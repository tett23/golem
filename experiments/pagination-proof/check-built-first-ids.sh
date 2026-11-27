#!/bin/sh
# Observe the private Built table without changing production exports.
# An optional first argument chooses another private-source observer.
# RUNGHC must supply the project's compiler and dependency package environment.
set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/Golem/Typeset"
awk '
  /^module Golem.Typeset.Flow$/ { header = 1; print "module Golem.Typeset.Flow where"; next }
  header && /^where$/ { header = 0; found++; next }
  !header { print }
  END { if (header || found != 1) exit 1 }
' "$root/modules/golem-typeset/src/Golem/Typeset/Flow.hs" >"$tmp/Golem/Typeset/Flow.hs"
# Compare everything after the original export list with the adapted module.
awk 'body { print } /^where$/ { body = 1 }' "$root/modules/golem-typeset/src/Golem/Typeset/Flow.hs" >"$tmp/original-body"
awk 'body { print } /^module Golem.Typeset.Flow where$/ { body = 1 }' "$tmp/Golem/Typeset/Flow.hs" >"$tmp/adapted-body"
cmp "$tmp/original-body" "$tmp/adapted-body"
cd "$root"
"${RUNGHC:-runghc}" --ghc-arg="-i$tmp" --ghc-arg="-i$root/modules/golem-typeset/src" "${1:-$root/experiments/pagination-proof/BuiltFirstIds.hs}"
