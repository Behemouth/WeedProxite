#!/bin/bash
# Util develop script
ROOT=`dirname $(realpath "$0")`;

# This trivial job need to be done by yourself!
export PATH="$(npm bin):$PATH";
export NODE_PATH="$ROOT/lib/:$ROOT/node_modules/:$NODE_PATH";


case "$1" in
  'watch')
    coffee --watch --compile --bare "$ROOT";
    ;;
  'build')
    coffee --compile --bare "$ROOT";
    requirejs -f "$ROOT/lib/Client.js" -o "$ROOT/lib/tpl/static/bundle.js";
    uglifyjs  ./lib/tpl/static/bundle.js -o ./lib/tpl/static/bundle.min.js --compress --mangle;
    ;;
  'test')
    shift;
    ./node_modules/.bin/mocha "$@"  --timeout 0  --reporter list
    ;;
  'repl')
    node;
    ;;
  *)
    echo "Invalid action '$1'" >&2;
    echo "Usage:";
    echo './make.sh [watch|build|test|repl]';
    exit 1;
    ;;
esac;
