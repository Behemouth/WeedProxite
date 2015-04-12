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

class Server
  ###
  Basic Proxy Server
  ###

  @defaultConfig: {
    timeout: 30000, # miliseconds
  }
  ###
  @param {Object} config
  ###
  constructor: (config) ->
    EventEmitter.call this
    @timeout = config.timeout || Server.defaultConfig.timeout
    @_middlewares = []

  ###
  Same params as http.Server#listen()
  ###
  listen: (port) ->
    @_server = http.createServer (req,res) => @_handle(req,res)
    @_server.setTimeout @timeout
    debug('Server listen on:'+port)
    @_server.listen.apply @_server,arguments

  close: () ->
    debug('Server closed')
    return if !@_server
    @_server.close()
    @_server = null

  ###
  Use middlewares, compatible with connect().use()

  opt = {
    before:function (req,res,next,proxyRequestOptions) {
      var opt = proxyRequestOptions;
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
      @_middlewares.push(new PWare {before:route,_isErrorHandler: route.arity == 4})
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
    debug('Incoming request:'+req.url)
    stackReq = @_middlewares.slice()
    stackRes = []
    req.setTimeout @timeout
    # When serve as browser http proxy
    # request.url will become full URI
    reqUrl = url.parse(req.url)
    req.protocol = reqUrl.protocol || (if req.connection.encrypted then 'https' else 'http')
    req.url = reqUrl.path
    proxyRequestOptions =
      protocol: req.protocol
      method: req.method
      host: reqUrl.host || req.headers.host
      path: req.url

    headers = {}
    headers[k] = v for own k,v of req.headers
    proxyRequestOptions.headers = headers
    proxyReq = null
    proxyRes = null
    error = null
    _done = finalhandler(req, res)
    done = (err) ->
      console.log "Done Error:",err
      _done.apply(this,arguments)
    debugHeader('Initial request options:\n'+JSON.stringify(proxyRequestOptions,null,2))

    nextReq = (err) ->
      error = err || error
      mw = stackReq.shift()
      return sendProxyRequest() unless mw
      return nextReq() unless mw._match req,res,proxyRequestOptions

      stackRes.push mw
      passReq = req
      if mw.mount
        # if mount point is "/static/",
        # for "/static/logo.png",middleware will get req.url "/logo.png"
        subUrl = req.url.slice(mw.route.length)
        if subUrl[0] != '/'
          subUrl = '/' + subUrl
        passReq = misc.clone req,{url:subUrl}
      runMiddleware mw,"_before",passReq,res,nextReq,proxyRequestOptions

    nextRes = (err) ->
      error = err || error
      mw = stackRes.shift()
      return sendProxyResponse() unless mw
      runMiddleware mw,"_after",proxyRes,res,nextRes,proxyReq,req


    sendProxyRequest = () ->
      debug("sendProxyRequest")
      return done(error) if error
      opt = proxyRequestOptions
      debugHeader("Proxy request options:\n",JSON.stringify(opt,null,2))
      opt.protocol += ':' unless opt.protocol.slice(-1) == ':'
      sender = if opt.protocol == 'https:' then https else http
      [hostname,port] = opt.host.split ':'
      (port = if opt.protocol == 'https:' then '443' else '80') if !port
      delete opt.host
      opt.hostname = hostname
      opt.port = port
      body = prepareBody(opt)

      proxyReq = sender.request opt,
                    (upstreamRes) ->
                      debug('Upstream response')
                      proxyRes = upstreamRes
                      debugHeader('Initial response headers:'+JSON.stringify(proxyRes.headers,null,2))
                      nextRes()

      abortProxyReq = () ->
                        debug("Request aborted!")
                        proxyReq.abort()
      proxyReq.setTimeout @timeout, abortProxyReq
      req.on "aborted", abortProxyReq
      proxyReq.on "error",(e) ->
        debug("Proxy request error:"+e.message)
        res.writeHead(500)
        res.end("<p>"+e.message+"</p>")
      if body
        proxyReq.write(body)
        proxyReq.end()
      else
        req.pipe(proxyReq)

    sendProxyResponse = () ->
      debug("sendProxyResponse")
      return done(error) if error
      body = prepareBody proxyRes
      res.writeHead(proxyRes.statusCode,proxyRes.headers)
      if body
        res.write(body)
        res.end()
      else
        proxyRes.pipe(res)

    runMiddleware = (mw,method,req,res,next,args...) ->
      debug("Run middleware #{method}:"+mw)
      if error && mw._isErrorHandler
        return mw[method].apply(mw,[err,req,res,next].concat args)
      else
        return mw[method].apply(mw,[req,res,next].concat args)

    nextReq()


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
    Extra options
    {
      defaultCharset:"ISO-8859-1",
      limit:"1mb" // size limit
    }
  ###
  withTextBody: (opt) ->
    defaultCharset = (opt.defaultCharset || "ISO-8859-1").toLowerCase()
    defaultCharset = "utf-8" if defaultCharset=="utf8"
    rawBody = bodyParser.raw({type:"*/*",limit:opt.limit || "2mb"})
    delete opt.limit
    delete opt.defaultCharset
    mw = {
      after: (proxyReq,res,next)->
        decodeBody = (err)->
          return next(err) if err
          body = proxyReq.body
          unless Buffer.isBuffer body
            proxyReq.body = ""
            return next()
          if defaultCharset == "utf-8"
            proxyReq.body = body.toString()
            return next()

          charset = getCharset proxyReq
          if !charset
            tmpBody = encoding.convert body,"utf-8",defaultCharset
            proxyReq.body = tmpBody.toString()
            charset = getCharsetFromBody proxyReq
          return next() unless charset
          try
            textBody = encoding.convert body,"utf-8",charset
          catch e
            return next(e)
          proxyReq.body = textBody.toString()
          proxyReq.charset = charset
          return next()

        rawBody(proxyReq,res,decodeBody)

    }
    opt.mime = /\b(?:text|javascript)\b/i if !opt.mime

    mw[k]=v for own k,v of opt
    return mw




bindWare = (name,ware) ->
  Server.prototype[name] = ()->
    return @use(ware.apply(this,arguments))

for own name,ware of Server.middleware
  bindWare(name,ware)


###
Prepare body to send
###
prepareBody = (opt) ->
  body = opt.body

  return unless body?
  if typeof body == 'string'
    charset = opt.charset || getCharset(opt) || "utf-8"
    console.log "prepareBody charset:",charset
    body = encoding.convert(body,charset)

  delete opt.headers["content-encoding"]
  # since body have read,it may have changed too
  delete opt.headers["content-length"]
  return  if !Buffer.isBuffer(body) then new Buffer("") else body


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
    body = body.replace /<!--[^]*?-->/g,"" # remove html comments
    m = /<[^>]+\btext\/html;\s+charset=([\w-]+)[^>]*>/i.exec body
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



