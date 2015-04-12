#!/bin/bash
# Util develop script
ROOT=`dirname $(realpath "$0")`;

# I can't believe that NPM is so hard to use.
# This trivial job need to be done by yourself!
export PATH="$(npm bin):$PATH";
export NODE_PATH="$ROOT/lib/:$ROOT/node_modules/:$NODE_PATH";


case "$1" in
  'watch')
    coffee --watch --map --compile "$ROOT";
    ;;
  'build')
    browserify --debug "$ROOT/lib/Client.js" -o "$ROOT/lib/tpl/static/bundle.js";
    ;;
  'test')
    npm test;
    ;;
  'repl')
    node;
    ;;
  *)
    echo "Invalid action '$1'" >&2;
    exit 1;
    ;;
esac;
