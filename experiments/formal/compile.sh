#!/bin/sh
set -eu
# Point BUILT_TREE at a checkout built with cabal and GHC 9.10.3.
db="${BUILT_TREE:-../codex-impl-0308}/dist-newstyle/packagedb/ghc-9.10.3"
store=${CABAL_DIR:-$HOME/.cabal}/store
storedb=$(ls -d "$store"/ghc-9.10.3*/package.db | head -1)
out=${TMPDIR:-/tmp}/golem-0310-0314
mkdir -p "$out"
plan="${BUILT_TREE:-../codex-impl-0308}/dist-newstyle/cache/plan.json"
for pkg in peg-grammar tasty tasty-hunit; do
  unit=$(jq -er --arg pkg "$pkg" '[."install-plan"[] | select(."pkg-name" == $pkg) | .id] | unique | if length == 1 then .[0] else error("expected one unit for "+$pkg) end' "$plan")
  set -- -package-id "$unit" "$@"
done
vector=$(rg -o "vctr-[^ ]+" "$db/golem-typeset-0.1.0-inplace.conf" | head -1)
set -- -package-id "$vector" "$@"
for pkg in parser fmt syntax length layout doc font test-support lsp typeset; do
  set -- -package-id "golem-$pkg-0.1.0-inplace" "$@"
done
ghc-9.10.3 -v0 -XGHC2021 -XLambdaCase -XOverloadedStrings -XDerivingStrategies \
  -package-db "$storedb" -package-db "$db" -imodules/golem-typeset/src \
  -outputdir "$out" -fforce-recomp "$@" -o "$out/probe"
"$out/probe"
