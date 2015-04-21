# Miscellaneous Util

_OBJECT_ID_ = '_INTERNAL_OBJECT_ID_WeedProxite:misc_'

misc =
  id: (object) ->
    if typeof object=='object' || typeof object=='function'
      if object.hasOwnProperty _OBJECT_ID_
        return object[_OBJECT_ID_]
      else
        return (object[_OBJECT_ID_] = misc.guid())
    else
      return typeof object + ':'+object
  guid: () ->
    ((+ new Date).toString(36).slice(2) +
     ((Math.random()*1e8)|0).toString(36) ).slice(0,10).toUpperCase()

  capitalize: (s)->
    s.replace /\b[a-z]/g,(c)-> c.toUpperCase()


  ###
  Repeat s: String n: Int times
  ###
  repeats: (s, n) -> (new Array(n + 1) ).join s

  ###
  Append c: Char to s: String tail to make s.length == n
  ###
  trails: (s, c, n) ->
    return s if s.length >= n
    s + repeats(c, n - s.length)

  ###
  Pad left c: Char to make s.length == n
  ###
  pads: (s, c, n) ->
    return s if s.length >= n
    repeats(c, n - s.length) + s


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


  trim: (s) -> s.replace(/^\s+/,'').replace(/\s+$/,'')

  ###
  Convert string with wildcard to regex,only support "*"
  @return {String} regex source
  ###
  rewild: (ws,assertBegin="^",assertEnd="$") ->
    s = ws.replace /[^*]*\*/g,(s) ->
            (misc.rescape s).slice(0,-2) + "([^\\s]*)"

    s = s.replace /[^*)]*$/,misc.rescape
    return assertBegin+s+assertEnd

  ###
  Convert string list to regex choice
  rechoice(["a","b"]) => "^(?:a|b)$"
  @return {String} regex source
  ###
  rechoice: (choices,assertBegin = '^',assertEnd = '$') ->
    assertBegin+"(:"+choices.map(misc.rescape).join('|')+")"+assertEnd


  ###
  Create object shadow copy
  @param {Object} obj original object
  @param {Object} ext properties extend to new object
  ###
  clone: (obj,ext) ->
    newObj = Object.create obj
    newObj[key] = value for own key,value of ext
    return newObj




module.exports = misc
