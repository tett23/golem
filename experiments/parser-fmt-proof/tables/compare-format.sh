#!/bin/sh
# Run from the repository root with the project GHC and Lean 4.7.0.
set -eu
tables=experiments/parser-fmt-proof/tables
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cabal build lib:golem-fmt -w ghc-9.10.3
cabal exec -w ghc-9.10.3 -- ghc -hide-all-packages -package base -package text \
  -package golem-fmt-0.1.0 -outputdir "$work" "$tables/FormatCases.hs" -o "$work/format-cases"
"$work/format-cases" > "$work/haskell"
lean -o "$work/Table.olean" "$tables/Table.lean"
LEAN_PATH="$work" lean --run "$tables/FormatCases.lean" > "$work/lean"
cmp "$work/haskell" "$work/lean"
test "$(wc -l < "$work/haskell")" -eq 97656
echo '97656 table formatter outputs matched'
