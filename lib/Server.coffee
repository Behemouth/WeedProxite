# Server
debug = require('debug')('WeedProxite:Server')
debugHeader = require('debug')('WeedProxite:Server:header')
http = require 'http'
https = require 'https'
misc = require './misc'
fs = require 'fs'
url = require 'url'
PWare = require './Middleware'
EventEmitter = (require 'events').EventEmitter
encoding = require 'encoding'
contentType = require 'content-type'
finalhandler = require 'finalhandler'
bodyParser = require 'body-parser'
compression = require 'compression'

class Server extends EventEmitter
  ###
  Basic Proxy Server

  Events:
    error:
      Emit before proxy request:
        (error,req,res,proxyReqOpt)
      Emit after proxy response:
        (error,req,res,proxyReq,proxyRes)
    timeout: Proxy request timeout
      (req,res,proxyReq)
    request: Request incoming,not run middlewares `before`
      (req,res,proxyReqOpt)
    proxyRequest: Send request upstream,already run all middlewares `before`
      (req,res,proxyReqOpt)
    proxyResponse: On upstream response, not run middlewares `after`
      (proxyRes,res,proxyReq,req)
    response: Response to client,already run middlewares `after`
      (proxyRes,res,proxyReq,req)
    finally: Emit on either normal response or error response, you can set some headers in this event
      (req,res,error)
  ###

  @defaultConfig: {
    timeout: 30000, # miliseconds
  }
  ###
  @param {Object} config
  ###
  constructor: (config) ->
    super
    @timeout = config.timeout || Server.defaultConfig.timeout
    @_middlewares = []

  ###
  Same params as http.Server#listen()
  ###
  listen: (port,host) ->
    if @_server
      throw new Error('Server already started!')
    @_server = http.createServer (req,res) => @_handle(req,res)
    @_server.setTimeout @timeout
    debug('Server listen on '+host+':'+port)
    @_server.listen.apply @_server,arguments

  close: (cb) ->
    debug('Server closed')
    return if !@_server
    @_server.close(cb)
    @_server = null
    @emit('close')

  ###
  Use middlewares, compatible with connect().use()

  opt = {
    before:function (req,res,next,proxyReqOpt) {
      var opt = proxyReqOpt;
      //change to target upstream host,remember to change Host header
      opt.headers.host = opt.host = "www.upstream.com"
      next(); // remember to invoke `next`
    }
  }

  server.use(opt) or server.use(new Middleware(opt))
  @match
    Same as connect().use
    @param {Function} fn As `before` handler
  @match
    Same as connect().use
    @param {String} route Mount point
    @param {Function} fn As `before` handler
  @match
    @param {Middleware...} middlewares or its constructor options

  ###
  use: (route,fn) ->
    args = Array.prototype.slice.call arguments
    # connect.use style one arg
    if args.length == 1 and typeof route == 'function'
      # connect().use() middleware function(err,req,res,next) is error handler
      @_middlewares.push(new PWare {before:route,isErrorHandler: route.arity == 4})
    else if args.length == 2  && typeof route == 'string' && typeof fn == 'function'
      # connect.use style two arg,mount middleware
      @_middlewares.push new PWare {route:route,before:fn}
    else
      # otherwise all are Middleware or options
      args = args.map (m) ->
                      if m instanceof PWare then return m
                      else return new PWare(m)
      @_middlewares.push.apply @_middlewares,args

    return this



  _handle: (req,res) ->
    debug('Server #'+misc.id(this)+' handle incoming request:'+req.url)
    req.setTimeout @timeout
    # When serve as browser http proxy
    # request.url will become full URI
    reqUrl = url.parse(req.url)
    req.protocol = reqUrl.protocol || (if req.connection.encrypted then 'https' else 'http')
    req.url = reqUrl.path
    proxyReqOpt =
      protocol: req.protocol
      method: req.method
      host: reqUrl.host || req.headers.host
      path: req.url

    headers = {}
    headers[k] = v for own k,v of req.headers
    proxyReqOpt.headers = headers

    @emit('request',req,res,proxyReqOpt)
    return @_prepareProxyRequest(req,res,proxyReqOpt)


  _prepareProxyRequest: (req,res,proxyReqOpt)->
    debugHeader('Initial request options:\n'+JSON.stringify(proxyReqOpt,null,2))
    stackReq = @_middlewares.slice()
    stackRes = []
    error = null

    nextReq = (err) =>
      error = err || error # leave it to error handler middleware
      mw = stackReq.shift()
      return @_sendProxyRequest(error,req,res,proxyReqOpt,stackRes) unless mw
      return nextReq() unless mw._match req,res,proxyReqOpt

      stackRes.push mw
      passReq = req
      if mw.mount
        # if mount point is "/static/",
        # for "/static/logo.png",middleware will get req.url "/logo.png"
        subUrl = req.url.slice(mw.route.length)
        if subUrl[0] != '/'
          subUrl = '/' + subUrl
        passReq = misc.clone req,{url:subUrl}
      runMiddleware mw,"_before",error,passReq,res,nextReq,proxyReqOpt

    return nextReq()


  _sendProxyRequest: (error,req,res,opt,stackRes) ->
    debug("sendProxyRequest")
    if error
      @emit('error',error,req,res,opt)
      return @_finalHandle(req, res, error)

    debugHeader("Proxy request options:\n",JSON.stringify(opt,null,2))
    opt.protocol += ':' unless opt.protocol.slice(-1) == ':'
    sender = if opt.protocol == 'https:' then https else http
    [hostname,port] = opt.host.split ':'
    (port = if opt.protocol == 'https:' then '443' else '80') if !port
    opt.hostname = hostname; opt.port = port; delete opt.host
    body = prepareBody(opt)

    @emit('proxyRequest',req,res,opt)
    proxyReq = sender.request opt,
                  (proxyRes) =>
                    debug('Upstream response')
                    debugHeader('Initial response headers:'+JSON.stringify(proxyRes.headers,null,2))
                    @emit('proxyResponse',proxyRes,res,proxyReq,req)
                    @_prepareProxyResponse(proxyRes,res,proxyReq,req,stackRes)

    onTimeout = ()=>
                  debug("Proxy request timeout")
                  proxyReq.abort()
                  @emit('timeout',req,res,proxyReq)
                  e = new Error("Proxy Request Timeout")
                  e.status = 504
                  @_finalHandle(req,res,e)
    proxyReq.setTimeout @timeout,onTimeout

    onError = (e) =>
                debug("Proxy request error:"+e.message)
                @emit('error',e,req,res,proxyReq)
                @_finalHandle(req,res,e)
    proxyReq.on 'error',onError

    if body #TODO: recalculate content-length
      proxyReq.end(body)
    else
      req.pipe(proxyReq)

  _prepareProxyResponse:(proxyRes,res,proxyReq,req,stackRes) ->
    error = null
    nextRes = (err) =>
      error = err || error
      mw = stackRes.shift()
      return @_sendProxyResponse(error,proxyRes,res,proxyReq,req) unless mw
      runMiddleware mw,"_after",error,proxyRes,res,nextRes,proxyReq,req

    nextRes()


  _sendProxyResponse: (error,proxyRes,res,proxyReq,req) ->
    debug("sendProxyResponse")
    if error
      @emit('error',error,req,res,proxyReq,proxyRes)
      return @_finalHandle(error,req,res)
    body = prepareBody proxyRes
    @emit('response',proxyRes,res,proxyReq,req)
    for k,v of proxyRes.headers
      if v # Obsessive! Http Header Must Be Capitalize!
        res.setHeader(misc.capitalize(k),v)
      else
        res.removeHeader(k)

    @emit('finally',req,res)

    res.writeHead(proxyRes.statusCode)
    if body
      res.end(body)
    else
      proxyRes.pipe(res)

  _finalHandle: (req,res,error) ->
    @emit('finally',req,res,error)
    finalhandler(req,res)(error)


