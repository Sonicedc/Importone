#!/bin/sh
set -eu
cd "$(dirname "$0")"
export THEOS="${THEOS:-$HOME/theos}"
export CLANG_MODULE_CACHE_PATH="$PWD/.theos/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
make package FINALPACKAGE=1 "$@"
