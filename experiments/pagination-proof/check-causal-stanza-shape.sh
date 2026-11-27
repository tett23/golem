#!/bin/sh
# Root ADR 0352: the mutual entry trace follows every stanza/accept branch.
# Optional paths allow negative checks without editing the original files.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
proof=${1:-$root/experiments/pagination-proof/CausalStanzaEntries.lean}
model=${2:-$root/experiments/pagination-proof/Physical.lean}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
for line in \
  '  WrapReady region cursor ∧' \
  '  WrapReady region cursor ∧ (∀ snapshot ∈ trials, WrapReady region snapshot) ∧' \
  '    verseEntriesSafe env region b cursor (firstIndex :: rest) ∧' \
  '        WrapReady region settled ∧' \
  '          WrapReady region held ∧'; do
  grep -Fqx "$line" "$proof" || {
    echo "missing stanza entry condition: $line" >&2
    exit 1
  }
done
extract() {
  awk -v name="$2" '
    $0 ~ "^def " name " " { copy = 1; next }
    /^termination_by / { if (copy) exit }
    copy {
      if (!body) {
        if ($0 !~ /\(?match indices with/ && $0 !~ /\(?if h0 : count = 0/) next
        body = 1
      }
      if ($0 ~ /WrapReady region/ || $0 ~ /verseEntriesSafe env/) next
      $1 = $1
      if (!NF || $0 == ")" || $0 == "))") next
      sub(/^\(match /, "match ")
      sub(/^\(if /, "if ")
      sub(/True\)\)$/, "True")
      gsub(/\.error e => \.error e/, ".error _ => True")
      sub(/then \.error \(\.noProgress.*$/, "then True")
      sub(/=> \.error \(\.noProgress.*$/, "=> True")
      gsub(/\.ok \(checkWaits cursor\)/, "True")
      gsub(/\.ok cursor/, "True")
      gsub(/\.ok held/, "True")
      gsub(/stanza env region b a/, "stanzaEntriesSafe env region b a")
      gsub(/accept env region b a/, "acceptEntriesSafe env region b a")
      print
    }
  ' "$1"
}
for name in stanza accept; do
  extract "$model" "$name" > "$tmp/$name.model"
  extract "$proof" "${name}EntriesSafe" > "$tmp/$name.proof"
  [ -s "$tmp/$name.model" ] && [ -s "$tmp/$name.proof" ] || {
    echo "missing $name or ${name}EntriesSafe definition" >&2
    exit 1
  }
  diff -u "$tmp/$name.model" "$tmp/$name.proof"
done
