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

  ###
  Append to mirror landing page body end
  ###
  htmlBodyAppendix: ''


  ###
  If wildly full text regex replace links likely allowed to relative no matter whether it is valid link
  For example, 'example.com' is in allowHosts,
  if set rewriteLinkWildly to true, then html:
    <p rel="http://example.com/meta.xml">https://example.com/meta.xml</p>
    <script>var link='http:\/\/example.com\/'</script>
  will be rewrited to
    <p rel="/http-colon-//example.com/meta.xml">/https-colon//example.com/meta.xml</p>
    <script>var link='\/http-colon-\/\/example.com\/'</script>
  ###
  # Not implemented yet
  # rewriteLinkWildly: false


  ###
  Debug option, in debug mode the client will load uncompressed bundle.js
  ###
  debug:false

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
  Ensure all extenal http links are using auto protocol or https
  Enum(auto|https|off)

  auto: Change non-https link to auto protocol
  https: Force all non-https link to https
  off: No change
  ###
  ensureExternalLinkProtocol : 'auto'


  ###
  Proxy server alt mirror base url list file path or remote url
  each url seperated by newline

  mirrorLinksFile: "alt_base_urls.txt"

  Same as
  mirrorLinks = misc.trim(fs.readFileSync("./alt_base_urls.txt",{encoding:"utf-8"})).split(/\s+/g)

  Format:
    https://one.mirror-domain.com/
    https://two.mirror-domain.com/

  Or plain domains,default https:
    one.mirror-domain.com
    two.mirror-domain.com

  mirrorLinksFile could be also a remote url which obeys Centrice GET API:
  See: https://github.com/Behemouth/centrice

  For example: https://centrice-domain-server-ip/domains/mirror-name/
  ###
  mirrorLinksFile: ""

  # Rank visitors by their visit frequency, this options only works with Centrice API mirrorLinksFile
  rankVisitors: false
  # How many page views cause rank upgrade
  rankMissionLevel: 10

  ###
  mirrorLinksFile Interval refresh in Minutes
  Default update per 30 minutes,set to zero to disable it
  Only make sense when set mirrorLinksFile option
  ###
  mirrorLinksFileRefresh: 30

  ###
  You can specify either `mirrorLinksFile` or `mirrorLinks`,but can not set both of them
  For example:[
    "http: //proxite.lo.cal/",
    "http: //localhost:1984/"
  ]

  Or plain domains:["one.mirror-domain.com","two.mirror-domain.com"]
  ###
  mirrorLinks: []

  # Used on mirror landing page and notice
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
  # @deprecated
  # httpsOptions: null

  ###
  @param {Object} config
  ###
  constructor: (config) ->
    @allowHosts = []
    for own key, value of config
      if key[0] != '_' && typeof this[key]!='function'
        this[key] = value

    @setSelfLinks(@mirrorLinks)

    @upstream = @upstream.slice(0,-1) if @upstream.slice(-1) =='/'
    [scheme,host] = misc.parseUrl(@upstream)
    @upstreamHost = host
    @upstreamScheme = scheme
    @allowHosts.push(@upstreamHost)

    @_allowHostsMap = {}
    @addAllowHosts(@allowHosts)

  setSelfLinks: (links) ->
    return unless links.length
    links = _normalizeLinks(links)

    _selfHosts = (misc.parseUrl(url)[1] for url in links)
    @_selfHostsMap = {}
    for host in _selfHosts
      @_selfHostsMap[host.toLowerCase()]=1

  setPublicLinks: (links) ->
    @mirrorLinks = _normalizeLinks(links)

  addAllowHosts: (hosts) ->
    @allowHosts.push.apply(@allowHosts,hosts)
    for host in hosts
      host = host.toLowerCase()
      @_allowHostsMap[host] = 1

  allowHost: (host) -> # HostString -> Bool
    #([host,port] = host.split ':') if (misc.suffixOf ':80',host) || (misc.suffixOf ':443',host)
    @_allowHostsMap.hasOwnProperty host

  # return true if host in baseUrlList or is upstream
  isSelfHost: (host) ->
    @_selfHostsMap.hasOwnProperty host



  isUpstreamHost: (host) -> host == @upstreamHost

  isProxyAPI: (urlpath) -> misc.prefixOf @api,urlpath

  toClient: () ->
    ignore = {
      host:1,port:1,root:1,httpsOptions:1,
      mirrorLinksFile:1,rankMissionLevel:1
    }
    a = {}
    for k,v of this
      if !ignore[k] && k[0]!='_' && typeof this[k]!='function'
        a[k] = v
    return a


_normalizeLinks = (links) ->
  for url in links
    url = if !~url.indexOf('//') then 'https://'+url+'/' else url
    if url.slice(-1)!='/' then url+'/' else url


module.exports = Config
