# Site
Config = require './Config'
fs = require 'fs'
util = require 'util'
path = require 'path'
url = require 'url'
# Set = require 'Set'
Server = require './Server'
rewrite = require './rewrite'
nodeStatic = require 'node-static'
md5 = require 'md5'
ejs = require 'ejs'
querystring = require 'querystring'
misc = require './misc'
# LRU = require("lru-cache")
debug = require('debug')('WeedProxite:Site')
bodyParser = require 'body-parser'
http = require 'http'
https = require 'https'
Cookies = require 'cookies'
crypto = require 'crypto'
CRYPTO_ALGORITHM = 'AES-256-CTR'

# Special rank to skip
RESERVED_RANK = 9

_USER_RANK_COOKIE_NAME = 'weedproxite_urc'


encrypt = (text,password) ->
  cipher = crypto.createCipher(CRYPTO_ALGORITHM,password)
  crypted = cipher.update(text,'utf8','hex')
  crypted += cipher.final('hex')
  return crypted

decrypt = (text,password) ->
  try
    decipher = crypto.createDecipher(CRYPTO_ALGORITHM,password)
    dec = decipher.update(text,'hex','utf8')
    dec += decipher.final('utf8')
    return dec
  catch
    return ""



ajustUserRank = (req,res) ->
  config = req.localConfig
  password = config._cryptoPassword
  maxRank = config._domainsMap.up.maxRank
  rankLevel = config.rankMissionLevel

  value = req.cookies.get(_USER_RANK_COOKIE_NAME) + ""
  value = decrypt(value,password) + ""
  value = +value.slice(4) # 4 random padding
  value = +value || 0
  value += 1
  rank = (value / rankLevel) | 0

  (rank = maxRank) if rank > maxRank
  if rank == 0
    config.setPublicLinks(config._zeroRankLinks)
  else
    config.setPublicLinks(config._domainsMap.up[rank])
  config.guestRank = rank

  # console.log "Value:"+value+" Rank:"+rank

  value = encrypt((Math.random()*100000).toString(32).slice(0,4)+value,password)
  expires = new Date
  expires.setDate(expires.getDate()+3) # three day expires
  res.cookies.set(_USER_RANK_COOKIE_NAME,value,{expires:expires,path:"/"})


updateMirrorLinks = (config)->
  file = config.mirrorLinksFile
  setLinks = (data)->
    links = misc.trim(data).split(/\s+/g)
    config._zeroRankLinks = links
    config.setSelfLinks(links)
    config.setPublicLinks(links)

  if !~file.indexOf '//'
    readFile = () -> fs.readFile file, {encoding:"utf-8"}, onRead
    onRead = (err,data)->
      throw err if err
      setLinks(data)

    checkExists = (exists)->
                if not exists
                  throw new Error("Config mirrorLinksFile does not exist!")
                readFile()
    fs.exists file,checkExists
  else # Use Centrice API
    [scheme,_,_] = misc.parseUrl file
    sender = if scheme == 'https' then https else http
    any = () -> true
    groupByRank = (domains) ->
      map = {}
      maxRank = 0
      for d in domains
        continue if d.rank == RESERVED_RANK
        (maxRank = d.rank) if d.rank > maxRank
        (map[d.rank] = map[d.rank] || []).push d.domain

      map.maxRank = maxRank
      return map

    setDomainsMap = (domains) ->
      upDomains = domains.filter (p)-> not p.blocked
      downDomains = domains.filter (p)-> p.blocked
      config._domainsMap = {
        up: groupByRank upDomains
        down: groupByRank downDomains
      }

    onPublicLinksResponse = (res)->
      next = ()->
        setLinks(res.body)

      bodyParser.text({type:any})(res,null,next)


    onDetailResponse = (res)->
      next = (err)->
        if err
          config.rankVisitors = false
          console.error "Fetch all domains failed:"+err.message
        else
          setDomainsMap(res.body)

      bodyParser.json({type:any})(res,null,next)

    sender.get file+'?rank=0&status=up',onPublicLinksResponse
    sender.get file+'?rank=all&status=all&format=detail',onDetailResponse





