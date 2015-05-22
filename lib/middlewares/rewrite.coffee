misc = require '../misc'
###
Rewrite path
@param {String|RegExp|Wildcard} pattern of path
@param {String} substitution Able to use group match result "$1" and
                               could be either path or full URI
@example
  rewrite("/static/*","http://static.cdn.com/$1")
  rewrite("/http://*","http://$1")
  rewrite(/^\/(.+)\.css\b(?:\?.*)?$/i,"/css-compress/$1.css")
###
rewrite = (pattern,substitution) ->
  pattern = misc.rewild pattern if typeof pattern == 'string'
  return {
    path: pattern
    before:(req,res,next,opt) ->
      target = req.url.replace  pattern,substitution
      target = url.parse target
      opt.path = target.path
      opt.protocol = target.protocol if target.protocol
      opt.host = target.host if target.host
      next()
  }

module.exports = rewrite
