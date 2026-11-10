#!/bin/sh
# measure-books.sh ROUNDS OUT: builds the user manual and the ten books (in books/ next to
# this script) ROUNDS times with golem-before and golem-after (next to this
# script, both linked with -rtsopts and the shipped -N -A64m), the two in
# turn for each table, the order of the two swapped every round, and appends
# one line per build to OUT: the load average of one minute, the exit code,
# the wall clock, the +RTS -s values and a hash of build/ and of the output.
B=$(cd "$(dirname "$0")" && pwd)
ROUNDS=$1; OUT=$2
: > "$OUT"
r=1
while [ $r -le "$ROUNDS" ]; do
  if [ $((r % 2)) -eq 1 ]; then order="before after"; else order="after before"; fi
  for f in manual koya-hijiri ichiaku-no-suna haru-to-shura taira-no-masakado ushiyama-hotel merry-wives frogs snark elements-of-style nightmare-abbey; do
    for bin in $order; do
      cd "$B/books/$f" || exit 1
      rm -rf build
      load=$(uptime | sed "s/.*load averages*: *//" | awk "{print \$1}" | tr -d ,)
      s=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
      "$B/golem-$bin" build --target pdf +RTS -s"$B/rts.txt" -RTS > "$B/out.txt" 2>&1
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
      echo "$r $f $bin load=$load exit=$code wall=$wall cpu=$tot mut=$mut gc=$gc alloc=$alloc maxres=$res mem=$mem hash=$h" >> "$OUT"
    done
  done
  r=$((r+1))
done
