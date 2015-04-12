Config = require './Config'
misc = require './misc'
trans = require './trans'


class Client
  constructor: () ->
    return

main = () ->
  alert('Run Client!')



module.exports = Client

if process.browser
  main()
