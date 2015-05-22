enableServerDestroy = (server) ->
  #  WTF Server#close(). There is no other way to force shutdown server!
  connections = {}

  server.on 'connection', (conn) ->
    key = conn.remoteAddress + ':' + conn.remotePort
    connections[key] = conn
    conn.on 'close', () ->
      delete connections[key]

  server.destroy = (cb) ->
    server.close(cb)
    for key of connections
      connections[key].destroy()


module.exports = enableServerDestroy