class Site extends Server
  ###
  Proxy Site
  ###

  ###
  Init site root directory
  ###
  @init: (root,override) ->
    # copyFolder __dirname+"/tpl",root,override
    files = ['config.js','main.js']
    # staticDir = root + '/static'
    # fs.mkdirSync staticDir  if !fs.existsSync(staticDir)
    # if fs.existsSync(staticDir)
    #   copyFolder __dirname + "/tpl/static/" , staticDir , true
    for f in files
      copyFile __dirname + "/tpl/" + f , root + "/" + f

    copyFile __dirname + "/tpl/web.config" , root + "/web.config", true
    copyFile __dirname + "/tpl/package.json" , root + "/package.json", true


    return

  ###
  Run inited site, you must do Site.init(root) first
  ###
  @run: (root,host,port) ->
     # F**king process.env is not normal object, it will convert undefined to string 'undefined'
    process.env.host = host || ''
    process.env.port = port || ''
    return require(path.join(root,'main.js'))


  root: ''
  ###
  @param {String|Object} p Site root path string or config object
  ###
  constructor: (p) ->
    if typeof p == 'string'
      @root = p
      configJSFile = path.join(p,'config.js')
      configJSONFile = path.join(p,'config.json')
      config = {}
      if fs.existsSync(configJSFile)
        config = require(configJSFile)

      if fs.existsSync(configJSONFile)
        configJSONContent = fs.readFileSync(configJSONFile,'utf-8')
        try
          configJSON = eval('('+configJSONContent+')')
        catch e
          console.error("Config JSON file \"#{configJSONFile}\"  is not valid:\n"+e)
          throw e
        for key of configJSON
          config[key] = configJSON[key]


      if config.mirrorLinksFile
        file = config.mirrorLinksFile
        if !~file.indexOf('//') && file[0]!='/'
          file = path.join(@root,config.mirrorLinksFile)
        config.mirrorLinksFile = file

      if process.env.WEED_PROXITE_DEBUG
        config.debug = true

      @config = new Config(config)
      @config.root = @root
      if @config.mirrorLinksFile
        updateMirrorLinks(@config)
      if @config.mirrorLinksFileRefresh
        _refresh = ()=> updateMirrorLinks(@config)
        t = @config.mirrorLinksFileRefresh * 1000 * 60
        @_mirrorLinksFileRefreshTimer = setInterval _refresh, t
    else
      @config = new Config(p)
      @root = @config.root

    super {timeout:@config.timeout,xforward:true,httpsOptions:@config.httpsOptions}

    @config.manifest = @config.api + 'manifest.appcache'
    @config.version = calcVersion @root

    if @config.rankVisitors
      if !~@config.mirrorLinksFile.indexOf('//')
        throw new Error("Config#rankVisitors only works when set mirrorLinksFile to Centrice API")

      @config._cryptoPassword = Math.random().toString(36) + (+new Date) + Math.random().toString(36)


    # if fs.existsSync(path.join(@root,'static'))
    #   @_staticServer = new nodeStatic.Server(path.join(@root,'static'),{serverInfo:'Static'})
    # else
    #  @_staticServer = new nodeStatic.Server(path.join(__dirname,'tpl','static'),{serverInfo:'Static'})
    @_staticServer = new nodeStatic.Server(path.join(__dirname,'tpl','static'),{serverInfo:'NWS'})

    @_initTemplates()
    @use Cookies.express()
    @_prepare()

    #@config._outputCtrlQueryRe = new RegExp('\\b'+@config.outputCtrlParamName+'=[^=&?#]*','g')

  close: (cb)->
    clearInterval @_mirrorLinksFileRefreshTimer
    super cb

  useDefault: () ->
    @use rewriteCrossDomainXML
    @use rewriteCSS
    @use rewriteHTML

    ###
    if @config.useMemcache
      @_cache = LRU({max:300,maxAge:1000*60*60}) # one hour
      @useCache(@_cache)
    ###


  run: (host,port)->
    @runningHost = host || @config.host || process.env.host
    @runningPort = port || @config.port || process.env.port
    console.log "Site serving on #{@runningHost}:#{@runningPort}..."
    @listen(@runningPort,@runningHost)


  ###
  Use simple cache
  ###
  useCache: (cache)->
    throw new Error('useCache Not Implemented yet!')
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

  _handleProxyAPI:(req,res)->
    action = req.url.slice(@config.api.length).split(/\/|\?/)[0]
    if ProxiteAPI.hasOwnProperty(action)
      ProxiteAPI[action].call(this,req,res)
    else
      badRequest(res,"Invalid Proxy API Action: #{action};\n URL: #{req.url}" )

  _prepare: () ->
    originConfig = @config
    _this = this
    # ignore headers
    reqIgnoreHeaders = _reqIgnoreHeaders
    resIgnoreHeaders = _resIgnoreHeaders
    unless @config.enableCookie
      reqIgnoreHeaders = reqIgnoreHeaders.concat(["cookie"])
      resIgnoreHeaders = resIgnoreHeaders.concat(["set-cookie"])

    @use {
      before:(req,res,next,opt) ->
        req.localConfig = config = misc.clone originConfig

        if req.headers.origin # set access rules only when CORS request Origin header present
          res.setHeader('Access-Control-Allow-Origin',req.origin)
          res.setHeader('Access-Control-Allow-Headers','Origin, X-Requested-With, Content-Type, Accept')

        cacheCtrl = config.cacheControl
        res.setHeader 'Cache-Control', ('max-age=' + cacheCtrl.maxAge +
                                        ', stale-while-revalidate=' + cacheCtrl.staleWhileRevalidate +
                                        ', stale-if-error=' + cacheCtrl.staleIfError)

        return _this._handleProxyAPI(req,res) if config.isProxyAPI req.url

        result = revertParseUrl(opt.path,config)
        config.proxyTarget = target = result.target
        return forbidden(res,'Forbidden Host: '+target.host) if !result.allowed
        config.location = location = { path: req.url }
        location.baseRoot = result.baseRoot
        location.ctrlType = result.ctrlType

        # redirect "/http://default-upstream-host/path/?_WeedProxiteCtrl=x" to "/path/?_WeedProxiteCtrl=x"
        # return redirect(res,rewrite.addCtrlParam(target.path,config)) if result.redundant
        return redirect(res,target.path || '/') if result.redundant
        # redirect "/http://upstream" to "/http://upstream/"
        return redirect(res,req.url.replace(/($|\?)/,'/$1')) if target.path[0]!='/'

        opt.headers.host = opt.host = target.host
        opt.protocol = target.protocol
        opt.path = target.path || '/'

        res.setHeader(k,v) for k,v of secureHeaders
        for h in ['origin','referer']
          v = opt.headers[h]
          continue unless v
          [_,_host,_path] = misc.parseUrl(v)
          if _host == req.headers.host || _host == req.host || config.isSelfHost _host
            opt.headers[h] = revertUrl(_path,config)

        delete opt.headers[h] for h in reqIgnoreHeaders  #ignore headers

        next()

      ###
      Relocation
      ###
      after: (proxyRes,res,next,proxyReq,req) ->
        proxyRes.headers[k] = v for k,v of secureHeaders
        delete proxyRes.headers[h] for h in resIgnoreHeaders  #ignore headers
        location = proxyRes.headers.location
        return next() unless location
        location = rewrite.url location,req.localConfig
        if ! misc.isDomainUrl location # jumping to allowed domain
          location = rewrite.addCtrlParam(location,req.localConfig)
        proxyRes.headers.location = location
        return next()
    }

  _initTemplates: () ->
    tpl = {}
    mainTpl = 'main.html'
    clientJSFile = path.join(@root,'client.js')
    includeClientJSPlaceholder = '<!--#INCLUDE_CLIENT_JS#-->'
    if fs.existsSync(path.join(@root,mainTpl))
      tplFile = path.join(@root,mainTpl)
    else
      tplFile = path.join(__dirname,'tpl',mainTpl)

    tplStr = fs.readFileSync(tplFile,{encoding:'utf-8'})
    clientJS = ""

    if fs.existsSync(clientJSFile)
      clientJS = fs.readFileSync(clientJSFile,{encoding:'utf-8'})

    tplStr = tplStr.replace(includeClientJSPlaceholder,clientJS)

    tpl.main = ejs.compile(tplStr)
    manifestTpl = 'manifest.appcache'
    tpl.manifest = ejs.compile(fs.readFileSync(path.join(__dirname,'tpl',manifestTpl),{encoding:'utf-8'}))
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
      copyFile src,target,override

