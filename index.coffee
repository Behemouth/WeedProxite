# Silly index.

WeedProxite = {}

for m in ['Server','Site','Middleware','Config','Client','misc','trans']
  WeedProxite[m] = require('./lib/'+m)

module.exports = WeedProxite
