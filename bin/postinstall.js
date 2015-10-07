#!/usr/bin/env node

exec = require("child_process").exec;
//nodejs = '"' + process.execPath + '"  '; //not work on Windows, who know why?
nodejs = 'node ';
exec( nodejs + ' ./node_modules/coffee-script/bin/coffee --compile --bare --no-header .', require_compile);

function require_compile(err) {
  if (err) {
    console.log(err)
    process.exit(2);
  } else {
    exec(nodejs + ' ./node_modules/light-require-compile/bin/light-require-compile.js ./lib/Client.js ./lib/tpl/static/bundle.js',uglifyjs);
  }
}

function uglifyjs(err) {
  if (err) {
    console.log(err);
    process.exit(3);
  } else {
    exec(nodejs + ' ./node_modules/uglifyjs/bin/uglifyjs ./lib/tpl/static/bundle.js -o ./lib/tpl/static/bundle.min.js --compress --mangle');
  }
}
