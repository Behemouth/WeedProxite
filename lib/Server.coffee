# Server
debug = require('debug')('WeedProxite:Server')
debugHeader = require('debug')('WeedProxite:Server:header')
http = require 'http'
https = require 'https'
misc = require './misc'
fs = require 'fs'
url = require 'url'
Middleware = require './Middleware'
EventEmitter = (require 'events').EventEmitter
iconv = require 'iconv-lite'
contentType = require 'content-type'
finalhandler = require 'finalhandler'
bodyParser = require 'body-parser'


###
request(IncomingMessage) extended properties:
    protocol: Enum(http:|https:)  # Because Node.js URLObject mimiced window.location object
    origin: String # try get self origin from X-Forwarded-Host headers
    host: String   # X-Forwarded-Host | req.headers.host
    charset: String|null  # charset get from Content-Type header
###
extendRequest = (req)->
  # When serve as browser's http proxy
  # request.url will become full href
  reqUrl = url.parse(req.url)
  req.protocol = (reqUrl.protocol || (if hasEncryptedConnection(req) then 'https:' else 'http:'))
  req.url = reqUrl.path
  req.charset = getCharset req
  host = (req.headers['x-forwarded-host'] || '').split(',')[0] || req.headers.host
  proto = (req.headers['x-forwarded-proto'] || '').split(',')[0] || req.protocol.slice(0,-1)
  req.host = host
  req.origin = proto + '://' + host


###
proxyResponse(IncomingMessage) extended properties:
    charset: String|null # charset get from Content-Type header
    withTextBody: (options,next)
        Options {
          defaultCharset:"utf-8",
          limit:"2mb" # size limit
        }

        next(err,body:String)
###
extendProxyResponse = (proxyRes)->
  proxyRes.charset = getCharset proxyRes
  proxyRes.withTextBody = _withTextBody




