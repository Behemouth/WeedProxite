assert = require 'assert'
http = require 'http'
Site = require '../lib/Site'
request = require 'supertest'
os = require 'os'
fs = require 'fs'
rmdir = require 'rmdir'
enableDestroy = require '../lib/enableServerDestroy'
rewrite = require '../lib/rewrite'
should = require 'should'


tempDir = ()->
  tmp = os.tmpdir()
  tmp = tmp + '/WeedProxite-test-' + (Math.random()+'').slice(2)
  fs.mkdirSync tmp
  return tmp



TEST_UPSTREAM1_PORT = 17891
TEST_UPSTREAM2_PORT = 17892
TEST_PROXY_PORT = 17890

upstream1 = null ;
upstream1Host = null;
upstream2 = null ;
upstream2Host = null;
upstream2HostEscaped = null;
proxite = null;
proxiteHost = null;



siteRoot = null
setupProxite = ()->
  upstream1 = http.createServer()
  upstream1.listen TEST_UPSTREAM1_PORT
  upstream1Host = '127.0.0.1:'+TEST_UPSTREAM1_PORT

  upstream2 = http.createServer()
  upstream2.listen TEST_UPSTREAM2_PORT
  upstream2Host = '127.0.0.1:'+TEST_UPSTREAM2_PORT
  upstream2HostEscaped =  '127.0.0.1-colon-'+TEST_UPSTREAM2_PORT

  siteRoot = tempDir()
  Site.init siteRoot
  config = require siteRoot+'/config.js'
  config.upstream = 'http://' + upstream1Host
  config.allowHosts = [upstream2Host ]
  config.port = TEST_PROXY_PORT
  config.root = siteRoot
  proxite = new Site config
  proxite.useDefault()
  proxite.run()
  proxiteHost = '127.0.0.1:'+ TEST_PROXY_PORT

  enableDestroy(upstream1)
  enableDestroy(upstream2)
  enableDestroy(proxite._server)


cleanSite = (done)->
  upstream1.destroy()
  upstream2.destroy()
  proxite._server.destroy()
  proxite = null
  rmdir siteRoot,done



