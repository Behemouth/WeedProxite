#!/usr/bin/env coffee
fs = require 'fs'
http = require 'http'
WeedProxite = require '../'
Server = WeedProxite.Server
Site = WeedProxite.Site
program = require 'commander'
# browserify = require 'browserify'
path = require 'path'
watch = require 'watch'
# coffeeify = require 'coffeeify'
exec = require("child_process").exec;
enableDestroy = require '../lib/enableServerDestroy'

LIB_ROOT = path.resolve __dirname+'/../'
CLIENT_SRC = LIB_ROOT + '/lib/Client.coffee'
BUNDLE_JS = LIB_ROOT + '/lib/tpl/static/bundle.js'
misc = WeedProxite.misc





rebuild = (cb)->
  process.chdir __dirname + '/../'
  require_compile = ()->
    exec(process.execPath + ' ./node_modules/light-require-compile/bin/light-require-compile.js ./lib/Client.js ./lib/tpl/static/bundle.js',done)

  # exec(process.execPath + ' ./node_modules/coffee-script/bin/coffee --compile --bare --no-header .', require_compile)

  done = (err)->
    if (err)
      console.error(err)
      process.exit(2)
    else
      process.chdir __dirname
      cb()

  require_compile()


exit =  (code) -> process.exit(code)


checkSiteRoot = (root) ->
  if !fs.statSync(root).isDirectory()
    console.error("Site root must be directory!")
    exit(1)

initSite = (root,opts,cb) ->
  root ?= process.cwd()
  checkSiteRoot root
  if !opts.debug
    Site.init root
    cb && cb()
  else
    onfinish = ()->
      Site.init root
      cb && cb()
    rebuild(onfinish)
    ###
    bundleJS = fs.createWriteStream(BUNDLE_JS)
    bundleJS.on 'finish',()->
      Site.init root
      console.log "Init successfully!Override:"+ (!!opts.override)
      cb && cb()

    browserify(CLIENT_SRC).transform(coffeeify).bundle().pipe(bundleJS)
    ###



runSite = (root,opts) -> # Used nodemon to auto reload server
  root ?= process.cwd()
  checkSiteRoot root

  startSite = ()->
    process.env.WEED_PROXITE_DEBUG = true
    Site.run root,opts.host,opts.port

  if opts.debug
    rebuild(startSite)
  else
    startSite()


  ###
  if false && opts.debug
    monitors = []
    onChange = (f) ->
      # return if /\.coffee$/i.test(f) # skip coffee file
      m.stop() for m in monitors
      console.log "Site reloading..."
      site._server.destroy()
      site[k]=null for k,v of site
      site = monitors = null
      runSite root,opts
    initSite root,{override:true,debug:true},()->
      bindMonitor = (monitor)->
        monitors.push monitor
        monitor.on 'changed',onChange

      watch.createMonitor root,bindMonitor
      watch.createMonitor LIB_ROOT+'/lib/tpl/',bindMonitor
      Site.run root,opts.host,opts.port
      # enableDestroy site._server
  else
    Site.run root,opts.host,opts.port
  ###






program.command('init [root]')
       .description('Init site, root param is the site root directory')
       # .option('--override','Override exist files except config.js main.js and main.html')
       .option('--debug','Generate fresh debug version bundle.js, you need to set debug=true in config.js by yourself')
       .action(initSite)


program.command('run [root]')
       .description('Run site')
       .option('--debug','Watch changes so server will automatically reload on debug')
       .option('--host [host]','Bind host, default is 127.0.0.1')
       .option('--port [port]','Bind port, default is 1984')
       .action(runSite)

program.command('help')
       .description('Show help')
       .action(() -> program.outputHelp())

program.parse(process.argv);

return
###

testServer = http.createServer (req, res) ->

  body = ""
  body += req.method + "\n"
  body += req.url + "\n"
  body += req.headers.host + "\n"
  body += JSON.stringify(req.headers, null, 4) + "\n"
  body += "\nTest"

  res.writeHead(200, {
    "Content-Type":"text/html"
   # "Content-Length":Buffer.byteLength body
  } )
  res.end(body)

testServer.listen 8998, "0.0.0.0"
###


# site.retarget "http://ourartnet.com/"

###
site.use(compression()).withTextBody({mime: 'text/html'}).use({
  mime: 'text/html',
  after: (proxyRes, res, next) ->
    console.log "Call me after?"
    # console.log proxyRes.body
    proxyRes.body = (proxyRes.body.split "http://ourartnet.com/").join "/"
    next()
})
###

