###
Config
###
misc = require './misc'

class Config
  # Upstream
  # e.g. http://www.example.com
  # @required
  upstream: ""
  upstreamDefaultCharset: ""

  # Override HTTP Cache Control header
  # See: https://www.fastly.com/blog/stale-while-revalidate/
  cacheControl:{
    maxAge: 60
    staleIfError: 86400
    staleWhileRevalidate: 600
  }

  texts:{
    title: "Mirror Site",
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
  Proxy server base url list file path
  each url seperated by newline, url must ends with '/'
  Default is relative to site root dir
  If not specified, use request host instead
  ###
  baseUrlsFile: "base_urls.txt"

  ###
  You can specify either `baseUrlsFile` or `baseUrlList`,but can not both of them
  For example:[
    "http: //proxite.lo.cal/",
    "http: //localhost/proxite/"
  ]
  baseUrlList = misc.trim(fs.readFileSync($ROOT+"/base_urls.txt",{encoding:"utf-8"})).split(/\s+/g)
  ###
  baseUrlList: []

  # Display a message to notice users this is a mirror site
  showMirrorNotice: true

  # Enable cookie on this mirror site
  enableCookie: false

  # Enable HTML5 applicationCache
  enableAppcache:true


  ###
  Path reserved as  WeedProxite API: /-proxite-/$action/$url
  Example:
    CSS proxy path" /-proxite-/css/
    Iframe proxy: /-proxite-/iframe/
    Raw content direct proxy path: /-proxite-/raw/
    Serve static files under "$siteRoot/static" directory: /-proxite-/static/
    Status: /-proxite-/status/
  Target url appended; e.g. /-proxite-/raw/http://example.com/logo.png
  So it's easy to use nginx proxy_pass for '/-proxite-/raw/'
  ###
  api: '/-proxite-/'

  # Proxy server bind host
  host: '127.0.0.1'
  # Proxy server listen port
  port: 1984

  @filename: 'config.js'

  ###
  @param {Object} config
  ###
  constructor: (config) ->
    @allowHosts = []
    for own key, value of config
      if key[0] != '_' && typeof this[key]!='function'
        this[key] = value

    @upstream = @upstream.slice(0,-1) if @upstream.slice(-1) =='/'

    @_upstreamHost = /^https?:\/\/([^\/]+)/.exec(@upstream)[1]
    @allowHosts.push(@_upstreamHost)

    @_allowHostsMap = {}
    for host in @allowHosts
      host = host.toLowerCase()
      @_allowHostsMap[host] = host

  allowHost: (host) ->
    ([host,port] = host.split ':') if (misc.suffixOf ':80',host) || (misc.suffixOf ':443',host)
    !!@_allowHostsMap.hasOwnProperty host

  isUpstreamHost: (host) -> host == @_upstreamHost

  isProxyAPI: (urlpath) -> misc.prefixOf @api,urlpath

  toClient: () ->
    ignore = {baseUrlsFile:1,host:1,port:1,root:1}
    a = {}
    for k,v of this
      if !ignore[k] && k[0]!='_' && typeof this[k]!='function'
        a[k] = v
    return a





module.exports = Config