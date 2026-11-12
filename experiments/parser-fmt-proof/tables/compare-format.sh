#!/bin/sh
# Run from the repository root with the project GHC and Lean 4.7.0.
set -eu
tables=experiments/parser-fmt-proof/tables
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cabal build lib:golem-fmt lib:golem-eval -w ghc-9.10.3
cabal exec -w ghc-9.10.3 -- ghc -hide-all-packages -package base -package text \
  -package golem-parser-0.1.0 -package golem-eval-0.1.0 -package golem-syntax-0.1.0 -package golem-fmt-0.1.0 -outputdir "$work" "$tables/FormatCases.hs" -o "$work/format-cases"
"$work/format-cases" > "$work/haskell"
"${LEAN:-lean}" -o "$work/Table.olean" "$tables/Table.lean"
LEAN_PATH="$work" "${LEAN:-lean}" --run "$tables/FormatCases.lean" > "$work/lean"
if ! cmp -s "$work/haskell" "$work/lean"; then
  echo 'Table formatter mismatch (input => output, decimal Unicode scalars)' >&2
  diff -u "$work/haskell" "$work/lean" | head -n 12 >&2
  exit 1
fi
test "$(wc -l < "$work/haskell")" -eq 124999
echo '97656 formatter outputs and 3906 inputs per CSV/TSV parser matched; 19531 diagnostic lists matched'
