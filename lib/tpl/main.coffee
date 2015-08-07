#!/usr/bin/env coffee
WeedProxite = require('WeedProxite')
Site = WeedProxite.Site
misc = WeedProxite.misc

###
 Run as `node main.js localhost 1984`
###
if require.main == module
  argv = process.argv
  host = argv[2]
  port = argv[3]

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
