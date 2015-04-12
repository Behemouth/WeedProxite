#!/usr/bin/env coffee

Site = require('WeedProxite').Site;

run = ()->
  site = new Site(__dirname)
  console.log("Server running...")
  site.listen(1984)


exports.run = run;

run() if require.main == module


