
###
Replace page content
Usage:

  replaceBody = require('WeedProxite/middlewares/replaceBody')
  site.use({
    after:replaceBody(/find/g,'substitution')
  })
  // Or bulk replace
  site.use({
    after:replaceBody(
      [/find/g,'substitution'],
      [/a/g,'b']
    )
  })
###

rewriteBody = require('./rewriteBody')
replaceBody = (subs...) ->
  if subs.length == 2 and typeof subs[1] == 'string'
    subs = [subs]

  return rewriteBody (body)->
      for sub in subs
        if typeof sub[0] == 'string'
          body = body.split(sub[0]).join(sub[1])
        else
          body = body.replace sub[0],sub[1]

      return body


module.exports = replaceBody