class Server extends EventEmitter
  ###
  Basic Proxy Server

  Events:
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
      (req,res,[error])
  ###

  @defaultConfig: {
    xforward:true,
    timeout: 30000, # miliseconds
  }

  @_server:null
  @_running:false
  ###
  @param {Object} config
  @option  timeout
  @option  xforward
  @option httpsOptions  pass to https.createServer
  ###
  constructor: (config) ->
    super
    @timeout = config?.timeout || Server.defaultConfig.timeout
    @_middlewares = []
    @use(xforward) unless config?.xforward==false
    @_httpsOptions = config?.httpsOptions


  ###
  Same params as http/https.Server#listen()
  ###
  listen: (port,host) ->
    throw new Error('Server is already running!') if @_server

    handler = (req,res) => @_handle(req,res)
    @_server =  if @_httpsOptions
                  https.createServer(@_httpsOptions,handler)
                else
                  http.createServer(handler)

    # old Node.js version like 0.10 https Server doesn't have setTimeout
    @_server.setTimeout @timeout if @_server.setTimeout

    listenOn = if typeof host == 'string' then host + ':' + port else port
    debug('Server listen on ' + listenOn)
    @_server.listen.apply @_server,arguments

  close: (cb) ->
    debug('Server closing')
    return if !@_server
    @_server.close ()=>
                      cb && cb()
                      @emit('close')
    @_server = null


  ###
  Use middlewares, compatible with connect().use()

  opt = {
    before:function (req,res,next,proxyReqOpt) {
      var opt = proxyReqOpt;
      //change to target upstream host,remember to change Host header
      opt.headers.host = opt.host = "www.upstream.com"
      next(); // ** remember to invoke `next` **
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
      # connect().use() middleware four arity function(err,req,res,next) is error handler
      @_middlewares.push(new Middleware {before:route,isErrorHandler: route.arity == 4})
    else if args.length == 2  && typeof route == 'string' && typeof fn == 'function'
      # connect.use style two arg,mount middleware
      @_middlewares.push new Middleware {route:route,before:fn}
    else
      # otherwise all are Middleware or options
      args = args.map (m) -> if m instanceof Middleware then  m else  new Middleware(m)
      @_middlewares.push.apply @_middlewares,args

    return this

  _handle: (req,res) ->
    debug('Server #'+misc.id(this)+' handle incoming request:'+req.url)
    req.setTimeout @timeout
    extendRequest(req)
    proxyReqOpt = {
      protocol: req.protocol
      method: req.method
      host: ''
      path: req.url
    }

    headers = {}
    headers[k] = v for k,v of req.headers
    proxyReqOpt.headers = headers

    @emit('request',req,res,proxyReqOpt)
    @_prepareProxyRequest(req,res,proxyReqOpt)


  _prepareProxyRequest: (req,res,proxyReqOpt)->
    debugHeader('Initial request options:\n',proxyReqOpt)
    stackReq = @_middlewares.slice()
    stackRes = []
    error = null

    nextReq = (err) =>
      error = err || error # leave it to error handler middleware
      mw = stackReq.shift()
      return @_sendProxyRequest(error,req,res,proxyReqOpt,stackRes) unless mw
      return nextReq() unless mw._match req,res,proxyReqOpt
      stackRes.push mw
      runMiddleware mw,"_before",error,req,res,nextReq,proxyReqOpt

    return nextReq()


  _sendProxyRequest: (error,req,res,opt,stackRes) ->
    return @_finalHandle(req, res, error) if error
    debug("sendProxyRequest")
    debugHeader("Proxy request options:\n",opt)
    return @_finalHandle(req, res, new Error('Target host is empty!')) if !opt.host

    opt.protocol += ':' unless opt.protocol.slice(-1) == ':'
    sender = if opt.protocol == 'https:' then https else http
    [hostname,port] = opt.host.split ':'
    (port = if opt.protocol == 'https:' then '443' else '80') if !port
    opt.hostname = hostname; opt.port = port; delete opt.host

    prepareBody(opt)

    @emit('proxyRequest',req,res,opt)
    proxyReq = sender.request opt, (proxyRes) =>
                    debug('Upstream response')
                    debugHeader('Initial response headers:\n',proxyRes.headers)
                    extendProxyResponse(proxyRes)
                    @emit('proxyResponse',proxyRes,res,proxyReq,req)
                    @_prepareProxyResponse(proxyRes,res,proxyReq,req,stackRes)

    proxyReq.setTimeout @timeout, ()=>
                    debug("Proxy request timeout")
                    proxyReq.abort()
                    @emit('timeout',req,res,proxyReq)
                    e = new Error("Proxy Request Timeout")
                    e.status = 504
                    @_finalHandle(req,res,e)

    proxyReq.on 'error',(e) =>
                            debug("Proxy request error:",e)
                            @_finalHandle(req,res,e)

    if opt.body #TODO: recalculate content-length?
      proxyReq.end(opt.body)
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
    return @_finalHandle(error,req,res) if error
    prepareBody proxyRes

    for k,v of proxyRes.headers
      if v # Obsessive! Http Header Must Be Capitalized!
        # k = misc.capitalize(k)
        res.setHeader(k,v)
      else
        res.removeHeader(k)

    @emit('response',proxyRes,res,proxyReq,req)
    @emit('finally',req,res)
    res.writeHead(proxyRes.statusCode)
    if proxyRes.body
      res.end(proxyRes.body)
    else
      proxyRes.pipe(res)

  _finalHandle: (req,res,error) ->
    @emit('finally',req,res,error)
    finalhandler(req,res)(error)


runMiddleware = (mw,method,error,req,res,next,args...) ->
  if error && mw.isErrorHandler
    return mw[method].apply(mw,[error,req,res,next].concat args)
  else if !error && !mw.isErrorHandler
    return mw[method].apply(mw,[req,res,next].concat args)


###
Adds x-forward headers
###
xforward = {
  name: 'xforward'
  before: (req,res,next,opt) ->
    # Proxy standard headers.
    values = {
      for  : req.connection.remoteAddress || req.socket.remoteAddress,
      port : getPort(req),
      proto: req.protocol.slice(0,-1) # WTF url.parse(s).protocol contains colon
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




# Improved text body reader for proxy response
# withTextBody method of proxyResponse
_withTextBody = (opts,cb) ->
  if !cb
    cb = opts
    opts = null

  return cb(null,@body) if typeof @body == 'string'
  tryCharset = (@charset || opts?.defaultCharset || 'utf-8').toLowerCase()
  any = () -> true
  options = {
    type:any
    limit: opts?.limit || '2mb'
  }
  ct = @headers['content-type']
  _this = this
  decodeBody = (err) ->
    return cb(err) if err
    bodyBuffer = _this.body
    unless Buffer.isBuffer(bodyBuffer)
      _this.body = ""
      return cb(null,"") # doesn't have body
    body = iconv.decode bodyBuffer,tryCharset
    body = (body + " ").slice(0,-1) # work aroud Node.js buffer encoding bug
    _this.body = body
    # if charset specified with Content-Type,don't guess it again
    return cb(null,body) if _this.charset
    charset = getCharsetFromBodyByCT body,ct
    _this.charset = charset || tryCharset
    return cb(null,body) if !charset || charset==tryCharset
    body = iconv.decode bodyBuffer,charset
    body = (body + " ").slice(0,-1) # work aroud Node.js buffer encoding bug
    _this.body = body
    return cb(null,body)

  return decodeBody(null) if Buffer.isBuffer(@body)
  bodyParser.raw(options)(this,null,decodeBody)



###
Prepare body to send
@param {IncomingMessage} opt
opt.charset may be set by others
opt.headers
opt.body
###
prepareBody = (opt) ->
  body = opt.body
  delete opt.body
  return unless body?
  charset = (opt.charset || 'utf-8')
  body = iconv.encode(body,charset) if typeof body == 'string'
  return unless Buffer.isBuffer(body)
  delete opt.headers["content-encoding"]
  # since body have read,its length may have been changed too
  delete opt.headers["content-length"]
  opt.body = body


# getCharset from IncomingMessage header
getCharset = (im)-> try return contentType.parse(im).parameters.charset.toLowerCase()

# getCharset from IncomingMessage body by content-type
getCharsetFromBodyByCT = (body,ct)->
  return if !ct
  m = null
  if /\btext\/html\b/i.test(ct) && /<meta\s/i.test(body) && /<meta[^>]+charset=/i.test(body)
    # remove html comments and scripts,styles
    body = body.replace /<!--[^]*?-->|<script[^>]*>[^]*?<\/script>|<style[^>]*>[^]*?<\/style>/ig,""
    m = /<meta\s+[^>]+\btext\/html;\s+charset=([\w-]+)[^>]*>/i.exec body
    m = /<meta\s+charset=["']?([\w-]+)[^>]*>/i.exec body if !m
  else if /\btext\/css\b/i.test(ct) && /^@charset\s/im.test(body)
    body = body.replace /\/\*[^]*?\*\//g,"" # remove css comments
    m = /^@charset\s+["']([\w-]+)["']/im.exec body

  charset = (m?[1] || '').toLowerCase()
  charset = 'utf-8' if charset == 'utf7' || charset=='utf-7' # forbidden UTF-7
  return charset

getPort = (req) ->
  if req.headers.host
    p = req.headers.host.split(':')[1]
    return p if p

  return if hasEncryptedConnection(req) then '443' else '80';


hasEncryptedConnection = (req) ->
  return !!(req.connection.encrypted || req.connection.pair)




module.exports = Server



