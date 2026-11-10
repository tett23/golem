#!/bin/sh
# peak.sh FILE: print the largest total of a heap-profile sample in bytes.
# peak.sh --types FILE: print the types in that sample, largest first.
set -eu

if [ "$#" -eq 1 ]; then
  mode=peak
  file=$1
elif [ "$#" -eq 2 ] && [ "$1" = --types ]; then
  mode=types
  file=$2
else
  echo 'usage: peak.sh [--types] FILE.hp' >&2
  exit 2
fi
[ -f "$file" ] || { echo "peak.sh: no file: $file" >&2; exit 2; }
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

awk -v mode="$mode" '
  /^BEGIN_SAMPLE[[:space:]]/ { in_sample = 1; total = 0; for (k in sample) delete sample[k]; next }
  /^END_SAMPLE[[:space:]]/ {
    if (in_sample && (!seen || total > peak)) {
      peak = total; seen = 1
      for (k in types) delete types[k]
      for (k in sample) types[k] = sample[k]
    }
    in_sample = 0
    next
  }
  in_sample && index($0, "\t") {
    n = split($0, fields, "\t")
    value = fields[n] + 0
    label = substr($0, 1, length($0) - length(fields[n]) - 1)
    total += value
    sample[label] += value
  }
  END {
    if (!seen) exit 1
    if (mode == "peak") printf "%.0f\n", peak
    else for (k in types) printf "%s\t%.0f\n", k, types[k]
  }
' "$file" > "$tmp"
if [ "$mode" = types ]; then LC_ALL=C sort -t '	' -k2,2nr "$tmp"; else cat "$tmp"; fi
