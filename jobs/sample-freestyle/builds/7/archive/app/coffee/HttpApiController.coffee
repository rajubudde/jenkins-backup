WebsocketLoadBalancer = require "./WebsocketLoadBalancer"
DrainManager = require "./DrainManager"
logger = require "logger-sharelatex"

module.exports = HttpApiController =
	sendMessage: (req, res, next) ->
		logger.log {message: req.params.message}, "sending message"
		if Array.isArray(req.body)
			for payload in req.body
				WebsocketLoadBalancer.emitToRoom req.params.project_id, req.params.message, payload
		else
			WebsocketLoadBalancer.emitToRoom req.params.project_id, req.params.message, req.body
		res.send 204 # No content
	
	startDrain: (req, res, next) ->
		io = req.app.get("io")
		rate = req.query.rate or "4"
		rate = parseFloat(rate) || 0
		logger.log {rate}, "setting client drain rate"
		DrainManager.startDrain io, rate
		res.send 204