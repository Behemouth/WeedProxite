###
Content rewrite
###
misc = require './misc'
HTMLRewriter = require './HTMLRewriter'

parseUrl = misc.parseUrl

###
Simple html encode only replace "<>"
###
encodeHTML = (html) ->
  return html.replace(/</g,'&lt;').replace(/>/g,'&gt;')


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
        # replace colon to avoid error in Azure websites
        return if config.isUpstreamHost host then path else '/' + u.replace(/:/g,'-colon-')
    else if u[0] == '/'
      return baseRoot.replace(/:/g,'-colon-') + u.slice(1)

    ensureProto = config.ensureExternalLinkProtocol
    if ensureProto != 'off' && /^https?:\/\//i.test(p)
      if ensureProto == 'auto'
        p = p.replace(/^http:\/\//i,'//')
      else if ensureProto == 'https'
        p = p.replace(/^http:\/\//i,'https://')

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
                        return encodeHTML(href)
                      else if misc.isDomainUrl href
                        href = 'http:' + href if href.slice(0,2)=='//'
                        [scheme,host,path] = parseUrl href
                        baseRoot = '/' + scheme + '://' + host + '/'

                      return encodeHTML(rh)

    rt = new HTMLRewriter(html)
    rt.rule({tag:'base',attr:'href',first:true,rewrite: rewriteBase})
    html = rt.result()

    ###
    TODO: Consider to use CloudFlare image proxy
    https://images.weserv.nl/?url=www.google.com/images/srpr/logo11w.png
    ###
    rt = new HTMLRewriter(html)
    reUrl = (src)-> encodeHTML(rewrite.url src,config,baseRoot)
      # return rewrite.url src,config,baseRoot if ! disableRewriteInternal
      # return if misc.isDomainUrl src then rewrite.url src,config,baseRoot else src

    tags = 'img src|object data|applet src|embed src|audio src|video src|source src|track src|a href|script src|link href|area href| background'

    for t in tags.split('|')
      [tag,attr] = t.split(' ')
      rt.rule({tag:tag,attr:attr,rewrite:reUrl})

    reframe = (url) ->
      url = reUrl url
      return encodeHTML(url) if misc.isDomainUrl url
      return encodeHTML(rewrite.addCtrlParam url,config,'iframe')

    rt.rule({tag:'iframe',attr:'src',rewrite:reframe})
    rt.rule({tag:'frame',attr:'src',rewrite:reframe})

    reCSS = (css)-> encodeHTML(rewrite.css css,config,baseRoot)
    rt.rule({tag:'style',rewrite:reCSS})
    rt.rule({attr:'style',rewrite:reCSS})

    rewriteRefresh = (content,tag) ->
      return content unless /http-equiv=['"]?refresh['"]?/i.test tag
      return content.replace  /(;\s*url=)([^<>'"]+)/ig,
                              (_,a,url) -> return a + reUrl(url)
    rt.rule({tag:'meta',attr:'content',rewrite:rewriteRefresh})
    return rt


module.exports = rewrite
