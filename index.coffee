# Silly index.

WeedProxite = {}

for m in ['Server','Site','Middleware','Config','misc','rewrite']
  WeedProxite[m] = require('./lib/'+m)

module.exports = WeedProxite
