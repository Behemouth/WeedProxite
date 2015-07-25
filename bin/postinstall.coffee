#!/usr/bin/env node

execSync = require("child_process").execSync
# root = __dirname + '/..'
# exec = (cmd) -> execSync(cmd,{cwd:root})
exec = execSync
exec('node ./node_modules/coffee-script/bin/coffee --compile .')
exec('node ./node_modules/browserify/bin/cmd.js -t coffeeify ./lib/Client.coffee -o ./lib/tpl/static/bundle.js')
exec('node ./node_modules/uglifyjs/bin/uglifyjs ./lib/tpl/static/bundle.js -o ./lib/tpl/static/bundle.min.js --compress --mangle')