describe 'Site Base',()->
  originCSS = rewritedCSS = versionRegex = originPage = rewritedPage = null
  before ()->
    setupProxite()
    versionRegex = new RegExp('version\\:\\s+' + proxite.config.version + '\\s')
    originCSS = """
    @import "/style.css";
    @import url("http://example.com/style.css");
    """
    rewritedCSS = """
    @import "/http-colon-//#{upstream2HostEscaped}/style.css";
    @import url("http://example.com/style.css");
    """

    originPage = """
    <a href="/path/index.html">Link</a>
    <a href="/">Link</a>
    <a href="index.html">Link</a>
    <div style="background:url('/bg.png')">Bg</div>
    <style>body {background:url(/bg.png);}</style>
    <script>var html='<a href="/">Should not touch me</a>'</script>
    <iframe src="/path/page.html"></iframe>
    <iframe src="/path/page.html?a=45"></iframe>
    <iframe src="/path/page.html#a=45"></iframe>
    <iframe src="a.html"></iframe>
    """

    iframeQuery = proxite.config.outputCtrlParamName+'=iframe'
    rewritedPage = """
    <a href="/http-colon-//#{upstream2HostEscaped}/path/index.html">Link</a>
    <a href="/http-colon-//#{upstream2HostEscaped}/">Link</a>
    <a href="index.html">Link</a>
    <div style="background:url('/http-colon-//#{upstream2HostEscaped}/bg.png')">Bg</div>
    <style>body {background:url(/http-colon-//#{upstream2HostEscaped}/bg.png);}</style>
    <script>var html='<a href="/">Should not touch me</a>'</script>
    <iframe src="/http-colon-//#{upstream2HostEscaped}/path/page.html?#{iframeQuery}"></iframe>
    <iframe src="/http-colon-//#{upstream2HostEscaped}/path/page.html?a=45&#{iframeQuery}"></iframe>
    <iframe src="/http-colon-//#{upstream2HostEscaped}/path/page.html?#{iframeQuery}#a=45"></iframe>
    <iframe src="a.html?#{iframeQuery}"></iframe>
    """


    upstream1.on 'request',(req,res)->
                              res.setHeader('X-Referer',req.headers['referer']+'')
                              res.setHeader('X-Origin',req.headers['origin']+'')
                              res.end('Upstream1')
    upstream2.on 'request',(req,res)->
                              if req.headers.accept == 'text/html'
                                res.setHeader('Content-Type','text/html')
                                res.end('Upstream2')
                              else if req.headers.accept == 'text/css'
                                res.setHeader('Content-Type','text/css')
                                res.end(originCSS)
                              else
                                res.end('Upstream2')

    proxite.use {
      match:(req) -> return req.headers['x-test-rewrite-html']
      before:(req,res)->
        rt = rewrite.html originPage,req.localConfig
        res.end(rt.result())
    }

  after cleanSite

  it 'GET manifest',(done)->
    request(proxite._server)
    .get(proxite.config.api+'manifest.appcache')
    .expect(versionRegex)
    .end(done)

  it 'GET manifest refresh',(done)->
    request(proxite._server)
    .get(proxite.config.api+'manifest.appcache?version=xxxx')
    .expect(versionRegex)
    .end (err,res)->
      if (err) then done()
      else throw new Error("Manifest should return timestamp when version in query string not correct.")


  it 'GET static/bundle.js',(done)->
    request(proxite._server)
    .get(proxite.config.api+'static/bundle.js')
    .expect(fs.readFileSync(proxite.root+'/static/bundle.js','utf-8'))
    .end done


  it 'Should forbidden',(done)->
    request(proxite._server)
    .get('/http://unknown.com/')
    .expect(403)
    .end(done)

  it 'Should bad request',(done)->
    request(proxite._server)
    .get(proxite.config.api+'bad')
    .expect(400)
    .end(done)


  it 'Revert referer and origin',(done)->
    request(proxite._server)
    .get('/')
    .set('Referer','http://'+proxiteHost+'/http://'+upstream2Host+'/path/')
    .set('Origin','http://'+proxiteHost)
    .expect('X-Referer','http://'+upstream2Host+'/path/')
    .expect('X-Origin','http://'+upstream1Host)
    .expect(200)
    .end(done)


  it 'Upstream 1',(done)->
    request(proxite._server)
    .get('/')
    .set('Origin','http://example.com')
    .expect(200,'Upstream1')
    .expect('Access-Control-Allow-Origin','http://'+proxiteHost)
    .end(done)

  it 'Redirect redundant upstream 1',(done)->
    request(proxite._server)
    .get('/http://' + upstream1Host )
    .expect(301)
    .expect('location','/')
    .end(done)

  it 'Redirect',(done)->
    request(proxite._server)
    .get('/http://'+upstream2Host)
    .expect(301)
    .expect('location','/http://'+upstream2Host+'/')
    .end(done)

  it 'Redirect with query string',(done)->
    request(proxite._server)
    .get('/http://'+upstream2Host+'?a=1')
    .expect(301)
    .expect('location','/http://'+upstream2Host+'/?a=1')
    .end(done)

  it 'Upstream 2',(done)->
    request(proxite._server)
    .get('/http://'+upstream2Host+'/')
    .expect(200,'Upstream2')
    .end(done)


  it 'Upstream 2 rewrite html',(done)->
    request(proxite._server)
    .get('/http://'+upstream2Host+'/')
    .set('Accept','text/html')
    .expect(200,/"pageContent":"Upstream2"/)
    .end(done)

  it 'Rewrite html',(done)->
    request(proxite._server)
    .get('/http://'+upstream2Host+'/')
    .set('x-test-rewrite-html','true')
    .expect(200)
    .end (err,res)->
            return done(err) if err
            res.text.should.equal(rewritedPage)
            return done()

  it 'Rewrite css',(done)->
    request(proxite._server)
    .get('/http://'+upstream2Host+'/')
    .set('Accept','text/css')
    .expect('Content-Type','text/css')
    .expect(200)
    .end (err,res)->
            return done(err) if err
            res.text.should.equal rewritedCSS
            return done()