copyFile = (src,target,override) ->
  # skip coffee script source code
  # return if /\.coffee$|\.js\.map$/i.test src
  return if fs.existsSync(target) and not override
  data = fs.readFileSync src
  fs.writeFileSync target,data


calcVersion = (dir) ->
  versions = [
    _md5Folder dir,
    _md5Folder __dirname
  ]
  return md5(versions+"")

_md5Folder = (dir) ->
  versions = []
  for f in fs.readdirSync dir
    f = path.join dir,f
    if fs.statSync(f).isDirectory()
      versions.push(_md5Folder f)
    else
      versions.push(md5(fs.readFileSync(f)))
  return md5(versions+"")

badRequest = (res, msg = '') ->
  res.writeHead(400)
  res.end("<h1>400 Bad Request</h1><p>#{msg}</p>")

forbidden = (res, msg = '') ->
  res.writeHead(403)
  res.end("<h1>403 Forbidden</h1><p>#{msg}</p>")

redirect = (res,location) ->
  res.writeHead(301,{location: location })
  res.end()


###
Revert target url from req.url
@param {String} p  url path like '/http://www.upstream.com/a.html'
@param {Object} config
###
revertUrl = (p,config) ->
  if /^\/https?:/i.test p
    # sometimes browser will reduce '/http://www' to '/http:/www'
    return p.slice(1).replace /^(https?:\/)([^\/].+)$/i,'$1/$2' # fixDoubleSlash
  else
    return config.upstream + p


