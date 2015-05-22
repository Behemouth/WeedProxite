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
  @param {Config} config

  ###
  url:(p,config,baseRoot) ->
    u = p
    baseRoot ||= config.location.baseRoot
    # "//example.com/" is valid but url.parse not handle correctly
    u = 'http:'+u if u.slice(0,2) == '//'
    if misc.isDomainUrl u
      [scheme,host,path] = parseUrl u
      if config.allowHost host
        return if config.isUpstreamHost host then path else '/' + u
    else if u[0] == '/'
      return baseRoot + u.slice(1)

    return p # otherwise remain unchange

  addCtrlParam: (path,config,ctrlType) ->
    ctrlType ||= config.location.ctrlType
    return path if !ctrlType
    [path,hash]=path.split('#')
    [path,qs]=path.split('?')
    qs = if qs then qs+'&' else ''
    qs += config.outputCtrlParamName + '=' + ctrlType
    return path + '?' + qs + (if hash then '#' + hash else '')

  css:(css,config,baseRoot) ->
    replace = (m,url) ->
                m.replace url,(rewrite.url url,config,baseRoot)
    css = css.replace /\burl\(['"]([^*'"]+)['"]\)/ig,replace
    css = css.replace /\burl\(([^*'"()\s]+)\)/ig,replace
    css = css.replace /@import\s+['"]([^*'"]+)['"]/ig,replace
    return css

  # @return {HTMLRewriter}
  html:(html,config) ->
    baseRoot = config.location.baseRoot
    # disableRewriteInternal = false # disable rewrite url in same domain
    rewriteBase = (href) -> # rewrite base tag first
                      rh = rewrite.url href,config
                      if misc.isDomainUrl rh # tertiary domain
                        # disableRewriteInternal = true
                        return href
                      else if misc.isDomainUrl href
                        href = 'http:' + href if href.slice(0,2)=='//'
                        [scheme,host,path] = parseUrl href
                        baseRoot = '/' + scheme + '://' + host + '/'

                      return rh

    rt = new HTMLRewriter(html)
    rt.rule({tag:'base',attr:'href',first:true,rewrite: rewriteBase})
    html = rt.result()

    ###
    TODO: Consider to use CloudFlare image proxy
    https://images.weserv.nl/?url=www.google.com/images/srpr/logo11w.png
    ###
    rt = new HTMLRewriter(html)
    reUrl = (src)-> rewrite.url src,config,baseRoot
      # return rewrite.url src,config,baseRoot if ! disableRewriteInternal
      # return if misc.isDomainUrl src then rewrite.url src,config,baseRoot else src

    tags = 'img src|object data|applet src|embed src|audio src|video src|source src|track src|a href|script src|link href|area href| background'

    for t in tags.split('|')
      [tag,attr] = t.split(' ')
      rt.rule({tag:tag,attr:attr,rewrite:reUrl})

    reframe = (url) ->
      url = reUrl url
      return url if misc.isDomainUrl url
      return rewrite.addCtrlParam url,config,'iframe'

    rt.rule({tag:'iframe',attr:'src',rewrite:reframe})
    rt.rule({tag:'frame',attr:'src',rewrite:reframe})

    reCSS = (css)-> rewrite.css css,config,baseRoot
    rt.rule({tag:'style',rewrite:reCSS})
    rt.rule({attr:'style',rewrite:reCSS})

    rewriteRefresh = (content,tag) ->
      return content unless /http-equiv=['"]?refresh['"]?/i.test tag
      return content.replace  /(;\s*url=)([^<>'"]+)/ig,
                              (_,a,url) -> return a + reUrl(url)
    rt.rule({tag:'meta',attr:'content',rewrite:rewriteRefresh})
    return rt


module.exports = rewrite
