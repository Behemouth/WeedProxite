#!/usr/bin/env coffee
WeedProxite = require('WeedProxite')
Site = WeedProxite.Site
misc = WeedProxite.misc

main = (host,port)->
  site = new Site(__dirname)
  site.run(host,port)
  return site


exports.main = main

main() if require.main == module


