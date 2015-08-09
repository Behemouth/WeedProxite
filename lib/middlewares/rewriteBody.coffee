
###
Rewrite page content
Usage:

  rewriteBody = require('WeedProxite/middlewares/rewriteBody')
  site.use({
    after:rewriteBody(function (body) {
      return body.replace('replace only once','once')
    })
  })
###

rewriteBody = (f) ->
  return (proxyRes,res,next) ->
    proxyRes.withTextBody (err,body)->
      return next(err) if err
      proxyRes.body = f(body)
      next()



module.exports = rewriteBody
