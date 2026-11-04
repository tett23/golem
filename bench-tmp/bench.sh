#!/bin/sh
# bench.sh SHEM PDFS REPS: times the rendering of every PDF at 72 dpi PPM
# with the SHA-256 of the pages, in several shapes, REPS times each; prints
# a TSV line per run: shape rep seconds sum-of-all-page-hashes
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SHEM=$1 PDFS=$2 REPS=$3
export SHEM
if command -v sha256sum >/dev/null 2>&1; then SHA=sha256sum; else SHA="shasum -a 256"; fi
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
NPROC=$(getconf _NPROCESSORS_ONLN)
run() {
  shape=$1 rep=$2 W=$(mktemp -d)
  t0=$(now)
  case $shape in
    seq-*) j=${shape#seq-}; for pdf in "$PDFS"/*.pdf; do sh "$HERE/one.sh" "$pdf" "$W" "$j"; done ;;
    par*) p=${shape#par}; p=${p%%-*}; j=${shape##*-j}
      ls -S "$PDFS"/*.pdf | xargs -n 1 -P "$p" -I{} sh "$HERE/one.sh" {} "$W" "$j" ;;
  esac
  t1=$(now)
  sum=$(cat "$W"/*.txt | LC_ALL=C sort | $SHA | cut -c1-16)
  printf '%s\t%s\t%s\t%s\n' "$shape" "$rep" "$(echo "$t1 - $t0" | bc)" "$sum"
  rm -rf "$W"
}
SHAPES=${SHAPES:-"seq-default seq-1 seq-2 seq-$NPROC seq-8 par$NPROC-j1 par2-j1 par2-j2 par$NPROC-j2 par$NPROC-jdefault"}
echo "nproc=$NPROC $(uname -sm) $("$SHEM" --version)"
rep=1
while [ "$rep" -le "$REPS" ]; do
  for s in $SHAPES; do run "$s" "$rep"; done
  rep=$((rep + 1))
done
