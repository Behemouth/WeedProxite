fs = require 'fs'
http = require 'http'
WeedProxite = require '../'
Server = WeedProxite.Server
Site = WeedProxite.Site
bodyParser = require 'body-parser'
compression = require 'compression'
getRawBody = require 'raw-body'
program = require 'commander'
browserify = require 'browserify'
path = require 'path'
watch = require 'watch'
LIB_ROOT = path.resolve __dirname+'/../'
CLIENT_JS = LIB_ROOT + '/lib/Client.js'
BUNDLE_JS = LIB_ROOT + '/lib/tpl/static/bundle.js'
misc = WeedProxite.misc

exit =  (code) -> process.exit(code)



enableDestroy = (server) ->
  #  WTF Server#close()! Node.js sucks! There is no way to force shutdown server!
  connections = {}

  server.on 'connection', (conn) ->
    key = conn.remoteAddress + ':' + conn.remotePort
    connections[key] = conn
    conn.on 'close', () ->
      delete connections[key]

  server.destroy = (cb) ->
    server.close(cb)
    for key of connections
      connections[key].destroy()



checkSiteRoot = (root) ->
  if !fs.statSync(root).isDirectory()
    console.error("Site root must be directory!")
    exit(1)

initSite = (root,opts,cb) ->
  checkSiteRoot root
  bundleJS = fs.createWriteStream(BUNDLE_JS)
  bundleJS.on 'finish',()->
    Site.init root,opts.override
    console.log "Init successfully!Override:"+opts.override
    cb && cb()

  browserify(CLIENT_JS).bundle().pipe(bundleJS)



runSite = (root,opts) -> # Used nodemon to auto reload server
  checkSiteRoot root
  site = null
  if opts.debug
    monitors = []
    onChange = (f) ->
      return if /\.coffee$/i.test(f) # skip coffee file
      m.stop() for m in monitors
      console.log "Site reloading..."
      site._server.destroy() #FKFKFKFKFKFK!!!
      site[k]=null for k,v of site
      site = monitors = null
      runSite root,opts
    initSite root,{override:true},()->
      bindMonitor = (monitor)->
        monitors.push monitor
        monitor.on 'changed',onChange

      watch.createMonitor root,bindMonitor
      watch.createMonitor LIB_ROOT+'/lib/tpl/',bindMonitor
      site = Site.run root,opts.host,opts.port
      enableDestroy site._server
  else
    site = Site.run root,opts.host,opts.port








program.command('init <root>')
       .description('Init site, root param is the site root directory')
       .option('--override','If override exist files except config.js')
       .action(initSite)


program.command('run <root>')
       .description('Run site')
       .option('--debug','In debug mode, copied files in root directory will update automatically')
       .option('--host [host]','Bind host, default is 127.0.0.1')
       .option('--port [port]','Bind port, default is 1984')
       .action(runSite)

program.command('help')
       .description('Display help')
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

