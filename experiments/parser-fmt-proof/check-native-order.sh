#!/bin/sh
# Build both versions of StringLit with peg-hs and parse an entire literal.
set -eu
root=$(pwd)
runtime=$(jq -er '[."install-plan"[] | select(."pkg-name" == "peg-runtime") | .id] | unique | if length == 1 then .[0] else error("expected one runtime") end' dist-newstyle/cache/plan.json)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for variant in actual reversed; do
  node - "$root/modules/golem-parser/grammar/Golem.hpeg" "$tmp/Literal.hpeg" "$variant" <<'JS'
const fs = require('node:fs');
let rule = fs.readFileSync(process.argv[2],'utf8').split('\n').find(s=>s.startsWith('StringLit <-'));
if (process.argv[4] === 'reversed') rule = rule.replace(/\((.+) \/ (.+)\)\*/, '($2 / $1)*');
fs.writeFileSync(process.argv[3], '%module Literal\nWhole :: ()\nWhole <- StringLit !. { () }\nStringLit :: ()\n' + rule + '\n');
JS
  peg-hs gen "$tmp/Literal.hpeg" -o "$tmp/Literal.hs"
  cat > "$tmp/Main.hs" <<'HS'
module Main where
import qualified Literal
import qualified Data.Text as T
main = print (Literal.parse (T.pack "\"a\\\"b\""))
HS
  cabal exec -- ghc -v0 -fforce-recomp -hide-all-packages -package base -package text -package-id "$runtime" -i"$tmp" -outputdir "$tmp" "$tmp/Main.hs" -o "$tmp/parse"
  actual=$("$tmp/parse")
  printf '%s: %s\n' "$variant" "$actual"
  case "$variant:$actual" in actual:Right*|reversed:Left*) ;; *) exit 1 ;; esac
done
