#!/bin/sh
set -eu
root=$(pwd)
dir=$root/experiments/parser-fmt-proof
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
node "$dir/read-grammar.mjs" "$root/modules/golem-parser/grammar/Golem.hpeg" "$tmp/Generated.lean"
cp "$dir/Proof.lean" "$dir/StringProof.lean" "$tmp/"
cd "$tmp"
export LEAN_PATH=.
lean --version
lean -o Generated.olean Generated.lean
lean -o Proof.olean Proof.lean
lean StringProof.lean
node - "$root/modules/golem-parser/grammar/Golem.hpeg" "$tmp/reversed.hpeg" <<'JS'
const fs = require('node:fs');
const original = fs.readFileSync(process.argv[2], 'utf8');
const reversed = original.replace(/^(StringLit <- .*)\((.+) \/ (.+)\)\*/m, '$1($3 / $2)*');
if (original === reversed) throw new Error('No ordered choice changed');
fs.writeFileSync(process.argv[3], reversed);
JS
node "$dir/read-grammar.mjs" "$tmp/reversed.hpeg" Generated.lean
lean -o Generated.olean Generated.lean
lean -o Proof.olean Proof.lean
if lean StringProof.lean > mutation.log 2>&1; then
  echo 'Reversing the choice should break the round-trip theorem' >&2
  exit 1
fi
grep -F '⊢ False' mutation.log
