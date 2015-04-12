#!/usr/bin/env node

fs = require 'fs'
http = require 'http'
WeedProxite = require '../'
Server = WeedProxite.Server
Site = WeedProxite.Site
bodyParser = require 'body-parser'
compression = require 'compression'
getRawBody = require 'raw-body'

exit =  (code) -> process.exit(code)

checkSiteRoot = (root) ->
  if !fs.statSync(root).isDirectory()
    console.error("Site root must be directory!")
    exit(1)

helpDoc = """
WeedProxite: Run Proxy Mirror Site
Usage: npm action ...args
Actions:
  init root
    - Init site, root param is the site root directory.
  run root
    - Run site.
"""

commands = {
  help: () ->
    console.log helpDoc
    exit()
  init: (root) ->
    checkSiteRoot root
    Site.init root
    console.log "Init successfully!"
  run: (root) ->
    checkSiteRoot root
    Site.run root
}

# alwasy run as `node cmd.js $action`
action = process.argv[2]
args = process.argv.slice(3)

return commands.help() if !action
return commands[action].apply(null,args) if commands.hasOwnProperty action
console.error "Invalid action! Please run `proxite help` to get help."


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

