
###
Usage:
enableSocialShare = require('WeedProxite/middlewares/enableSocialShare')
enableSocialShare(site)
###

replaceBody = require('./replaceBody')

module.exports = (site) ->
  site.config.addAllowHosts(['v3.jiathis.com','lc.jiathis.com','id.jiathis.com'])
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

  site.use {
    host:'v3.jiathis.com',
    path:'/code/plugin.client.js'
    mime:/javascript/i,
    after:  replaceBody(
              [/:\/\//g, '//'],
              ['|http|', '|/http-colon-|'],
            )
  }
