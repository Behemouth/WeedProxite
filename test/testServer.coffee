assert = require 'assert'
http = require 'http'
Server = require '../lib/Server'
retarget = require '../lib/middlewares/retarget'
enableDestroy = require '../lib/enableServerDestroy'
request = require 'supertest'
TEST_UPSTREAM_PORT = 7891
TEST_PROXY_PORT = 7890

upstream = null ; proxy = null ;
upstreamHost = null; proxyHost = null;

setupServer = () ->
  upstream = http.createServer()
  upstream.listen TEST_UPSTREAM_PORT
  upstreamHost = 'localhost:'+TEST_UPSTREAM_PORT
  proxy = new Server
  proxy.listen TEST_PROXY_PORT
  proxyHost = 'localhost:'+TEST_PROXY_PORT
  enableDestroy(upstream)
  enableDestroy(proxy._server)


closeServer = () ->
  upstream.destroy()
  upstream = null
  proxy._server.destroy()
  proxy = null



describe 'Retarget',()->
  before setupServer
  after closeServer
  it 'Upstream', (done)->
    msg = 'Upstream forward port:'
    proxy.use retarget(upstreamHost)
    upstream.on 'request',(req,res)-> res.end msg + req.headers['x-forwarded-port']
    request(proxy._server) # hehe
      .get('/').expect(200,msg+TEST_PROXY_PORT)
      .end(done)


describe 'Middleware',()->
  before ()->
    setupServer()
    proxy.use retarget(upstreamHost)
    handler = (req,res)->
        if req.url=='/match'
          res.end(req.headers['x-test'])
        else if req.headers.accept == 'text/wtf'
          res.setHeader('Content-Type','text/wtf')
          res.end(req.headers['x-before'])
        else
          res.end('NotMatch')

    upstream.on 'request',handler
    proxy.use {
      path: '/match'
      before:(req,res,next,opts) ->
        opts.headers['x-test'] = 'Match'
        next()
    }
    proxy.use {
      mime:'text/wtf'
      before: (req,res,next,opts) ->
        opts.headers['x-before'] = 'WTF'
        next()
      after: (proxyRes,res,next) ->
        cb = (err,body)->
                return next(err) if err
                proxyRes.body = body + '!!!'
                next()
        proxyRes.withTextBody cb
    }

    proxy.use {
      path: '/500'
      before: (req,res,next) ->
        e = new Error('Server Error')
        e.statusCode = 500
        next(e)
    }

  after closeServer

  it 'Pass path', (done)->
    request(proxy._server) # hehe
      .get('/').expect('NotMatch')
      .end done

  it 'Match path',(done)->
    request(proxy._server) # hehe
      .get('/match').expect('Match')
      .end done

  it 'Match mime',(done)->
    request(proxy._server) # hehe
      .get('/any').expect('WTF!!!')
      .set('Accept','text/wtf')
      .end done

  it 'Handle error',(done)->
    request(proxy._server) # hehe
      .get('/500').expect(500)
      .end done



