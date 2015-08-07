
module.exports = {
  upstream: "http://example.com",
  # upstreamDefaultCharset: "UTF-8",
  # defaultPageTitle:'Your Site Page Title',
  port: process.env.port || 1984,
  allowHosts:[
    # 'sub.example.com'
  ],


  # Display a message to notice users this is a mirror site
  # showMirrorNotice: true,

  # Enable cookie on this mirror site
  # enableCookie: false,

  # Enable HTML5 applicationCache
  # enableAppcache:true,

  # Display Jiathis social share button
  # showJiathis: false,


  mirrorCollectionLinks:["http://some-host.com/your-org/bookmark"],

  # You can specify either  mirrorLinksFile or mirrorLinks
  # mirrorLinksFile: "alt_mirror_urls.txt",
  mirrorLinks: ["http://proxite.lo.cal:1984/"]
}