###
Revert parse target url from req.url
@param {String} p  url path like '/http://www.upstream.com/a.html'
@param {Object} config
@return {
  target:{
    host:String,
    path:String,
    protocol:Enum(http:|https:)
  },
  baseRoot:String, // '/' or '/$origin/', see `rewrite.url`
  ctrlType:String, //  e.g. raw|iframe in url query string '?_weedProxiteCtrl=iframe'
  allowed:Boolean, // if host is allowed
  // if target host is default upstream and specified host in url would be redundant
  // i.e. /http://default-upstream/path/  should be redirected to /path/
  redundant:Boolean
}
###
revertParseUrl = (p,config) ->
  `var path;`
  origin = ''; redundant = false; allowed = false;
  host = ''; path = ''; baseRoot = '/' ;
  ctrlType = ''
  if ~p.indexOf config.outputCtrlParamName
    u = url.parse(p)
    qs = querystring.parse(u.query)
    ctrlType = qs[config.outputCtrlParamName]

  if /-colon-/i.test p
    # Fix colon in url path caused error on Azure websites IIS
    p = p.replace(/-colon-/g,':')

  if /^\/https?:/i.test p
    p = revertUrl(p,config)
    [scheme,host,path] = misc.parseUrl p
    protocol = scheme + ':'
    origin = scheme + '://' + host
    baseRoot += origin + '/'
    allowed = config.allowHost host
    redundant = config.isUpstreamHost host
  else
    allowed = true
    host = config.upstreamHost
    path = p
    protocol = config.upstreamScheme + ':'
    p = config.upstream + p

  # path = path.replace(config._outputCtrlQueryRe,'') if ctrlType
  ctrlType = '' if ctrlType != 'iframe' && ctrlType != 'raw'

  return {
    target:{
      protocol: protocol,
      host:host, path:path,
    },
    ctrlType:ctrlType,
    baseRoot:baseRoot,
    allowed:allowed,
    redundant:redundant
  }



matchRewriteCond = (req) ->
  return false if req.method !='GET' && req.method !='POST'
  ctrlType = req.localConfig.location.ctrlType
  return false if ctrlType == 'raw'
  return false if req.headers['x-requested-with']
  return true


