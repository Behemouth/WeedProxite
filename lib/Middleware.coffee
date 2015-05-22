###
Middleware
###

misc = require './misc'

class Middleware
  # friends class Server

  ###
  All of host,path,mime,method exact or wildcard match are ignore case
  If you pass RegExp,you need to specify ignoreCase by yourself
  Wildcard doesn't match white spaces; i.e. "*" means "[^\s]*" in RegExp
  All properties are used to match proxyRequestOptions,not original request
  Initially proxyRequestOptions is equal to original request,
  but if certain middleware changed proxyRequestOptions.url,
  middlewares come after it will do match against new url
  ###

  ###
  Exact host or wildcard or RegExp
  "*.google.com" will match "www.google.com"
  but not match "google.com" or "www.google.com.sb"
  RegExp could be more powerful:
  new RegExp(misc.rechoice(['1.a.com','2.a.com']),'i')
  @type {String|RegExp}
  ###
  host: '*'

  ###
  Exact path or wildcard or RegExp
  "/a/" will match path start with it
  Path always need to start with '/'
  @type {String|RegExp}
  ###
  path: '*'

  ###
  Exact mime type like text/html or wildcard; e.g. "text/css" or "*\/javascript"
  If specified mime appeared in request.headers.accept,then execute before handler
  If appeared in proxyResponse.headers["content-type"],then execute after handler
  @type {String}
  ###
  mime: '*'

  # Exact method name like GET,POST or use '*' to catch all
  # @type {String}
  method: '*'

  ###
  If mount mode is true, request.url part match @route will be trimed off
  Just like what `connect` did,for compatible purpose
  ###
  _mount: false
  route: ''
  isErrorHandler: false

  ###
  Quick test if this middleware match all request
  ###
  _matchAll:false
  _toTestProps:null

  # verbose name
  name: ''

  ###
  @param {Object} options extend to Middleware instance property
  ###
  constructor: (options) ->
    if ((options.host || '*') == (options.path || '*') ==
        (options.method || '*') == (options.mime || '*')) &&
       !options.route && !options.match
      @_matchAll = true

    this[key]=value for own key,value of options

    if @route
      @path = @route
      @_mount = true

    return if @_matchAll

    toTestProps = []

    if @mime != '*'
      @_mimeRegex = if @mime instanceof RegExp
                      @mime
                    else
                      new RegExp((misc.rewild this.mime,"\\b","\\b"),"i")

    @path += '*' if typeof @path == 'string' && @path.slice(-1) != '*'

    ['host','path','method'].forEach (p)=>
        return if this[p] == '*'
        _p = '_'+p+'Regex'
        this[_p] =  if this[p] instanceof RegExp
                      this[p]
                    else
                      new RegExp((misc.rewild this[p]),'i')
        toTestProps.push [p,this[_p]]

    @_toTestProps = toTestProps



  ###
  Default handler run before send request to upstream,
  you can alter request options before send to upstream.
  @param {IncomingMessage} req Origin request from client
  @param {ServerResponse} res Origin response to client
  @param {Function(err)} next As async return/continuation,err param see finalhandler doc
  @param {Object} options proxy to upstream http/https.request() options
  All options:
  {
    protocol : "http", // or change to "https"
    method: "POST",
    // If you changed host,remember to change headers.host too
    host: "www.example.com:8080",
    path: "/path/to/file.html?query=yes",
    headers: {},
    // You can alter request body here, Server class will send it
    body: "user=guest&passwd=no"
  }
  ###
  before: (req,res,next,options) -> next()

  ###
  Default handler run after upstream response,
  you can alter upstream response before send to client user.
  This param order is designed to easy reuse `connect` middlewares like `body-parser`
  For example:
    server.use({after:bodyParser.text({type:"text/html"})}) // remember to specify `type` option
  @param {IncomingMessage} proxyResponse get from proxyRequest.on('response')
  @param {ServerResponse} res Origin response to client
  @param {Function(err)} next As async return/continuation,err param see finalhandler doc
  @param {ClientRequest} proxyRequest return value by http/https.request
  @param {IncomingMessage} req Origin request from client
  ###
  after: (proxyRes,res,next,proxyReq,req) -> next()


  ###
  Match request,same arugments as `before`
  @return {Boolean} return true to execute this middleware
                    if return false, both `before` and `after` will not run
  ###
  match: (req,res,options) -> return true

  _match: (req,res,options) ->
    return true if @_matchAll
    fail = false
    for [p,re] in @_toTestProps
      unless re.test options[p]
        fail = true
        break

    return !fail && @match.apply(this,arguments)

  _before:  (req,res,next,options) ->
    accept = req.headers.accept || ''
    return next() if @mime != '*' && !~accept.indexOf('*/*') && !@_mimeRegex.test(accept)

    if @_mount
      # mount route compatibility for connect framework
      # if mount point is "/static/",
      # for "/static/logo.png",middleware will get req.url = "/logo.png"
      subUrl = req.url.slice(@route.length)
      subUrl = '/' + subUrl if subUrl[0] != '/'
      originUrl = req.url
      originNext = next
      req.url = subUrl
      next = (err)-> req.url = originUrl; originNext(err)

    @before.apply(this,arguments)

  _after: (proxyRes,res,next,proxyReq,req) ->
    ct = proxyRes.headers["content-type"]
    return next() if @mime !='*' && !@_mimeRegex.test(ct)
    @after.apply(this,arguments)


module.exports = Middleware
