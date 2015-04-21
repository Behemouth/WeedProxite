###
Content rewrite
###
URL = require 'url'
misc = require './misc'

rewrite =
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
      u = URL.parse p
      if config.allowHost u.host
        if config.isUpstreamHost u.host
          return baseRoot + u.path.slice(1)
        else
          return baseRoot + p
    else if p[0]=='/'
      return baseRoot + p.slice(1)

    return path # otherwise remain unchange


  ###
  Revert target url from path
  @return {
    // either '/path/'(default upstream) or 'http://subdomain.upstream.com/path/'
    target:String,
    baseRoot:String, // see `trans.url`
    defaultUpstream:Boolean, // if target is default upstream
    action:Enum(raw|css|iframe|static|status|manifest.appcache)
  }
  ###
  revertUrl:(p,config) ->
    baseRoot = '/'; action = ''; target = p
    defaultUpstream = false
    if config.isProxyAPI p
      parts = (p.slice config.api.length).split('/')
      action = parts[0].split('?')[0]
      target = '/' + parts.slice(1).join '/'

    if /^\/https?:/i.test target
      baseRoot = /^(\/https?:\/\/[^\/]+\/)/i.exec(target)[1]
      target = target.slice 1
    else
      defaultUpstream = true
      target = config.upstream + target

    return {target:target,baseRoot:baseRoot,action:action,defaultUpstream:defaultUpstream}

  css:(css,baseRoot,config) ->
    replace = (m,url) -> m.replace url,(rewrite.url url,baseRoot,config)
    css = css.replace /\burl\(['"]([^*'"]+)['"]\)/ig,replace
    css = css.replace /\burl\(([^*'"()\s]+)\)/ig,replace
    css = css.replace /@import\s+['"]([^*'"]+)['"]/ig,replace
    return css
  html:(html,baseRoot,config) ->
    # stash comment,style and script
    stashed = {}
    genKey = () -> '###' + misc.guid() + '###'
    html = html.replace /<!--[^]*?-->|<style\b[^>]*>[^]*?<\/style>|<script\b[^>]*>[^]*?<\/script>/ig,
                        (m) -> k = genKey(); stashed[k] = m; return k;

    html = html.replace /<base\s+[^>]*?\bhref=['"]([^<>'"]+)['"]/i,
                        (_,href) -> rewrite.url href,baseRoot,config

    ###
    TODO: Use CloudFlare image proxy
    https://images.weserv.nl/?url=www.google.com/images/srpr/logo11w.png
    ###
    rewriteRaw = (url) ->
      _baseRoot = config.api + 'raw' +  baseRoot
      rewrite.url url,_baseRoot,config
    rewriteFrame = (src) ->
      _baseRoot = baseRoot
      unless config.isProxyAPI baseRoot
        _baseRoot = config.api + 'iframe' +  baseRoot
      rewrite.url href,_baseRoot,config

    tagRewriter = {iframe: rewriteFrame,frame: rewriteFrame}
    rawTag = 'img|object|applet|embed|audio|video|source|track'.split '|'
    tagRewriter[tag] = rewriteRaw for tag in rawTag

    tags = 'img src|object data|applet src|embed src|audio src|video src|source src|track src|a href|iframe src|frame src|script src|link href|area href'

    tagRegexMap = {}
    tagsRegex = []
    tags.split('|').forEach (t)->
                      [tag,attr] = t.split ' '
                      re = '(<'+tag+'\\b[^>]*\\b'+attr+'=[\'"]?)([^\'"<>]+)([\'"]?[^>]*>)'
                      tagsRegex.push(re.replace(/[()]/g,''))
                      tagRegexMap[tag]=new RegExp('^'+re+'$','i')
    tagsRegex = new RegExp(tagsRegex.join('|'),'ig')

    html = html.replace tagsRegex, (m)->
              tag = /^<([a-z0-9]+)/i.exec(m)[1].toLowerCase()
              re = tagRegexMap[tag]
              [_,head,url,tail] = re.exec(m)
              url = if tagRewriter.hasOwnProperty(tag)
                      tagRewriter[tag](url)
                    else
                      rewrite.url(url,baseRoot,config)
              return head + url + tail

    # recover stashed stuffs
    html = html.replace /###[A-Z0-9]{10}###/g,(k) -> stashed[k]
    return html


module.exports = rewrite