runMiddleware = (mw,method,error,req,res,next,args...) ->
  #debug("Run middleware #{method}:"+mw)
  if error && mw.isErrorHandler
    return mw[method].apply(mw,[error,req,res,next].concat args)
  else if !error && !mw.isErrorHandler
    return mw[method].apply(mw,[req,res,next].concat args)


###
Built-in middlewares
###
Server.middleware =
  ###
  Proxy all requests to target host
  @param {String} target "http://www.example.com" or host only "www.example.com"
  @param {Boolean} relocation upstream response "Location" header if it is full href
  ###
  retarget: (target,relocation=true) ->
    if ~target.indexOf('://')
      target =  url.parse target
      targetHost = target.host
      targetProtocol = target.protocol
    else
      targetHost = target
      targetProtocol = null
    return {
      before:(req,res,next,opt) ->
        opt.headers.host = opt.host = targetHost
        opt.protocol = targetProtocol || req.protocol
        next()
      after:(proxyRes,res,next,_,req) ->
        location = proxyRes.headers.location
        return next() unless relocation && location
        href = location
        autoProtocol = false
        if href.slice(0,2) == "//"
          # "//example.com/" is valid but url.parse not handle correctly
          href = "http:" + href
          autoProtocol = true
        return next() unless ~href.indexOf("://")
        p = url.parse href
        if p.host == targetHost
          p.host = req.headers.host
          if autoProtocol
            p.protocol = null
          proxyRes.headers.location  = url.format p
        next()
    }

  ###
  Rewrite path
  @param {String|RegExp|Wildcard} pattern of path
  @param {String} substitution Able to use group match result "$1" and
                                 could be either path or full URI
  @example
    rewrite("/static/*","http://static.cdn.com/$1")
    rewrite("/http://*","http://$1")
    rewrite(/^\/(.+)\.css\b(?:\?.*)?$/i,"/css-compress/$1.css")
  ###
  rewrite: (pattern,substitution) ->
    pattern = misc.rewild pattern if typeof pattern == 'string'
    return {
      path: pattern
      before:(req,res,next,opt) ->
        target = req.url.replace  pattern,substitution
        target = url.parse target
        opt.path = target.path
        opt.protocol = target.protocol || opt.protocol
        opt.host = target.host || opt.host
        next()
    }

  ###
  Adds x-forward headers
  ###
  xforward: () ->
    return {
      before: (req,res,next,opt) ->
        # Proxy standard headers.
        encrypted = req.isSpdy || req.connection.encrypted || req.connection.pair
        values = {
          for  : req.connection.remoteAddress || req.socket.remoteAddress,
          port : getPort(req),
          proto: if encrypted then 'https' else 'http'
        }
        headers = opt.headers

        ['for', 'port', 'proto'].forEach (header)->
          h = 'x-forwarded-' + header
          headers[h] = (if headers[h] then headers[h]+',' else '') + values[header]

        if !headers['x-real-ip']
          real_ip = headers['x-forwarded-for'];
          if real_ip
            # If multiple (command-separated) forwarded IPs, use the first one.
            headers['x-real-ip'] = real_ip.split(',')[0]

        next()
    }

  compress: ()-> compression()

  ###
  Improved text body parser for proxy response
  @param {Object} options extend to Middleware
    Extra options:
    {
      defaultCharset:"ISO-8859-1",
      limit:"2mb" // size limit
    }
  ###
  withTextBody: (opt) ->
    opt ?= {}
    defaultCharset = (opt.defaultCharset || "ISO-8859-1").toLowerCase()
    defaultCharset = "utf-8" if defaultCharset=="utf8"
    rawBody = bodyParser.raw({type:"*/*",limit:opt.limit || "2mb"})
    _match = opt.match
    delete opt.match
    delete opt.defaultCharset
    delete opt.limit
    mw = {
      match: (req) ->
        if req.method =='HEAD' || req.method =='DELETE'
          return false
        return _match.apply(this,arguments) if _match
        return true
      after: (proxyRes,res,next)->
        decodeBody = (err)->
          return next(err) if err
          body = proxyRes.body
          unless Buffer.isBuffer body
            proxyRes.body = ""
            return next()
          if defaultCharset == "utf-8"
            proxyRes.body = body.toString()
            return next()

          charset = getCharset proxyRes
          if !charset
            tmpBody = encoding.convert body,"utf-8",defaultCharset
            proxyRes.body = tmpBody.toString()
            charset = getCharsetFromBody proxyRes
          return next() unless charset
          try
            textBody = encoding.convert body,"utf-8",charset
          catch e
            return next(e)
          proxyRes.body = textBody.toString()
          proxyRes.charset = charset
          return next()

        rawBody(proxyRes,res,decodeBody)

    }
    opt.mime ?= /\b(?:text|javascript|xml)\b/i
    mw[k]=v for k,v of opt

    return mw




