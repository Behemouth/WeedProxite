###
Content transformer
###
URL = require 'url'

trans =
  ###
  Transform path to proxy url
  @param {String} path     e.g. 'http://upstream.com/' or  '//upstream.com/' or relative '../'
  @param {String} baseRoot e.g. "/"
                           or "/http://subdomain.upstream.com/"
                           or "/-proxite-/css/http://subdomain.upstream.com/"

  ###
  url:(path,baseRoot,config) ->
    p = path
    # "//example.com/" is valid but url.parse not handle correctly
    p = 'http:'+p if p.slice(0,2) == '//'
    if /^https?:\//i.test p
      p = URL.parse p
      if config.allowHost p.host
        return baseRoot + p
    else if p[0]=='/'
      return baseRoot + p.slice(1)

    return path # remain unchange


  ###
  Revert target url from path
  @return {
    // either '/path/'(default upstream) or 'http://subdomain.upstream.com/path/'
    target:String,
    baseRoot:String, // see `trans.url`
    action:Enum(raw|css|iframe|static|status|manifest.appcache)
  }
  ###
  revertUrl:(p,config) ->
    baseRoot = ''
    action = ''
    target = p
    if config.isProxyAPI p
      parts = (p.slice config.api.length).split('/')
      action = parts[0].split('?')[0]
      target = '/' + parts.slice(1).join '/'
      baseRoot = config.api + action + '/'

    if /^\/https?:/i.test target
      baseRoot += target.exec(/^\/(https?:\/\/[^\/]+\/)/i)[1]
      target = target.slice 1
    else
      baseRoot = '/'
      target = config.upstream + target

    return {target:target,baseRoot:baseRoot,action:action}

  css:(css,baseRoot,config) ->
    return css
  html:(html,baseRoot,config) ->
    return html


module.exports = trans
