#!/bin/bash
# TEMPORARY diagnostics of the visual job's speed; not to be merged.
set -u
SHEM=third_party/shem/shem
P=visual-pdfs
TIMEFORMAT='real %R user %U sys %S'
echo "nproc=$(nproc) getconf=$(getconf _NPROCESSORS_ONLN)"
grep -m1 'model name' /proc/cpuinfo
cat /sys/fs/cgroup/cpu.max 2>/dev/null || true
df -h "$RUNNER_TEMP" /dev/shm | tail -n +1
uname -a
T=$RUNNER_TEMP/diag
for d in "$T" /dev/shm/diag; do
  for j in default 1 2 4; do
    rm -rf "$d"
    if [ "$j" = default ]; then a=""; else a="--jobs $j"; fi
    echo -n "manual.pdf dir=$d jobs=$j "
    { time $SHEM render --dpi 72 --format ppm $a "$P/manual.pdf" "$d" >/dev/null; } 2>&1
  done
  echo -n "hash 310 pages in $d: "
  { time sh -c "find '$d' -type f -name 'page-*.ppm' | xargs sha256sum >/dev/null"; } 2>&1
  rm -rf "$d"
done
sudo apt-get install -y -qq strace >/dev/null 2>&1 || true
for j in 1 4; do
  rm -rf "$T"
  echo "== strace -f -c manual.pdf --jobs $j"
  strace -f -c -o "$RUNNER_TEMP/strace.txt" $SHEM render --dpi 72 --format ppm --jobs $j "$P/manual.pdf" "$T" >/dev/null
  head -12 "$RUNNER_TEMP/strace.txt"
done
rm -rf "$T"
echo "== per input, --jobs 1, sequential"
echo -n "total "
{ time for f in "$P"/*.pdf; do
  n=$(basename "$f" .pdf)
  s=$(date +%s.%N)
  $SHEM render --dpi 72 --format ppm --jobs 1 "$f" "$T/$n" >/dev/null
  e=$(date +%s.%N)
  echo "  $n $(ls "$T/$n" | wc -l) pages $(echo "$e - $s" | bc) s" >&2
  rm -rf "$T/$n"
done; } 2>&1
for n in 2 4; do
  echo -n "== xargs -P $n, --jobs 1, all inputs: "
  { time ls "$P"/*.pdf | xargs -P "$n" -I{} sh -c 'f={}; n=$(basename "$f" .pdf); '"$SHEM"' render --dpi 72 --format ppm --jobs 1 "$f" "'"$T"'/$n" >/dev/null && rm -rf "'"$T"'/$n"'; } 2>&1
done
echo -n "== xargs -P 4, --jobs 1, all inputs, manuals first: "
{ time { printf '%s\n' "$P/manual.pdf" "$P/manual-dev.pdf"; ls "$P"/*.pdf | grep -v '/manual'; } | xargs -P 4 -I{} sh -c 'f={}; n=$(basename "$f" .pdf); '"$SHEM"' render --dpi 72 --format ppm --jobs 1 "$f" "'"$T"'/$n" >/dev/null && rm -rf "'"$T"'/$n"'; } 2>&1
exit 0
