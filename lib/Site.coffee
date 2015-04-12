# Site
Config = require './Config'
fs = require 'fs'
path = require 'path'
SUtil = require './misc'
url = require 'url'
Set = require 'Set'
Server = require './Server'
trans = require './trans'
nodeStatic = require 'node-static'
md5 = require 'MD5'
ejs = require 'ejs'
querystring = require 'querystring'



class Site extends Server
  ###
  Proxy Site
  ###

  ###
  Init site root directory
  ###
  @init: (root) ->
    copyFolder __dirname+"/tpl",root

  ###
  Run inited site, you must do Site.init(root) first
  ###
  @run: (root) ->
    site = require(path.join(root,'site.js'))
    site.run()


  root: ''
  ###
  @param {String} p Site root path
  ###
  constructor: (p) ->
    @root = p
    config = require(path.join(p,Config.filename))
    if config.baseUrlFile
      baseUrlFile = if @root && config.baseUrlFile[0]!='/'
                      path.join(@root,config.baseUrlFile)
                    else
                      config.baseUrlFile
      baseUrlList = fs.readFileSync(baseUrlFile,{encoding:"utf-8"})
      config.baseUrlList = misc.trim(baseUrlList).split(/\s+/g)
      delete config.baseUrlFile

    @config = new Config(config)
    @config.root = @root
    super {timeout:@config.timeout}

    @config.manifest = @config.api + 'manifest.appcache'
    @config.version = calcVersion @root
    @_initTemplates()
    @withTextBody({mime:/\btext\/(html|css)\b/i,match:matchRewriteCond})

    defaultMiddlewares = [
      'prepare','serveProxiteStatic','serveAppcache','serveStatus',
      'rewriteCSS','rewriteHTML','ignoreHeaders','xforward']
    this[mw]() for mw in defaultMiddlewares


  _initTemplates: () ->
    m = {
      manifest: 'manifest.appcache',
      main: 'main.html'
    }
    tpl = {}
    for k,v of m
      tpl[k] = ejs.compile(fs.readFileSync(path.join(@root,v),{encoding:'utf-8'}))

    @config._tpl = tpl

copyFolder = (from,to) ->
  for f in fs.readdirSync from
    src = path.join from,f
    target = path.join to,f
    if fs.statSync(src).isDirectory()
      fs.mkdirSync target if !fs.existsSync(target)
      copyFolder src,target
    else
      copyFile src,target if !fs.existsSync(target)

copyFile = (src,target) ->
  data = fs.readFileSync src
  fs.writeFileSync target,data


calcVersion = (dir) ->
  versions = []
  for f in fs.readdirSync dir
    f = path.join dir,f
    if fs.statSync(f).isDirectory()
      versions.push(calcVersion f)
    else
      versions.push(md5(fs.readFileSync(f)))

  return md5(versions+"")


badRequest = (res, msg = '') ->
  res.writeHead(400)
  res.end("<h1>400 Bad Request</h1><p>#{msg}</p>")

forbidden = (res, msg = '') ->
  res.writeHead(403)
  res.end("<h1>403 Forbidden</h1><p>#{msg}</p>")


###
Supported Proxy API Actions, i.e. /-proxite-/$action/
###
supportedProxyActions = new Set(['css','raw','iframe','static','status','manifest.appcache'])

PROXITE_XHR_HEADER = 'x-proxite-xhr' # indicate request issued by WeedProxite XMLHttpRequest wrapper
matchRewriteCond = (req) ->
  req.proxyAction != 'raw' &&
  !req.headers['x-requested-with'] &&
  !req.headers[PROXITE_XHR_HEADER]


_reqIgnoreHeaders = [ # hide headers to upstream
  'Accept-Encoding',
  'Connection',
  'Fastly-Client',
  'Fastly-Client-IP',
  'Fastly-FF',
  'Fastly-Orig-Host',
  'Fastly-SSL',
  'X-Forwarded-Host',
  'X-Forwarded-Server',
  'X-Varnish',
  'Via',
  'X-Amz-Cf-Id',
  PROXITE_XHR_HEADER
].map (s)-> s.toLowerCase()