# Make sure to send these security headers are included in all responses.
# See: https://securityheaders.com/
secureHeaders = {
  'X-Content-Type-Options':'nosniff'
  'X-Download-Options':'noopen'
  'X-Frame-Options': 'sameorigin'
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
  'X-Amz-Cf-Id'
].map (s)-> s.toLowerCase()

_resIgnoreHeaders = [ # remove headers from upstream response
  'X-Original-Content-Encoding'
].map (s)-> s.toLowerCase()


rewriteCSS = {
  mime:'text/css',
  match: matchRewriteCond
  after: (proxyRes,res,next,proxyReq,req) ->
    cb = (err,body)->
      return next(err) if err
      proxyRes.body = rewrite.css(body,req.localConfig)
      next()

    proxyRes.withTextBody cb
}

rewriteHTML = {
  mime:'text/html',
  match: (req) ->
    # return false if !~(req.headers.accept || '').indexOf('text/html')
    return matchRewriteCond.apply(this,arguments)

  after: (proxyRes,res,next,proxyReq,req) ->
    config = req.localConfig
    return next() if config.disableRewriteHTML
    ctrlType = config.location.ctrlType
    if proxyRes.statusCode != 200 || req.method != 'GET' || ctrlType == 'iframe'
      config.enableAppcache = false
      config.showMirrorNotice = false

    headers = proxyRes.headers
    #delete headers['expires'] # for firefox
    #delete headers['last-modified']
    headers['cache-control']='' # use default cache control
    headers['pragma']='' if headers['pragma']=='no-cache'

    ajustUserRank(req,res) if config.rankVisitors

    cb = (err,body) ->
      return next(err) if err
      config.pageTitle = /<title[^<>]*>([^<>]*)<\/title>/i.exec(body)?[1] || config.defaultPageTitle
      config.pageContent = body
      config.charset = proxyRes.charset || config.upstreamDefaultCharset
      #config.json = misc.escapeUnicode(JSON.stringify(config.toClient()).replace(/<\/script>/ig,'<\\/script>'))
      config.json = JSON.stringify(config.toClient()).replace(/<\/script>/ig,'<\\/script>')
      proxyRes.body = config._tpl.main({config:config})
      next()

    proxyRes.withTextBody {defaultCharset:config.upstreamDefaultCharset},cb
}

rewriteCrossDomainXML =  {
  mime:/\bxml\b/i,
  after: (proxyRes,res,next,_,req) ->
    cb = (err,body) ->
      return next(err) if err
      origin = req.origin
      endTag = '</cross-domain-policy>'
      return next() unless ~body.indexOf(endTag)
      et = new RegExp(endTag,'g')
      body = body.replace(et,'<site-control permitted-cross-domain-policies="master-only"/>'+endTag)
      body = body.replace(et,'<allow-http-request-headers-from domain="'+origin+'" headers="*"/>'+endTag)
      body = body.replace(et,'<allow-access-from domain="'+origin+'"/>'+endTag)
      proxyRes.body = body
      next()

    proxyRes.withTextBody {defaultCharset:req.localConfig.upstreamDefaultCharset},cb

}



ProxiteAPI = {
  'static':(req,res,staticServer) ->
    req.url = req.url.slice(req.localConfig.api.length + 'static'.length)
    return @_staticServer.serve(req,res)
  'manifest.appcache':(req,res) ->
    config = req.localConfig
    unless config.enableAppcache
      res.writeHead(404)
      res.end()

    res.writeHead(200,{
      # If set Cache-Control:no-cache,firefox will ignore appcache
      # See Appcache Facts:  http://appcache.offline.technology/
      'Cache-Control':'max-age=0',
      'Content-Type':'text/cache-manifest',
      'Access-Control-Allow-Origin':'*'  # For JS to ping
    })
    qs = querystring.parse(url.parse(req.url).query)
    clientVersion = qs.version
    if clientVersion && clientVersion != config.version
      config.version = (+new Date)/180000|0  # three minutes stamp
    body = config._tpl.manifest({config:config})
    return res.end(body)
  'status': (req,res)->
    return badRequest(res,'Status API not implemented yet!')
}




module.exports = Site



