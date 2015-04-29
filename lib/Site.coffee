# Site
Config = require './Config'
fs = require 'fs'
path = require 'path'
SUtil = require './misc'
url = require 'url'
Set = require 'Set'
Server = require './Server'
rewrite = require './rewrite'
nodeStatic = require 'node-static'
md5 = require 'MD5'
ejs = require 'ejs'
querystring = require 'querystring'
misc = require './misc'
getRawBody = require('raw-body')
LRU = require("lru-cache")
debug = require('debug')('WeedProxite:Site')


class Site extends Server
  ###
  Proxy Site
  ###

  ###
  Init site root directory
  ###
  @init: (root,override) ->
    copyFolder __dirname+"/tpl",root,override

  ###
  Run inited site, you must do Site.init(root) first
  ###
  @run: (root,host,port) ->
    site = require(path.join(root,'site.js'))
    return site.main(host,port)


  root: ''
  ###
  @param {String} p Site root path
  ###
  constructor: (p) ->
    @root = p
    config = require(path.join(p,'config.js'))
    if config.mirrorLinksFile
      mirrorLinksFile = if @root && config.mirrorLinksFile[0]!='/'
                          path.join(@root,config.mirrorLinksFile)
                        else
                          config.mirrorLinksFile
      mirrorLinks = fs.readFileSync(mirrorLinksFile,{encoding:"utf-8"})
      config.mirrorLinks = misc.trim(mirrorLinks).split(/\s+/g)

    @config = new Config(config)
    @config.root = @root
    super {timeout:@config.timeout}

    @config.manifest = @config.api + 'manifest.appcache'
    @config.version = calcVersion @root
    @_initTemplates()
    @withTextBody({
      defaultCharset: @config.upstreamDefaultCharset,
      match: matchRewriteCond
    })

    defaultMiddlewares = [
      'prepare','serveProxiteStatic','serveAppcache','serveStatus',
      'rewriteCSS','rewriteHTML','ignoreHeaders','xforward']
    this[mw]() for mw in defaultMiddlewares


    if @config.useMemcache
      @_cache = LRU({
                      max:300,
                      maxAge:1000*60*60 # one hour
                    })
      @useCache(@_cache)


  run: (host,port)->
    host ?= @config.host
    port ?= @config.port
    @listen(port,host)
    console.log "Site serving on #{host}:#{port}..."

  ###
  Use simple cache
  ###
  useCache: (cache)->
    # throw new Error('Not Implemented yet!')
    config = @config
    onRes = (proxyRes,res) ->
              return unless res.cacheKey && !proxyRes.shouldNotCache
              debug('Set cache:',res.cacheKey)
              item = {
                body:proxyRes.body,
                statusCode:proxyRes.statusCode,
                headers:proxyRes.headers
              }

              item = JSON.stringify item
              cache.set res.cacheKey,item

    @on 'response',onRes
    return @use {
      method:'GET'
      before:(req,res,next,opt) =>
        h = opt.headers
        key = [ opt.protocol,opt.host,opt.path,
                h.cookie,h[(h.vary || '').toLowerCase()],
                h['accept'],h['accept-encoding'],h['accept-language']
              ]

        key = key.join(',')
        res.cacheKey = key
        result = cache.get(key)
        if result
          debug('Cache hit:',key)
          result = JSON.parse(result)
          res.writeHead(result.statusCode,result.headers)
          res.end(new Buffer(result.body))
          return

        return next()
      after:(proxyRes,res,next)=>
        if proxyRes.statusCode >= 300
          proxyRes.shouldNotCache = true
          return next()

        return next() if proxyRes.body
        setBody = (err,body) ->
                    if err
                      proxyRes.shouldNotCache = true
                      return next()

                    proxyRes.body = body
                    next()


        getRawBody  proxyRes, {limit:'2mb'},setBody

    }

  _initTemplates: () ->
    m = {
      manifest: 'manifest.appcache',
      main: 'main.html'
    }
    tpl = {}
    for k,v of m
      tpl[k] = ejs.compile(fs.readFileSync(path.join(@root,v),{encoding:'utf-8'}))

    @config._tpl = tpl

copyFolder = (from,to,override) ->
  for f in fs.readdirSync from
    src = path.join from,f
    target = path.join to,f
    if fs.statSync(src).isDirectory()
      fs.mkdirSync target if !fs.existsSync(target)
      copyFolder src,target,override
    else
      name = path.basename(target)
      if !fs.existsSync(target) || (override && name!='config.js' && name!='site.js')
        copyFile src,target

copyFile = (src,target) ->
  # skip coffee script source code
  return if /\.coffee$|\.js\.map$/i.test src
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
supportedProxyActions = new Set(['raw','iframe','static','status','manifest.appcache'])

PROXITE_XHR_HEADER = 'x-proxite-xhr' # indicate request issued by WeedProxite XMLHttpRequest wrapper
matchRewriteCond = (req) ->
  req.proxyAction != 'raw' &&
  !req.headers['x-requested-with'] &&
  !req.headers[PROXITE_XHR_HEADER]

normalCacheHeader = (res,config)->
  cacheCtrl = config.cacheControl
  cacheCtrl = 'max-age=' + cacheCtrl.maxAge +
                ', stale-while-revalidate=' + cacheCtrl.staleWhileRevalidate +
                ', stale-if-error=' + cacheCtrl.staleIfError;

  res.setHeader('Cache-Control', cacheCtrl)
