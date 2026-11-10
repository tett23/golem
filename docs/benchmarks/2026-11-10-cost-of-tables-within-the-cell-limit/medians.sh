#!/bin/sh
# medians.sh RESULTS: the median and the range of each value per table and mode
f=$1
for fx in c10-r1000 c10-r2000 c10-r4000 c10-r8000 c10-r10000 c8-r10000; do for m in shipped audit; do
 med() { grep " $fx $m " "$f" | sed "s/.* $1=\([^ ]*\).*/\1/" | sort -g | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}'; }
 rng() { grep " $fx $m " "$f" | sed "s/.* $1=\([^ ]*\).*/\1/" | sort -g | awk '{a[NR]=$1} END{print a[1]"-"a[NR]}'; }
 echo "$fx $m n=$(grep -c " $fx $m " $f) wall=$(med wall) [$(rng wall)] cpu=$(med cpu) [$(rng cpu)] mut=$(med mut) gc=$(med gc) alloc=$(med alloc) [$(rng alloc)] maxres=$(med maxres) [$(rng maxres)] mem=$(med mem) load=$(med load) [$(rng load)] hashes=$(grep " $fx $m " $f | sed 's/.*hash=//' | sort -u | tr '\n' ' ') exits=$(grep " $fx $m " $f | sed 's/.*exit=\([0-9]*\).*/\1/' | sort -u | tr '\n' ' ')"
done; done
