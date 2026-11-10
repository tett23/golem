#!/bin/sh
# measure-heap.sh BEFORE AFTER FIXTURES OUT
# Run the six table inputs three times per binary, alternating before/after.
# BEFORE and AFTER must be the golem executables built from ff5d9b11 and
# 2e074342, respectively, each with -rtsopts and the shipped -N -A64m.
# FIXTURES is made with make-tables.sh; OUT must be a new, empty directory.
set -eu
[ "$#" -eq 4 ] || { echo 'usage: measure-heap.sh BEFORE AFTER FIXTURES OUT' >&2; exit 2; }
before=$1 after=$2 fixtures=$3 out=$4
[ -x "$before" ] && [ -x "$after" ] || { echo 'measure-heap.sh: executables not found' >&2; exit 2; }
[ -d "$fixtures" ] && [ -d "$out" ] || { echo 'measure-heap.sh: directory not found' >&2; exit 2; }
[ -z "$(ls -A "$out")" ] || { echo 'measure-heap.sh: OUT must be empty' >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
printf 'round\tinput\tside\texit\tpeak_bytes\tallocated_bytes\tresidency_bytes\toutput_sha256\n' > "$out/results.tsv"

round=1
while [ "$round" -le 3 ]; do
  for name in c10-r1000 c10-r2000 c10-r4000 c10-r8000 c10-r10000 c8-r10000; do
    sides='before after'
    for side in $sides; do
      case "$side" in before) exe=$before ;; after) exe=$after ;; esac
      book=$fixtures/$name
      [ -d "$book" ] || { echo "measure-heap.sh: no input $book" >&2; exit 2; }
      run=$out/r${round}-${name}-${side}
      mkdir "$run"
      if [ -d "$book/build" ]; then rm -r "$book/build"; fi
      if (cd "$book" && "$exe" build --target pdf +RTS -hT -i0.01 -A1m -s -RTS > "$run/stdout.txt" 2> "$run/rts.txt"); then
        code=0
      else
        code=$?
      fi
      profile=$book/$(basename "$exe").hp
      [ -f "$profile" ] || { echo "measure-heap.sh: no profile for $name $side" >&2; exit 1; }
      mv "$profile" "$run/heap.hp"
      peak=$(sh "$here/peak.sh" "$run/heap.hp")
      sh "$here/peak.sh" --types "$run/heap.hp" > "$run/types.tsv"
      allocated=$(awk '/bytes allocated in the heap/ { gsub(",", "", $1); print $1 }' "$run/rts.txt")
      residency=$(awk '/bytes maximum residency/ { gsub(",", "", $1); print $1 }' "$run/rts.txt")
      [ -n "$allocated" ] && [ -n "$residency" ] || { echo "measure-heap.sh: no RTS values for $name $side" >&2; exit 1; }
      output_hash=$( (cd "$book" && find build -type f -print | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done; cat "$run/stdout.txt") | shasum -a 256 | awk '{print $1}')
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$round" "$name" "$side" "$code" "$peak" "$allocated" "$residency" "$output_hash" >> "$out/results.tsv"
      printf 'round=%s input=%s side=%s exit=%s peak=%s allocated=%s\n' "$round" "$name" "$side" "$code" "$peak" "$allocated"
      [ "$code" -eq 0 ] || exit 1
    done
  done
  round=$((round + 1))
done
