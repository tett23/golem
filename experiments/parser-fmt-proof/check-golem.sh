#!/bin/sh
# Exercise the syntax and formatter through the released CLI.
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for ordering in 'lines=1...3 lang=haskell' 'lang=haskell lines=1...3'; do
  printf '@listing "a\\"b" %s\n' "$ordering" > "$tmp/source.gm"
  golem inspect "$tmp/source.gm" --as ast > "$tmp/before"
  golem fmt "$tmp/source.gm"
  golem inspect "$tmp/source.gm" --as ast > "$tmp/after"
  cmp "$tmp/before" "$tmp/after"
  cp "$tmp/source.gm" "$tmp/once"
  golem fmt "$tmp/source.gm"
  cmp "$tmp/once" "$tmp/source.gm"
  cat "$tmp/source.gm"
  cat "$tmp/after"
done