# Make sure to send these security headers are included in all responses.
# See: https://securityheaders.com/
secureHeaders = {
  'X-Content-Type-Options':'nosniff'
  'X-Download-Options':'noopen'
  'X-XSS-Protection':'1; mode=block'
}

_reqIgnoreHeaders = [ # hide headers to upstream
  'Accept-Encoding',
  #'Connection',
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
        proxyRes.body = rewrite.css(proxyRes.body,req.proxyTarget.origin,config)
        next()
    }

  rewriteHTML: () ->
    config = @config
    return @use {
      mime:'text/html',
      match: (req) ->
        return false if !~(req.headers.accept || '').indexOf('text/html')
        return matchRewriteCond.apply(this,arguments)

      after: (proxyRes,res,next,proxyReq,req) ->
        return next() if proxyRes.statusCode >=400 || proxyRes.statusCode < 200

        headers = proxyRes.headers
        #delete headers['expires'] # for firexo
        #delete headers['last-modified']
        delete headers['cache-control'] # use default cache control
        delete headers['pragma'] if headers['pragma']=='no-cache'
        configData = config.toClient()
        body = proxyRes.body
        configData.pageTitle = /<title[^<>]*>([^<>]*)<\/title>/i.exec(body)?[1] || config.defaultPageTitle
        configData.pageContent = body
        configData.proxyTarget = req.proxyTarget
        configData.showMirrorNotice = false if req.method != 'GET'
        configData.enableAppcache = false if req.proxyAction == 'iframe' || req.method !='GET'
        configData.charset = proxyRes.charset || config.upstreamDefaultCharset
        configData.json = misc.escapeUnicode(JSON.stringify(configData).replace(/<\/script>/ig,'<\\/script>'))
        body = config._tpl.main({config:configData})
        proxyRes.body = body
        next()
    }

  serveCrossDomainXML: () ->
    return @use {
      mime:/\bxml\b/i,
      after: (proxyRes,res,next,_,req) ->
        body = proxyRes.body
        origin = req.origin
        endTag = '</cross-domain-policy>'
        return unless ~body.indexOf(endTag)
        et = new RegExp(endTag,'g')
        body = body.replace(et,'<site-control permitted-cross-domain-policies="master-only"/>'+endTag)
        body = body.replace(et,'<allow-http-request-headers-from domain="'+origin+'" headers="*"/>'+endTag)
        body = body.replace(et,'<allow-access-from domain="'+origin+'"/>'+endTag)
        proxyRes.body = body
        next()
    }

  serveProxiteStatic: () ->
    staticServer = new nodeStatic.Server(
                      path.join(@config.root,'static'),
                      {serverInfo:'Static'})
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
          # See Appcache Facts:  http://appcache.offline.technology/
          'Cache-Control':'max-age=0',
          'Content-Type':'text/cache-manifest',
          'Access-Control-Allow-Origin':'*'  # For JS to ping
        })
        qs = querystring.parse(url.parse(req.url).query)
        clientVersion = qs.version
        configData = config.toClient()
        if clientVersion && clientVersion != configData.version
          configData.version = (+new Date)/60000|0  # one minute stamp
        body = config._tpl.manifest({config:configData})
        return res.end(body)
    }

  serveStatus: () ->
    return @use {
      match: (req) -> req.proxyAction == 'status'
      before: (req,res) ->
        return badRequest(res,'Status API not implemented yet!')
    }

  prepare: () ->
    config = @config
    return @use {
      before: (req,res,next,opt) ->
        # sometimes browser will reduce '/http://www' to '/http:/www'
        opt.path = opt.path.replace /^([^?]*\/https?:\/)([^\/].+)/i,'$1/$2' # fixDoubleSlash
        reverted = rewrite.revertUrl(opt.path,config)
        action = req.proxyAction = reverted.action
        if action? && !supportedProxyActions.has(action)
          return badRequest(res,"Invalid Proxy API Action: #{action};\n URL: #{req.url}" )


        target = url.parse(reverted.url)
        if !reverted.allowed
          return forbidden(res, 'Forbidden Host: ' + target.host)
        if !reverted.isDefault && config.isUpstreamHost target.host && !action
          # redirect "/http://default-upstream-host/path/" to "/path/"
          res.writeHead(301,{location: target.path})
          return res.end()

        req.proxyTarget = reverted



        origin = req.headers.origin || req.headers.referer
        req.origin = (origin && /^https?:\/\/[^\/]+/.exec(origin)?[0]) || (req.protocol+'://'+req.headers.host)

        opt.headers.host = opt.host = target.host
        opt.protocol = target.protocol
        opt.path = target.path

        normalCacheHeader(res,config)
        res.setHeader('Access-Control-Allow-Origin',req.origin)
        res.setHeader('Access-Control-Allow-Headers','Origin, X-Requested-With, Content-Type, Accept')
        res.setHeader(k,v) for k,v of secureHeaders

        `var path;` # Holly shit
        for h in ['origin','referer']
          v = opt.headers[h]
          continue unless v
          {host,path} = url.parse(v)
          if host == req.headers.host || config.isSelfHost host
            opt.headers[h] = rewrite.revertUrl(path,config).url

        next()

      ###
      Relocation
      ###
      after: (proxyRes,res,next,proxyReq,req) ->
        proxyRes.headers[k]=v for k,v of secureHeaders

        location = proxyRes.headers.location
        return next() unless location
        proxyRes.headers.location  = rewrite.url location,req.proxyTarget.origin,config
        return next()
    }

Site.prototype[k]=v for k,v of Site.middleware


module.exports = Site