_resIgnoreHeaders = [ # remove headers from upstream
  'X-Original-Content-Encoding'
].map (s)-> s.toLowerCase()

Site.middleware =
  ignoreHeaders: () ->
    reqHeaders = _reqIgnoreHeaders
    resHeaders = _resIgnoreHeaders
    unless @config.enableCookie
      reqHeaders = reqHeaders.concat(["cookie"])
      resHeaders = resHeaders.concat(["set-cookie"])

    return @use {
      before:(req,res,next,opt) ->
        for h in reqHeaders
          delete opt.headers[h] if opt.headers[h]
        next()
      after:(proxyRes,res,next) ->
        for h in resHeaders
          delete proxyRes.headers[h] if proxyRes.headers[h]
        next()
    }

  rewriteCSS: () ->
    config = @config
    return @use {
      mime:'text/css',
      match: matchRewriteCond
      after: (proxyRes,res,next,proxyReq,req) ->
        proxyRes.body = trans.css(proxyRes.body,req.baseRoot,config)
        next()
    }

  rewriteHTML: () ->
    config = @config
    return @use {
      mime:'text/html',
      match: matchRewriteCond
      after: (proxyRes,res,next,proxyReq,req) ->
        body = proxyRes.body
        config.pageContent = body
        config.charset = req.charset || config.upstreamDefaultCharset
        body = config._tpl.main({config:config})
        proxyRes.body = body
        next()
    }

  serveProxiteStatic: () ->
    staticServer = new nodeStatic.Server(
                      path.join(@config.root,'static'),
                      {serverInfo:'ProxiteStatic'})
    return @use {
      match: (req) -> req.proxyAction == 'static'
      before: (req,res,next,opt) ->
        req.url = opt.path
        return staticServer.serve(req,res)
    }

  serveAppcache: () ->
    config = @config
    return @use {
      match: (req) -> req.proxyAction == 'manifest.appcache'
      before: (req,res) ->
        res.writeHead(200,{
          # If set Cache-Control:no-cache,firefox will ignore appcache
          'cache-control':'max-age=0',
          'content-type':'text/cache-manifest',
          'access-control-allow-origin':'*'  # For JS to ping
        })
        qs = querystring.parse(url.parse(req.url).query)
        clientVersion = qs.version
        if clientVersion && clientVersion != config.version
          config.version = (+new Date)/300000|0  # five minutes stamp
        body = config._tpl.manifest({config:config})
        return res.end(body)
    }

  serveStatus: () ->
    return @use {
      match: (req) -> req.proxyAction == 'status'
      before: (req,res) ->
        return badRequest('Status API not implemented yet!')
    }

  prepare: () ->
    config = @config
    return @use {
      before: (req,res,next,opt) ->
        # sometimes browser will reduce '/http://www' to '/http:/www'
        opt.path = opt.path.replace /^([^?]*\/https?:\/)([^\/].+)/i,'$1/$2' # fixDoubleSlash
        reverted = trans.revertUrl(opt.path,config)
        action = req.proxyAction = reverted.action
        if action && !supportedProxyActions.has(action)
          return badRequest(res,"Invalid Proxy API Action: #{action};\n URL: #{req.url}" )

        target = url.parse reverted.target
        if !config.allowHost target.host
          return forbidden(res, 'Forbidden Host: ' + target.host)
        req.baseRoot = reverted.baseRoot
        opt.headers.host = opt.host = target.host
        opt.protocol = target.protocol
        opt.path = target.path
        next()

      ###
      Relocation
      ###
      after: (proxyRes,res,next,proxyReq,req) ->
        location = proxyRes.headers.location
        return next() unless location
        proxyRes.headers.location  = trans.url location,req.baseRoot,config
        next()
    }

Site.prototype[k]=v for k,v of Site.middleware


module.exports = Site



