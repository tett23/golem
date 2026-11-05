#!/bin/bash
# A temporary benchmark for docs/adr/0098: shem v0.1.0-rc3 and v0.1.0-rc4
# on the 17 PDFs of the visual regression test. Not for main.
#   bench.sh <dir of PDFs> <shem rc3> <shem rc4>
set -eu
PDFS=$1; RC3=$2; RC4=$3
OUT=${RUNNER_TEMP:-/tmp}/bench; mkdir -p "$OUT"
export LC_ALL=C

echo "## machine"
echo "nproc=$(nproc) online=$(getconf _NPROCESSORS_ONLN)"
lscpu | grep -E 'Model name|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)'
"$RC3" --version; "$RC4" --version

# one PDF -> its page hashes in $3; args: shem pdf out [jobs]
hashes() {
  local shem=$1 pdf=$2 out=$3 jobs=${4:-} d
  d=$(mktemp -d "$OUT/r.XXXXXX")
  "$shem" render --dpi 72 --format ppm ${jobs:+--jobs "$jobs"} "$pdf" "$d/ppm" >/dev/null
  (cd "$d/ppm" && ls | sort -V | xargs sha256sum) >"$out"
  rm -rf "$d"
}
export -f hashes; export OUT

t() { # label, command...
  local label=$1; shift
  local s e
  s=$(date +%s.%N)
  /usr/bin/time -f "%U %S" -o "$OUT/time" "$@"
  e=$(date +%s.%N)
  printf '| %s | %.2f | %s | %s |\n' "$label" "$(echo "$e - $s" | bc)" $(cat "$OUT/time")
}

ALL=$(ls "$PDFS"/*.pdf)
BIG=$(ls -S "$PDFS"/*.pdf)

seq_run() { # shem jobs tag
  for p in $ALL; do hashes "$1" "$p" "$OUT/$3.$(basename "$p").txt" "$2"; done
}
par_run() { # shem P jobs tag
  echo "$BIG" | xargs -n 1 -P "$2" -I{} bash -c 'hashes "$0" "$1" "$OUT/$3.$(basename "$1").txt" "$2"' "$1" {} "$3" "$4"
}
export -f seq_run par_run; export ALL BIG

echo "## manual.pdf (wall user sys, s)"
echo "| config | wall | user | sys |"
echo "|---|---|---|---|"
for v in rc3 rc4; do
  s=$RC3; [ $v = rc4 ] && s=$RC4
  for r in 1 2 3; do
    for j in 1 2 4 ""; do
      t "$v --jobs ${j:-default} #$r" bash -c 'hashes "$@"' _ "$s" "$PDFS/manual.pdf" "$OUT/m.$v.${j:-d}.txt" $j
    done
    [ $v = rc3 ] && break
  done
done

echo "## 17 PDFs (wall user sys, s)"
echo "| config | wall | user | sys |"
echo "|---|---|---|---|"
for r in 1 2 3; do
  for v in rc3 rc4; do
    s=$RC3; [ $v = rc4 ] && s=$RC4
    if [ $v = rc4 ] || [ $r = 1 ]; then
      t "$v seq default #$r" bash -c 'seq_run "$0" "" "$1"' "$s" "$v.seqd"
      t "$v seq --jobs 1 #$r" bash -c 'seq_run "$0" 1 "$1"' "$s" "$v.seq1"
      t "$v xargs -P 2, --jobs 1 #$r" bash -c 'par_run "$0" 2 1 "$1"' "$s" "$v.p2j1"
      t "$v xargs -P 4, --jobs 1 #$r" bash -c 'par_run "$0" 4 1 "$1"' "$s" "$v.p4j1"
      t "$v xargs -P 2, --jobs 2 #$r" bash -c 'par_run "$0" 2 2 "$1"' "$s" "$v.p2j2"
    fi
  done
done

echo "## identical hashes"
ref=$OUT/rc3.seqd
for p in $ALL; do
  b=$(basename "$p")
  for f in "$OUT"/*."$b".txt; do cmp -s "$f" "$ref.$b.txt" || echo "DIFF $f"; done
done
for f in "$OUT"/m.*.txt; do cmp -s "$f" "$ref.manual.pdf.txt" || echo "DIFF $f"; done
echo "pages: $(cat "$ref".*.txt | wc -l)"
echo "done"
