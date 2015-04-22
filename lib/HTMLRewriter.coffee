misc = require './misc'

class HTMLRewriter
  constructor: (html)->
    @_html = html
    @_reRules = [] # rewrite attribute value based on regexp
    @_specialRules = [] # rewrite inner content or script src

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


  # Execute rewrite base on rules,return result
  result:() ->
    html = @_html
    # stash comment,style and script
    stashed = {}
    genKey = () -> '###' + misc.guid() + '###'
    commentRe = /(<!--)([^]*?)(-->)/g
    styleRe = /(<style\b[^<>]*>)([^]*?)(<\/style>)/ig
    scriptRe = /(<script\b[^<>]*>)([^]*?)(<\/script>)/ig
    stash = (_,head,content,tail) ->
      k = genKey()
      tail = tail.toLowerCase()
      stashed[tail] ?= {}
      stashed[k] = stashed[tail][k] = [head,content,tail]
      return k

    for re in [commentRe,styleRe,scriptRe]
      html = html.replace re,stash

    reRuleRewrite = (_,head,value,tail)-> head + (rule.rewrite value) + tail

    for rule in @_reRules
      html = html.replace rule.re, reRuleRewrite

    for rule in @_specialRules
      tail = rule.tail
      for k,groups of stashed[tail]
        if rule.re # attr
          groups[0] = groups[0].replace rule.re,reRuleRewrite
        else # rewrite content
          groups[1] = rule.rewrite(groups[1])
        break if rule.first


    # recover stashed stuffs
    html = html.replace /###[A-Z0-9]{10}###/g,(k) -> stashed[k].join('')
    return html


module.exports = HTMLRewriter
