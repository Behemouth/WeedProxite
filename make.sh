#!/bin/bash
# Util develop script
ROOT=`dirname $(realpath "$0")`;

# This trivial job need to be done by yourself!
export PATH="$(npm bin):$PATH";
export NODE_PATH="$ROOT/lib/:$ROOT/node_modules/:$NODE_PATH";


case "$1" in
  'watch')
    coffee --watch --compile "$ROOT";
    ;;
  'build')
    coffee --compile "$ROOT";
    browserify -t coffeeify "$ROOT/lib/Client.coffee" -o "$ROOT/lib/tpl/static/bundle.js";
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
    exit 1;
    ;;
esac;
