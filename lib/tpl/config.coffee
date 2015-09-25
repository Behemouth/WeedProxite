# More config options please see `WeedProxite/lib/Config.coffee`

module.exports = {
  "upstream": "http://example.com",
  # "upstreamDefaultCharset": "UTF-8",
  # "defaultPageTitle":"Your Site Page Title",
  "port": "1984",
  "host": "127.0.0.1",
  "allowHosts":[
    # "sub.example.com"
  ],

  "ensureExternalLinkProtocol": "auto",

  # Display a message to notice users this is a mirror site
  # showMirrorNotice: true,

  # Enable cookie on this mirror site
  # enableCookie: false,

  # Enable HTML5 applicationCache
  # enableAppcache:true,

  # Enalbe Jiathis social share widget
  # enableShareWidget: false,

  "mirrorCollectionLinks": [
    "https://github.com/greatfire/wiki",
    "https://bitbucket.org/greatfire/wiki"
  ],


  # You can specify either mirrorLinksFile or mirrorLinks
  # "mirrorLinksFile": "alt_mirror_urls.txt",
  # You mirror site's links
  "mirrorLinks": ["http://proxite.lo.cal:1984/"]
}
