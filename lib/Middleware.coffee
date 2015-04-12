###
Middleware
###

misc = require './misc'

class Middleware
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
  mount: false

  route: ''

  ###
  @param {Object} options extend to Middleware instance property
  ###
  constructor: (options) ->
    (this[key]=value if key[0]!= '_') for own key,value of options

    if @mime != '*'
      @_mimeRegex = if @mime instanceof RegExp
                      @mime
                    else
                      new RegExp((misc.rewild this.mime,"\\b","\\b"),"i")

    if @route
      @path = @route
      @mount = true

    @path += "*" if typeof @path == 'string' && @path.slice(-1) != '*'

    ['host','path','method'].forEach (p)=>
      if this[p] != '*'
        _p = "_"+p+"Regex"
        if this[p] instanceof RegExp
          this[_p] = this[p]
        else
          this[_p] = new RegExp((misc.rewild this[p]),'i')



  ###
  Before send request to upstream default handler,you can alter request options before send to upstream.
  @param {IncomingMessage} req Origin request from client, extended with BodyAccesor
  @param {ServerResponse} res Origin response to client
  @param {Function(err)} next As async return/continuation,err param see finalhandler doc
  @param {Object} options proxy to upstream http.request() options, extended with `body` property
  All options:
  {
    protocol : "http", // or change to "https"
    method: "POST",
    // If you changed host,remember to change headers.host too
    host: "www.example.com:8080",
    path: "/path/to/file.html?query=yes",
    headers: {},
    // You can alter request body
    body: "user=guest&passwd=no"
  }
  ###
  before: (req,res,next,options) -> next()

  ###
  After upstream response default handler,you can alter upstream response before send to client user.
  This param order is designed to easy reuse `conntect` middlewares like `body-parser`
  For example:
    server.use({after:bodyParser.text({type:"text/html"})}) // remember to specify `type`
  @param {IncomingMessage} proxyRes get from proxyRequest.on('response'), extended with BodyAccesor
  @param {ServerResponse} res Origin response to client
  @param {Function(err)} next As async return/continuation,err param see finalhandler doc
  @param {ClientRequest} proxyReq return value by http.request
  @param {IncomingMessage} req Origin request from client, extended with BodyAccesor
  ###
  after: (proxyRes,res,next,proxyReq,req) -> next()


  ###
  Match request,same arugments as `before`
  @return {Boolean} return true to execute this middleware
                    if return false, both `before` and `after` will not run
  ###
  match: (req,res,options) -> return true

  _match: (req,res,options) ->
    fail = false
    for p in ["host","path","method"]
      unless this[p] == '*' || this["_"+p+"Regex"].test(options[p])
        fail = true
        break

    accept = options.headers.accept + ''
    fail = true if @mime != '*' && !~accept.indexOf('*/*') && !@_mimeRegex.test(accept)

    return false if fail
    return @match.apply(this,arguments)

  _isErrorHandler: false

  _before:  (req,res,next,options) ->
    @before.apply(this,arguments)


  _after: (proxyRes,res,next,proxyReq,req) ->
    return next() if @mime !='*' && !@_mimeRegex.test(proxyRes.headers["content-type"])
    @after.apply(this,arguments)


module.exports = Middleware
