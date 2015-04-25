misc = require './misc'

class HTMLRewriter
  constructor: (html)->
    @html = html
    @_reRules = [] # rewrite attribute value based on regexp
    @_specialRules = [] # rewrite script or style inner content or script src
    @_replaceRules = []

  ###
  Similar to html.replace(),but exec after stashed style,script and comments
  so there is no more interference
  ###
  replace: (pattern,substitution) ->
    @_replaceRules.push [pattern,substitution]
    return this

  ###
  Rewrite tag or attributes
  @param {Object} options
  Options:{
    tag:'img', // html tag,must be lowercase,if don't specified,match all tags
    // attribute,
    //if don't specified, rewrite innerHTML, only make sense for script,style tag content
    attr:'src',
    // if only applys to first occurrence, default replace global
    first:Boolean,
    // Rewrite function
    rewrite:Function(
      value:String // value of attribute
    )
  }
  ###
  rule:(options)->
    tag = (options.tag || '[a-z][a-z0-9]+')
    g = if options.first then '' else 'g'
    special = tag == 'script' || tag =='style'
    if options.attr
      re = '(<'+tag+'\\s+[^<>]*\\b'+options.attr+'\\s*=\\s*[\'"]?)\\s*([^\'"<>]+)\\s*([\'"]?[^<>]*>)'
      re = new RegExp(re,'i'+g)
    if special
      @_specialRules.push({tail:'</'+tag+'>',re:re,rewrite:options.rewrite})
    else if options.attr
      @_reRules.push({re:re,rewrite:options.rewrite})
    else
      throw new Error('Rewrite element inner content only support script and style tag!')

    return this

  # Execute rewrite base on rules,return result
  result:() ->
    html = @html
    # stash comment,style and script
    stashed = {}
    genKey = () -> '###' + misc.guid() + '###'
    # Must combine all regex together at one time, otherwise it will match "<script><!--" incorrectly
    re = /(<!--[^]*?-->)|(<style\b[^<>]*>)([^]*?)(<\/style>)|(<script\b[^<>]*>)([^]*?)(<\/script>)/ig
    stash = (_,comment,styleHead,styleContent,styleTail,scriptHead,scriptContent,scriptTail) ->
      k = genKey()
      if comment
        stashed[k] = [comment]
        return k

      if styleHead
        [head,content,tail] = [styleHead,styleContent,styleTail]
      else
        [head,content,tail] = [scriptHead,scriptContent,scriptTail]

      tail = tail.toLowerCase()
      stashed[tail] ?= {}
      stashed[k] = stashed[tail][k] = [head,content,tail]
      return k

    html = html.replace re,stash

    reRuleRewrite = (whole,head,value,tail)-> head + (rule.rewrite value,whole) + tail

    for rule in @_reRules
      html = html.replace rule.re, reRuleRewrite

    for rule in @_specialRules
      tail = rule.tail
      for k,matched of stashed[tail]
        if rule.re # attr
          matched[0] = matched[0].replace rule.re,reRuleRewrite
        else # rewrite content
          matched[1] = rule.rewrite(matched[1])
        break if rule.first

    for rule in @_replaceRules
      html = html.replace.apply(html,rule)

    # recover stashed stuffs
    html = html.replace /###[A-Z0-9]{10}###/g,(k) -> stashed[k].join('')
    return html


module.exports = HTMLRewriter
