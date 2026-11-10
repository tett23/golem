#!/bin/sh
# measure.sh ROUNDS OUT: builds every table of make-tables.sh (in fx/ next to
# this script) ROUNDS times with golem-rtsopts (next to this script), once
# with the RTS options it was linked with (-N -A64m, "shipped") and once with
# -A4m (the nursery of the audit of 2026-11-09, "audit"), and appends one line
# per build to OUT: the load average of one minute, the exit code, the wall
# clock, the +RTS -s values and a hash of build/ and of the output.
B=$(cd "$(dirname "$0")" && pwd)
ROUNDS=$1; OUT=$2
: > "$OUT"
r=1
while [ $r -le "$ROUNDS" ]; do
  for f in c10-r1000 c10-r2000 c10-r4000 c10-r8000 c10-r10000 c8-r10000; do
    for mode in shipped audit; do
      cd "$B/fx/$f" || exit 1
      rm -rf build
      if [ $mode = shipped ]; then extra=""; else extra="-A4m"; fi
      load=$(uptime | sed "s/.*load averages*: *//" | awk "{print \$1}" | tr -d ,)
      s=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
      "$B/golem-rtsopts" build --target pdf +RTS -s"$B/rts.txt" $extra -RTS > "$B/out.txt" 2>&1
      code=$?
      e=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
      h=$( (find build -type f | sort | xargs shasum -a 256; cat "$B/out.txt") | shasum -a 256 | cut -c1-12)
      alloc=$(awk '/bytes allocated/{gsub(",","",$1);print $1}' "$B/rts.txt")
      res=$(awk '/maximum residency/{gsub(",","",$1);print $1}' "$B/rts.txt")
      tot=$(awk '/Total   time/{print $3}' "$B/rts.txt" | tr -d s)
      mut=$(awk '/MUT     time/{print $3}' "$B/rts.txt" | tr -d s)
      gc=$(awk '/GC      time/{print $3}' "$B/rts.txt" | tr -d s)
      mem=$(awk '/total memory in use/{print $1}' "$B/rts.txt")
      wall=$(echo "$e - $s" | bc)
      echo "$r $f $mode load=$load exit=$code wall=$wall cpu=$tot mut=$mut gc=$gc alloc=$alloc maxres=$res mem=$mem hash=$h" >> "$OUT"
    done
  done
  r=$((r+1))
done