bindWare = (name,ware) ->
  Server.prototype[name] = ()->
    return @use(ware.apply(this,arguments))

for name,ware of Server.middleware
  bindWare(name,ware)


###
Prepare body to send
@param {http.IncomingMessage like Object} opt
opt.charset may be set by others
opt.headers
opt.body
###
prepareBody = (opt) ->
  body = opt.body

  return unless body?
  if typeof body == 'string'
    charset = opt.charset || getCharset(opt) || "utf-8"
    body = encoding.convert(body,charset)

  delete opt.headers["content-encoding"]
  # since body have read,it may have been changed too
  delete opt.headers["content-length"]
  return opt.body = (if !Buffer.isBuffer(body) then new Buffer("") else body)


getCharset = (req)->
  try
    charset = contentType.parse(req).parameters.charset.toLowerCase()
    return charset


getCharsetFromBody = (req)->
  ct = req.headers["content-type"]
  return if !ct
  body = req.body
  m = null
  if /\btext\/html\b/i.test ct
    # remove html comments and scripts
    body = body.replace /<!--[^]*?-->|<script[^>]*>[^]*?<\/script>/ig,""
    m = /<meta\s+[^>]+\btext\/html;\s+charset=([\w-]+)[^>]*>/i.exec body
    m = /<meta\s+charset=["']?([\w-]+)[^>]*>/i.exec body if !m
  else if /\btext\/css\b/i.test ct
    body = body.replace /\/\*[^]*?\*\//g,"" # remove css comments
    m = /^@charset\s+["']([\w-]+)["']/im.exec body

  return m[1] if m

getPort = (req) ->
  if req.headers.host
    p = req.headers.host.split(':')[1]
    return p if p

  return if hasEncryptedConnection(req) then '443' else '80';


hasEncryptedConnection = (req) ->
  return !!(req.connection.encrypted || req.connection.pair)

module.exports = Server



