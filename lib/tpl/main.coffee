#!/usr/bin/env coffee
WeedProxite = require('WeedProxite')
Site = WeedProxite.Site
misc = WeedProxite.misc

main = (host,port)->
  host ||= process.env.host
  port ||= process.env.port
  site = new Site(__dirname)

  if site.config.showJiathis
    site.use {
      host:'v3.jiathis.com',
      mime:'text/html',
      before: (req,res,next)->
        # don't display jiathis in itself
        req.localConfig.showJiathis = false;
        # req.localConfig.disableRewriteHTML = true;
        req.localConfig.enableAppcache = false;
        next();
    }


  site.useDefault()
  site.run(host,port)
  return site


module.exports = main
argv = process.argv
###
 Run as `node main.js localhost 1984`
###
main(argv[2],argv[3]) if require.main == module


