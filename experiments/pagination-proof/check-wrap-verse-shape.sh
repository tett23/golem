#!/bin/sh
# Root ADR 0352: the entry invariant follows every tryVerses recursive edge.
# Optional paths permit negative checks without changing the source files.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
proof=${1:-$root/experiments/pagination-proof/WrapVerses.lean}
model=${2:-$root/experiments/pagination-proof/Physical.lean}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
grep -Fqx '  WrapReady region cursor ∧' "$proof" || {
  echo 'missing wrap-ready entry condition' >&2
  exit 1
}
awk '
  /^def tryVerses / { copy = 1; next }
  /^theorem / { if (copy) exit }
  copy {
    if (skip) { skip--; next }
    if ($0 ~ /match tryVerses .* with/) {
      sub(/match tryVerses /, "verseEntriesSafe "); sub(/ with$/, "");
      print; skip = 2; next
    }
    gsub(/\.error e => \.error e/, ".error _ => True")
    gsub(/\.ok \[\]/, "True")
    print
  }
' "$model" > "$tmp/model"
awk '
  /^def verseEntriesSafe / { copy = 1; next }
  /^\/--/ { if (copy) exit }
  copy {
    if ($0 == "  WrapReady region cursor ∧" || $0 ~ /\(match indices with/) next
    sub(/True\)$/, "True")
    print
  }
' "$proof" > "$tmp/proof"
# The empty entry only states WrapReady; normalize its trivial tail.
for file in model proof; do
  awk 'NF { $1 = $1; print }' "$tmp/$file" > "$tmp/$file.normal"
done
[ -s "$tmp/model.normal" ] && [ -s "$tmp/proof.normal" ] || {
  echo 'missing tryVerses or verseEntriesSafe definition' >&2
  exit 1
}
diff -u "$tmp/model.normal" "$tmp/proof.normal"
