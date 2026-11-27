#!/bin/sh
# Root ADR 0352: every paragraphs branch is represented by its entry trace.
# Optional paths allow negative checks without changing either source.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
proof=${1:-$root/experiments/pagination-proof/CausalCalls.lean}
model=${2:-$root/experiments/pagination-proof/Physical.lean}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
for line in \
  '  WrapReady region cursor ∧' \
  '      WrapReady region pre ∧' \
  '        verseEntriesSafe env region b pre (verseSpan b index later).1 ∧'; do
  grep -Fqx "$line" "$proof" || {
    echo "missing causal entry condition: $line" >&2
    exit 1
  }
done
[ "$(grep -Fc 'WrapReady region ready ∧' "$proof")" -eq 2 ] || {
  echo 'missing one of the two placement entry conditions' >&2
  exit 1
}
awk '
  /^def paragraphs / { copy = 1; next }
  /^termination_by / { if (copy) exit }
  copy {
    if (!body) {
      if ($0 !~ /match indices with/) next
      body = 1
    }
    gsub(/\.error e => \.error e/, ".error _ => True")
    gsub(/\.ok cursor/, "True")
    sub(/paragraphs env region b a p/, "causalParagraphEntriesSafe env region b a p")
    print
  }
' "$model" > "$tmp/model"
awk '
  /^def causalParagraphEntriesSafe / { copy = 1; next }
  /^termination_by / { if (copy) exit }
  copy {
    if (!body) {
      if ($0 !~ /\(match indices with/) next
      body = 1
    }
    if ($0 ~ /WrapReady region/ || $0 ~ /verseEntriesSafe env/) next
    sub(/\(match /, "match ")
    sub(/\(if /, "if ")
    sub(/\.2\)\)$/, ".2")
    sub(/later\)\)\)$/, "later")
    print
  }
' "$proof" > "$tmp/proof"
for file in model proof; do
  awk 'NF { $1 = $1; print }' "$tmp/$file" > "$tmp/$file.normal"
done
[ -s "$tmp/model.normal" ] && [ -s "$tmp/proof.normal" ] || {
  echo 'missing paragraphs or causalParagraphEntriesSafe definition' >&2
  exit 1
}
diff -u "$tmp/model.normal" "$tmp/proof.normal"
