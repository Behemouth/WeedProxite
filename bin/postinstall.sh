node ./node_modules/coffee-script/bin/coffee --compile .
node ./node_modules/browserify/bin/cmd.js -t coffeeify ./lib/Client.coffee -o ./lib/tpl/static/bundle.js
node ./node_modules/uglifyjs/bin/uglifyjs ./lib/tpl/static/bundle.js -o ./lib/tpl/static/bundle.min.js --compress --mangle
