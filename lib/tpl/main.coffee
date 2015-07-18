#!/usr/bin/env coffee
WeedProxite = require('WeedProxite')
Site = WeedProxite.Site
misc = WeedProxite.misc

main = (host,port)->
  site = new Site(__dirname)
  site.useDefault()
  site.run(host,port)
  return site


module.exports = main
argv = process.argv
###
 Run as `node site.js localhost 8080`
###
main(argv[2],argv[3]) if require.main == module


