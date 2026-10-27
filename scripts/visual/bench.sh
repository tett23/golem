#!/bin/sh
# MEASUREMENT ONLY (not for merge): times check.sh PDFS in three forms,
# ROUNDS rounds each, interleaved, on the same machine.
#   a: VISUAL_JOBS=<cores> x shem --jobs 1   (docs/adr/0098 draft)
#   b: VISUAL_JOBS=1 x shem default --jobs   (docs/adr/0094 original)
#   c: VISUAL_JOBS=2 x shem --jobs 2
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PDFS=$1
ROUNDS=${2:-3}
NCPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
ms() { echo $(( $(date +%s%N) / 1000000 )); }
run() {
  t0=$(ms)
  env VISUAL_JOBS="$2" VISUAL_SHEM_JOBS="$3" sh "$HERE/check.sh" "$PDFS" >/dev/null 2>&1
  t1=$(ms)
  echo "bench form=$1 VISUAL_JOBS=$2 shem_jobs=${3:-default} ms=$((t1 - t0))"
}
r=1
while [ "$r" -le "$ROUNDS" ]; do
  run a "$NCPU" 1
  run b 1 ""
  run c 2 2
  r=$((r + 1))
done
