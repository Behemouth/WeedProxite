###
Content rewrite
###
misc = require './misc'
HTMLRewriter = require './HTMLRewriter'

parseUrl = misc.parseUrl


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
      {scheme,host,path} = parseUrl u
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
    origin = ''; action = null; url = p
    isDefault = false; allowed = false
    if config.isProxyAPI p
      parts = (p.slice config.api.length).split('/')
      action = parts[0].split('?')[0]
      url = '/' + parts.slice(1).join '/'

    if /^\/https?:/i.test url
      {scheme,host,path} = parseUrl url.slice(1)
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

  # @return {HTMLRewriter}
  html:(html,origin,config) ->
    baseOrigin = origin
    rewriteBase = (href) -> # rewrite base tag first
                      u = rewrite.url href,origin,config
                      # should not proxy if it has <base href="http://another-domain.com/"/>
                      if /^https?:\/\//i.test u
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
    rt.baseOrigin = baseOrigin
    reUrl = (src)->
      rewrite.url src,baseOrigin,config
    tags = 'img src|object data|applet src|iframe src|frame src|embed src|audio src|video src|source src|track src|a href|script src|link href|area href| background'

    for t in tags.split('|')
      [tag,attr] = t.split(' ')
      rt.rule({tag:tag,attr:attr,rewrite:reUrl})

    ###
    TODO: Pass current path to rewrite.url
    iframeBase = config.api.slice(1)+'iframe/'+baseOrigin
    reframe = (url) -> rewrite.url url,iframeBase,config
    rt.rule({tag:'iframe',attr:'src',rewrite:reframe})
    rt.rule({tag:'frame',attr:'src',rewrite:reframe})
    ###

    reCSS = (css)-> rewrite.css css,baseOrigin,config
    rewriteRefresh = (content,tag) ->
      return content unless /http-equiv=['"]?refresh['"]?/i.test tag
      return content.replace  /(;\s*url=)([^<>'"]+)/ig,
                              (_,a,url) -> return a + rewrite.url(url,baseOrigin,config)
    rt.rule({tag:'style',rewrite:reCSS})
    rt.rule({attr:'style',rewrite:reCSS})
    rt.rule({tag:'meta',attr:'content',rewrite:rewriteRefresh})
    return rt


module.exports = rewrite
