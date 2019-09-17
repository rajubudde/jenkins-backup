metrics = require "metrics-sharelatex"
logger = require "logger-sharelatex"
settings = require "settings-sharelatex"
WebsocketController = require "./WebsocketController"
HttpController = require "./HttpController"
HttpApiController = require "./HttpApiController"
Utils = require "./Utils"
bodyParser = require "body-parser"

basicAuth = require('basic-auth-connect')
httpAuth = basicAuth (user, pass)->
	isValid = user == settings.internal.realTime.user and pass == settings.internal.realTime.pass
	if !isValid
		logger.err user:user, pass:pass, "invalid login details"
	return isValid

module.exports = Router =
	_handleError: (callback = ((error) ->), error, client, method, extraAttrs = {}) ->
		Utils.getClientAttributes client, ["project_id", "doc_id", "user_id"], (_, attrs) ->
			for key, value of extraAttrs
				attrs[key] = value
			attrs.client_id = client.id
			attrs.err = error
			if error.message in ["not authorized", "doc updater could not load requested ops", "no project_id found on client"]
				logger.warn attrs, error.message
				return callback {message: error.message}
			else
				logger.error attrs, "server side error in #{method}"
				# Don't return raw error to prevent leaking server side info
				return callback {message: "Something went wrong in real-time service"}

	configure: (app, io, session) ->
		app.set("io", io)
		app.get "/clients", HttpController.getConnectedClients
		app.get "/clients/:client_id", HttpController.getConnectedClient

		app.post "/project/:project_id/message/:message", httpAuth, bodyParser.json(limit: "5mb"), HttpApiController.sendMessage
		
		app.post "/drain", httpAuth, HttpApiController.startDrain

		session.on 'connection', (error, client, session) ->
			if client? and error?.message?.match(/could not look up session by key/)
				logger.warn err: error, client: client?, session: session?, "invalid session"
				# tell the client to reauthenticate if it has an invalid session key
				client.emit("connectionRejected", {message: "invalid session"})
				client.disconnect()
				return

			if error?
				logger.err err: error, client: client?, session: session?, "error when client connected"
				client?.emit("connectionRejected", {message: "error"})
				client?.disconnect()
				return

			# send positive confirmation that the client has a valid connection
			client.emit("connectionAccepted")

			metrics.inc('socket-io.connection')

			logger.log session: session, client_id: client.id, "client connected"

			if session?.passport?.user?
				user = session.passport.user
			else if session?.user?
				user = session.user
			else
				user = {_id: "anonymous-user"}

			client.on "joinProject", (data = {}, callback) ->
				if data.anonymousAccessToken
					user.anonymousAccessToken = data.anonymousAccessToken
				WebsocketController.joinProject client, user, data.project_id, (err, args...) ->
					if err?
						Router._handleError callback, err, client, "joinProject", {project_id: data.project_id, user_id: user?.id}
					else
						callback(null, args...)

			client.on "disconnect", () ->
				metrics.inc('socket-io.disconnect')
				WebsocketController.leaveProject io, client, (err) ->
					if err?
						Router._handleError null, err, client, "leaveProject"

			# Variadic. The possible arguments:
			# doc_id, callback
			# doc_id, fromVersion, callback
			# doc_id, options, callback
			# doc_id, fromVersion, options, callback
			client.on "joinDoc", (doc_id, fromVersion, options, callback) ->
				if typeof fromVersion == "function" and !options
					callback = fromVersion
					fromVersion = -1
					options = {}
				else if typeof fromVersion == "number" and typeof options == "function"
					callback = options
					options = {}
				else if typeof fromVersion == "object" and typeof options == "function"
					callback = options
					options = fromVersion
					fromVersion = -1
				else if typeof fromVersion == "number" and typeof options == "object"
					# Called with 4 args, things are as expected
				else
					logger.error { arguments: arguments }, "unexpected arguments"
					return callback?(new Error("unexpected arguments"))

				WebsocketController.joinDoc client, doc_id, fromVersion, options, (err, args...) ->
					if err?
						Router._handleError callback, err, client, "joinDoc", {doc_id, fromVersion}
					else
						callback(null, args...)

			client.on "leaveDoc", (doc_id, callback) ->
				WebsocketController.leaveDoc client, doc_id, (err, args...) ->
					if err?
						Router._handleError callback, err, client, "leaveDoc"
					else
						callback(null, args...)

			client.on "clientTracking.getConnectedUsers", (callback = (error, users) ->) ->
				WebsocketController.getConnectedUsers client, (err, users) ->
					if err?
						Router._handleError callback, err, client, "clientTracking.getConnectedUsers"
					else
						callback(null, users)

			client.on "clientTracking.updatePosition", (cursorData, callback = (error) ->) ->
				WebsocketController.updateClientPosition client, cursorData, (err) ->
					if err?
						Router._handleError callback, err, client, "clientTracking.updatePosition"
					else
						callback()

			client.on "applyOtUpdate", (doc_id, update, callback = (error) ->) ->
				WebsocketController.applyOtUpdate client, doc_id, update, (err) ->
					if err?
						Router._handleError callback, err, client, "applyOtUpdate", {doc_id, update}
					else
						callback()
