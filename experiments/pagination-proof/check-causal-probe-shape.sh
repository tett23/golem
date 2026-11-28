#!/bin/sh
# Root ADR 0352: every probeNext/probeChain call is represented by its entry trace.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
proof=${1:-$root/experiments/pagination-proof/CausalProbeEntries.lean}
model=${2:-$root/experiments/pagination-proof/Physical.lean}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
for line in \
  '  WrapReady region cursor ∧' \
  '  | [] => WrapReady region (endWrap region cursor)' \
  '      WrapReady region ready ∧' \
  '        verseEntriesSafe env region b ready verses ∧' \
  '          WrapReady region placed ∧'; do
  grep -Fqx "$line" "$proof" || {
    echo "missing probe entry condition: $line" >&2
    exit 1
  }
done
extract() {
  awk -v name="$2" '
    function followingLine(expected) {
      if (getline <= 0) { print "missing terminal probe branch" > "/dev/stderr"; exit 1 }
      $1 = $1
      if ($0 != expected) { print "unexpected terminal probe branch: " $0 > "/dev/stderr"; exit 1 }
    }
    $0 ~ "^def " name " " { copy = 1; next }
    /^termination_by / { if (copy) exit }
    copy {
      if (!body) {
        if ($0 !~ /\(?match later with/ && $0 !~ /\(?if 0 < /) next
        body = 1
      }
      $1 = $1
      if (!NF || $0 ~ /^WrapReady region [a-zA-Z]+ ∧/ || $0 ~ /^verseEntriesSafe /) next
      sub(/^\(match /, "match ")
      sub(/^\(if /, "if ")
      sub(/^\(let /, "let ")
      sub(/^chain\)+$/, "chain")
      sub(/True\)$/, "True")
      if ($0 ~ /match probeNext env region b p .* with$/) {
        sub(/match probeNext /, "probeEntriesSafe "); sub(/ with$/, "")
        print
        followingLine("| .error e => .error e")
        followingLine("| .ok r => .ok r.2.2")
        next
      }
      if ($0 == "match chain with") {
        print "chain"
        followingLine("| .error e => .error e")
        followingLine("| .ok chainFits => .ok (required, true, prefixFits && chainFits)")
        next
      }
      gsub(/\.ok \(p.following \(endWrap region cursor\) wanted\)/, "WrapReady region (endWrap region cursor)")
      gsub(/\.error e => \.error e/, ".error _ => True")
      sub(/=> \.ok \(required, true, false\)$/, "=> True")
      gsub(/\.ok true/, "True")
      gsub(/let chain : Except Failure Bool :=/, "let chain : Prop :=")
      gsub(/probeChain env region b p/, "probeChainEntriesSafe env region b p")
      print
    }
  ' "$1"
}
compare() {
  extract "$model" "$1" > "$tmp/model"
  extract "$proof" "$2" > "$tmp/proof"
  [ -s "$tmp/model" ] && [ -s "$tmp/proof" ] || {
    echo "missing $1 or $2 definition" >&2
    exit 1
  }
  diff -u "$tmp/model" "$tmp/proof"
}
compare probeNext probeEntriesSafe
compare probeChain probeChainEntriesSafe
