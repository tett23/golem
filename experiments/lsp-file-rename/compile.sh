#!/bin/sh
set -eu
db="${BUILT_TREE:?Cabal build tree}/dist-newstyle/packagedb/ghc-9.10.3"
store=${CABAL_DIR:-$HOME/.cabal}/store
storedb=$(ls -d "$store"/ghc-9.10.3*/package.db | head -1)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghc-9.10.3 -v0 -XGHC2021 -XOverloadedStrings -package-db "$storedb" -package-db "$db" \
  -package-id golem-parser-0.1.0-inplace -package-id golem-project-0.1.0-inplace \
  -package-id golem-syntax-0.1.0-inplace -outputdir "$out" Probe.hs -o "$out/probe"
"$out/probe"
