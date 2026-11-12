#!/bin/sh
set -eu
suite=experiments/parser-fmt-proof/eval
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cabal build lib:golem-emet -w ghc-9.10.3
cabal exec -w ghc-9.10.3 -- ghc -hide-all-packages -package base -package bytestring -package text \
  -package golem-emet-0.1.0 -package golem-eval-0.1.0 -package golem-syntax-0.1.0 \
  -outputdir "$work" "$suite/EvalCases.hs" -o "$work/eval-cases"
"$work/eval-cases" > "$work/haskell"
"${LEAN:-lean}" -o "$work/Eval.olean" "$suite/Eval.lean"
LEAN_PATH="$work" "${LEAN:-lean}" --run "$suite/EvalCases.lean" > "$work/lean"
if ! cmp -s "$work/haskell" "$work/lean"; then
  diff -u "$work/haskell" "$work/lean" | head -n 12 >&2
  exit 1
fi
test "$(wc -l < "$work/haskell")" -eq 2508
echo '2508 Emet evaluation results matched'
