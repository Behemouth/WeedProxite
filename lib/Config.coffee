###
Config
###
misc = require './misc'

class Config
  # Upstream
  # e.g. http://www.example.com
  # @required
  upstream: ""
  upstreamDefaultCharset: "UTF-8"

  defaultPageTitle:'Page Title'

  # Override HTTP Cache Control header
  # See: https://www.fastly.com/blog/stale-while-revalidate/
  cacheControl:{
    maxAge: 60
    staleIfError: 86400
    staleWhileRevalidate: 600
  }

  # Some texts used on mirror landing page
  texts:{
    append_title: " | Mirror Site",
    loading: "Loading...",
    if_website_fails: "If the website fails to load, you may be able to find another mirror URL here:"
  }

  # Default timeout in miliseconds
  timeout: 30000

  ###
  Allowed other hosts,domain:port
  e.g. ["img.example.com","api.example.com:8080"]
  @type [String]
  ###
  allowHosts : []

  ###
  Proxy server alt mirror base url list file path
  each url seperated by newline, url must ends with '/'

  mirrorLinksFile: "alt_mirror_urls.txt"
  ###
  mirrorLinksFile: ""

  ###
  You can specify either `mirrorLinksFile` or `mirrorLinks`,but can not set both of them
  For example:[
    "http: //proxite.lo.cal/",
    "http: //localhost:1984/"
  ]
  mirrorLinks = misc.trim(fs.readFileSync("./alt_mirror_urls.txt",{encoding:"utf-8"})).split(/\s+/g)
  ###
  mirrorLinks: []

  # Used on mirror landing page and tip
  mirrorCollectionLinks:null

  # Display a message to notice users this is a mirror site
  showMirrorNotice: true

  # Enable cookie on this mirror site
  enableCookie: false

  # Enable HTML5 applicationCache
  enableAppcache:true

  useMemcache:false


  ###
  Path reserved as  WeedProxite API: /-proxite-/$action/$url
  Example:
    Serve static files under "$siteRoot/static" directory: /-proxite-/static/
    Status: /-proxite-/status/
    Appcache Manifest: /-proxite-/manifest.appcache
  ###
  api: '/-proxite-/'

  ###
  URL query string param name reserved to control output type
  Example: "/path/a.html?_WeedProxiteCtrl=raw" will output original html content without rewrite
  Value Enum(raw|iframe)
  ###
  outputCtrlParamName: '_WeedProxiteCtrl'

  # Proxy server bind host
  host: '127.0.0.1'
  # Proxy server listen port
  port: 1984

  # Use https server,pass these options to https.createServer(opts)
  httpsOptions: null

  ###
  @param {Object} config
  ###
  constructor: (config) ->
    @allowHosts = []
    for own key, value of config
      if key[0] != '_' && typeof this[key]!='function'
        this[key] = value

    @upstream = @upstream.slice(0,-1) if @upstream.slice(-1) =='/'

    @_selfHosts = (misc.parseUrl(url)[1] for url in @mirrorLinks)
    @_selfHostsMap = {}
    for host in @_selfHosts
      @_selfHostsMap[host.toLowerCase()]=1

    [scheme,host] = misc.parseUrl(@upstream)
    @upstreamHost = host
    @upstreamScheme = scheme
    @allowHosts.push(@upstreamHost)

    @_allowHostsMap = {}
    for host in @allowHosts
      host = host.toLowerCase()
      @_allowHostsMap[host] = 1

  allowHost: (host) ->
    #([host,port] = host.split ':') if (misc.suffixOf ':80',host) || (misc.suffixOf ':443',host)
    !!@_allowHostsMap.hasOwnProperty host

  # return true if host in baseUrlList or is upstream
  isSelfHost: (host) ->
    !!@_selfHostsMap.hasOwnProperty host



  isUpstreamHost: (host) -> host == @upstreamHost

  isProxyAPI: (urlpath) -> misc.prefixOf @api,urlpath

  toClient: () ->
    ignore = {mirrorLinksFile:1,host:1,port:1,root:1,httpsOptions:1}
    a = {}
    for k,v of this
      if !ignore[k] && k[0]!='_' && typeof this[k]!='function'
        a[k] = v
    return a





module.exports = Config
