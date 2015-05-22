# Miscellaneous Util

_OBJECT_ID_ = '_INTERNAL_OBJECT_ID_WeedProxite:misc_'

_AUTO_INCREMENT_ID = 1

misc =
  parseUrl: (url) -> # lite parse full url, return [scheme,host,path]
    [_,scheme,host,path] = /^(https?):\/\/([\w\d.:-]+)(.*)?$/i.exec(url) || []
    scheme ?= ''; host ?= ''; path ?= '';
    return [scheme,host,path]

  # if url contains domain
  isDomainUrl: (url) ->
    return /^https?:\/|^\/\//i.test url


  id: (object) ->
    if object !=null && (typeof object=='object' || typeof object=='function')
      if object.hasOwnProperty _OBJECT_ID_
        return object[_OBJECT_ID_]
      else
        id = misc.guid()
        if Object.defineProperty
          # configurable:false,enumerable:false,writable:false
          Object.defineProperty(object,_OBJECT_ID_,{value:id})
        else
          object[_OBJECT_ID_] = id
        return id
    else
      return typeof object + ':' + object

  # Return upper case guid of length 10
  guid: () ->
    _AUTO_INCREMENT_ID = (_AUTO_INCREMENT_ID + 1) | 0
    a = _AUTO_INCREMENT_ID.toString(36)
    date = (+new Date).toString(36).slice(2) + a
    rand = ((Math.random()*1e8)|0).toString(36)
    return (date+rand).slice(0,10).toUpperCase()

  capitalize: (s)->
    s.replace /\b[a-z]/g,(c)-> c.toUpperCase()


  ###
  Repeat s: String n: Int times
  ###
  repeats: (s, n) -> (new Array(n + 1) ).join s

  ###
  Pad right c: Char to s: String tail to make s.length == n
  ###
  padRight: (s, c, n) ->
    return s if s.length >= n
    s + misc.repeats(c, n - s.length)

  ###
  Pad left c: Char to make s.length == n
  ###
  padLeft: (s, c, n) ->
    return s if s.length >= n
    misc.repeats(c, n - s.length) + s


  ###
  Test p is prefixOf s
  @return {Boolean}
  ###
  prefixOf: (p, s) -> s.slice(0, p.length) == p
  ###
  Test t is suffixOf s
  ###
  suffixOf: (t, s) -> s.slice(-t.length) == t

  ###
  Escape regex
  ###
  rescape: (s) -> s.replace /[.*+?^${}()|[\]\\]/g, "\\$&"


  trim: (s) -> if s.trim then s.trim() else s.replace(/^\s+/,'').replace(/\s+$/,'')

  ###
  Convert string with wildcard to regex,only support "*"
  @return {String} regex source
  ###
  rewild: (ws,assertBegin="^",assertEnd="$") ->
    s = ws.replace /[^*]*\*/g,(s) -> misc.rescape(s.slice(0,-1)) + "([^\\s]*)"
    s = s.replace /[^*)]*$/,misc.rescape
    return assertBegin+s+assertEnd

  ###
  Convert string list to regex choice
  rechoice(["a","b"]) => "^(?:a|b)$"
  @return {String} regex source
  ###
  rechoice: (choices,assertBegin = '^',assertEnd = '$') ->
    assertBegin+'(:'+choices.map(misc.rescape).join('|')+')'+assertEnd


  ###
  Convert unicode char to unicode escape

  escapeUnicode: (s) ->
    s.replace /[\u0100-\uFFFF]/g,(c)->
      return '\\u'+ misc.pads(c.charCodeAt(0).toString(16),'0',4)
  ###


  ###
  Shadow clone object as prototype
  ###
  clone: (src) ->
    if Object.create
      return Object.create(src)
    else
      C = new Function
      C.prototype = src
      return new C





module.exports = misc
