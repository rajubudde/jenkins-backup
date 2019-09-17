logger = require "logger-sharelatex"

module.exports =
	startDrain: (io, rate) ->
		# Clear out any old interval
		clearInterval @interval
		if rate == 0
			return
		else if rate < 1
			# allow lower drain rates
			# e.g. rate=0.1 will drain one client every 10 seconds
			pollingInterval = 1000 / rate
			rate = 1
		else
			pollingInterval = 1000
		@interval = setInterval () =>
			@reconnectNClients(io, rate)
		, pollingInterval

	RECONNECTED_CLIENTS: {}
	reconnectNClients: (io, N) ->
		drainedCount = 0
		for client in io.sockets.clients()
			if !@RECONNECTED_CLIENTS[client.id]
				@RECONNECTED_CLIENTS[client.id] = true
				logger.log {client_id: client.id}, "Asking client to reconnect gracefully"
				client.emit "reconnectGracefully"
				drainedCount++
			haveDrainedNClients = (drainedCount == N)
			if haveDrainedNClients
				break
		if drainedCount < N
			logger.log "All clients have been told to reconnectGracefully"