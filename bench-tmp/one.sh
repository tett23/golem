#!/bin/sh
# one.sh PDF DIR JOBS: renders PDF at 72 dpi PPM into DIR/<name>, writes the
# SHA-256 of its pages to DIR/<name>.txt and removes the PPMs
set -eu
pdf=$1 dir=$2 jobs=$3 n=$(basename "$1" .pdf)
if command -v sha256sum >/dev/null 2>&1; then SHA=sha256sum; else SHA="shasum -a 256"; fi
rm -rf "$dir/$n"
if [ "$jobs" = default ]; then "$SHEM" render --dpi 72 --format ppm "$pdf" "$dir/$n" >/dev/null
else "$SHEM" render --dpi 72 --format ppm --jobs "$jobs" "$pdf" "$dir/$n" >/dev/null; fi
find "$dir/$n" -type f -name 'page-*.ppm' | xargs $SHA | sed "s#^\([0-9a-f]*\) [ *]*.*/\(page-[0-9]*\)\.ppm\$#\1  $n \2#" >"$dir/$n.txt"
rm -rf "${dir:?}/$n"
