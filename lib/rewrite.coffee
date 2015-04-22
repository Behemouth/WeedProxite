###
Content rewrite
###
misc = require './misc'
HTMLRewriter = require './HTMLRewriter'

parseUrl = (url) -> # parse full uri, return [scheme,host,path]
  [_,scheme,host,path] = /^(https?):\/\/([\w\d.:-]+)(\/.*)?/i.exec(url) || []
  scheme ?= ''; host ?= ''; path ?= '/';
  return [scheme,host,path];


rewrite =
  ###
  Transform path to proxy url
  @param {String} path     e.g. 'http://upstream.com/' or  '//upstream.com/' or relative '../'
  either empty string indicate default upstream origin
  or "http://some-allowed-host"
  @param {String} origin
  @param {Config} config

  ###
  url:(p,origin,config) ->
    u = p
    # "//example.com/" is valid but url.parse not handle correctly
    u = 'http:'+u if u.slice(0,2) == '//'
    if /^https?:\//i.test u
      [_,host,path] = parseUrl u
      if config.allowHost host
        return if config.isUpstreamHost host then path else '/' + u
    else if u[0]=='/' and origin
      return '/' + origin + u

    return p # otherwise remain unchange


  ###
  Revert target url from path
  @return {
    // 'http://subdomain.upstream.com/path/'
    url:String,
    origin:String, // see `rewrite.url`
    allowed:Boolean, // if allowed host
    isDefault:Boolean, // if target is default upstream
    action:Enum(raw|css|iframe|static|status|manifest.appcache)
  }
  ###
  revertUrl:(p,config) ->
    origin = ''; action = ''; url = p
    isDefault = false; allowed = false
    if config.isProxyAPI p
      parts = (p.slice config.api.length).split('/')
      action = parts[0].split('?')[0]
      url = '/' + parts.slice(1).join '/'

    if /^\/https?:/i.test url
      [scheme,host,path] = parseUrl url
      origin = scheme + '://' + host
      allowed = config.allowHost host
      url = url.slice 1
    else
      isDefault = true
      allowed = true
      url = config.upstream + url

    return {
      url:url,origin:origin,
      action:action,allowed:allowed,
      isDefault:isDefault
    }

  css:(css,origin,config) ->
    replace = (m,url) -> m.replace url,(rewrite.url url,origin,config)
    css = css.replace /\burl\(['"]([^*'"]+)['"]\)/ig,replace
    css = css.replace /\burl\(([^*'"()\s]+)\)/ig,replace
    css = css.replace /@import\s+['"]([^*'"]+)['"]/ig,replace
    return css

  html:(html,origin,config) ->
    baseOrigin = origin
    rewriteBase = (href) -> # rewrite base tag first
                      u = rewrite.url href,origin,config
                      if /^https?:\/\//i.test u # should not proxy
                        baseOrigin = ''
                      return u

    rt = new HTMLRewriter(html)
    rt.rule({tag:'base',attr:'href',first:true,rewrite: rewriteBase})
    html = rt.result()

    ###
    TODO: Consider to use CloudFlare image proxy
    https://images.weserv.nl/?url=www.google.com/images/srpr/logo11w.png
    ###
    rt = new HTMLRewriter(html)
    reUrl = (src)->
      rewrite.url src,baseOrigin,config
    tags = 'img src|object data|applet src|embed src|audio src|video src|source src|track src|a href|iframe src|frame src|script src|link href|area href| background'

    for t in tags.split('|')
      [tag,attr] = t.split(' ')
      rt.rule({tag:tag,attr:attr,rewrite:reUrl})

    reCSS = (css)-> rewrite.css css,baseOrigin,config
    rt.rule({tag:'style',rewrite:reCSS})
    rt.rule({attr:'style',rewrite:reCSS})
    html = rt.result()
    return html


module.exports = rewrite
