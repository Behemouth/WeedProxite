Config = require './Config'
misc = require './misc'
rewrite = require './rewrite'

TIP_ID = 'WeedProxiteTip_JUST_MAGIC_BIT'
byId = (id) -> document.getElementById id

class Client
  constructor: (config) ->
    @config = new Config(config)
    @tip = byId(TIP_ID)
    if @tip
      @tipHTML = @tip.outerHTML.replace(/^\s*<div\b/i,'<div class="top"')

  run:() ->
    html = @config.pageContent
    html = rewrite.html(html,@config.proxyTarget.origin,@config)
    if @config.showMirrorNotice && @tipHTML
      html = html.replace /(<body\b[^>]*>)/ig,"$1"+@tipHTML

    writeDocument = ()->
        document.open()
        document.write(html)
        document.close()

    if document.readyState !='complete'
      window.onload = ()-> writeDocument()
    else
      writeDocument()



module.exports = Client

#if process.browser
if typeof window == 'object' # browserify will add fat process.js
  window.WeedProxite = {Client:Client}
