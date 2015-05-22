url = require 'url'
###
Proxy all requests to target host
@param {String} target "http://www.example.com" or host only "www.example.com"
@param {Boolean} relocation upstream response "Location" header if it is full href
###
retarget = (target,relocation=true) ->
  if ~target.indexOf('://')
    target =  url.parse target
    targetHost = target.host
    targetProtocol = target.protocol
  else
    targetHost = target
    targetProtocol = null
  return {
    name: 'retarget'
    before:(req,res,next,opt) ->
      opt.headers.host = opt.host = targetHost
      opt.protocol = targetProtocol if targetProtocol
      next()
    after:(proxyRes,res,next,_,req) ->
      location = proxyRes.headers.location
      return next() unless relocation && location
      href = location
      if href.slice(0,2) == "//"
        # "//example.com/" is valid but url.parse not handle correctly
        href = "http:" + href
      return next() unless ~href.indexOf("://")
      p = url.parse href
      if p.host == targetHost
        proxyRes.headers.location  = p.path
      next()
  }

module.exports = retarget
