# This module only run in browser
Config = require './Config'
misc = require './misc'
rewrite = require './rewrite'
HTMLRewriter = require './HTMLRewriter'

noop = new Function

TIP_ID = 'WeedProxiteTip_JUST_MAGIC_BIT'
byId = (id) -> document.getElementById id

warningElm= byId(TIP_ID+'_warning')
warn = (msg)->
  warningElm.innerHTML += '<br />'+msg.replace(/\n/g,'<br />')

LS = window.localStorage;
LS = {getItem:noop,setItem:noop,removeItem:noop,clear:noop} if !LS;

if !window.console
  window.console = {log:noop}

isInCrossDomainFrame = ()->
  try
    return isInFrame() && top.location.host != self.location.host
  catch
    return true

isInFrame = ()->
  return top != self

isFirstVisit = ()->
  return LS.getItem("visited:"+location.href)!='true'

markVisisted = ()->
  return LS.setItem("visited:"+location.href,'true')

class Client
  constructor: () ->
    return top.location = self.location if isInCrossDomainFrame()
    @config = new Config(_config)
    @tip = byId(TIP_ID)
    if @tip
      @tipHTML = @tip.outerHTML.replace(/^\s*<div\b/i,'<div class="top"')

    html = @config.pageContent
    @rewriter = rewrite.html(html,@config)
    if @config.showMirrorNotice && @tipHTML
      @rewriter.replace /(<body\b[^>]*>)/ig,"$1"+@tipHTML

    mirrorLinks = @config.mirrorLinks
    href = location.href
    @currentMirror = ''
    @altMirrorLinks = []
    for link in mirrorLinks
      if misc.prefixOf link,href
        @currentMirror = link
      else
        @altMirrorLinks.push link



  run:() ->
    appCache = window.applicationCache
    return @showPage() if isFirstVisit() || !appCache || appCache.status==0 || navigator.onLine==false
    @_fetchPage()


  showPage: ()->
    markVisisted()
    html = @rewriter.result()
    writeDocument = ()->
                      document.open()
                      document.write(html)
                      document.close()

    if document.readyState !='complete'
      window.onload = ()-> setTimeout writeDocument,100
    else
      setTimeout writeDocument,100

  _fetchPage:()->
    url = _config.api + 'raw/' + _config.proxyTarget.url;
    fail = ()=>
              warn 'Current mirror is not available!\nTrying other mirrors...Please wait...'
              testOtherMirrors(@altMirrorLinks)

    return fail()  if isBlocked(@currentMirror)
    request {
      url:url
      mime:'text/html; charset=' + (_config.charset || _config.upstreamDefaultCharset)
      done:(xhr)=>
        @rewriter.html = xhr.responseText
        @showPage()
      fail:fail
    }

chooseMirror = (url)->
  chooseMirror = noop
  location.replace(url + _config.proxyTarget.url)

testOtherMirrors= (altMirrorLinks)->
    return noAvailableMirror() if !altMirrorLinks.length
    count= altMirrorLinks.length;
    pingQueue = altMirrorLinks.map (url)->
      succ = ()->
        pingQueue.forEach (xhr)-> xhr && xhr.abort() # only choose the fastest mirror
        chooseMirror(url)
      fail = ()->
        count--
        noAvailableMirror() if !count

      checkMirror(url,succ,fail)


checkMirror = (mirror,succ,fail)->
  return fail() if isBlocked(mirror)
  return request {
    url:mirror+_config.manifest.slice(1)+"?nocache"+(+new Date),
    done:succ
    fail:()->
      LS.setItem(mirror,'blocked');
      fail();
  }

# only check local storage
isBlocked = (mirror) ->
  return LS.getItem(mirror) == 'blocked'



noAvailableMirror = ()->
  console.log('%cEmergency!','color:red')
  warn("No available mirror!")
  warn("Trying mirror collection page...Please wait...")
  urls = _config.mirrorCollectionLinks
  urlCount = urls.length
  imgs = [];
  onLoad = ()->
    location.href = this.pageUrl

  onError = ()->
    urlCount--
    if urlCount<=0
      warn("No available mirror collection page!")


  for url in urls
    src = url.replace(/^(https?:\/\/[^\/]+\/).*/,'$1')+'favicon.ico'
    img = new Image
    img.onload = onLoad
    img.onerror = onError
    img.pageUrl = url
    img.src = src
    imgs.push img # lest browser gc it and cancel request



###
options {
  url:String,
  timeout:Int, // timeout in miliseconds
  onTimeout:Function,
  done:Function(xhr),
  fail:Function(xhr)
}
###
request = (opts)->
  xhr = new XMLHttpRequest
  xhr.open('GET',opts.url,true)
  xhr.setRequestHeader('X-Requested-With','XHR')
  if opts.mime
    xhr.overrideMimeType(opts.mime)
  xhr.timeout = opts.timeout || _config.timeout || 30000
  clean = ()->
    xhr.onreadystatechange = noop
    xhr.ontimeout = noop
    clearTimeout(tid)

  onTimeout = ()->
    console.log("Timeout:"+url)
    clean()
    opts.fail(xhr)

  xhr.onreadystatechange = ()->
    if xhr.readyState==4
      clean()
      if xhr.status>=200 && xhr.status <500
        opts.done(xhr)
      else
        opts.fail(xhr)

  xhr.ontimeout = onTimeout
  tid = setTimeout(onTimeout,xhr.timeout)
  xhr.send(null)
  return xhr


window.WeedProxite = {
  Client:Client,
  rewrite:rewrite,
  misc:misc,
  HTMLRewriter:HTMLRewriter,
  Config:Config
}
