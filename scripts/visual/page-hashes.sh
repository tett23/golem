#!/bin/sh
# The SHA-256 of the pages of one PDF of the visual regression test; check.sh
# runs one of these for each input, several at once (docs/adr/0097).
#
#   page-hashes.sh SHEM PDFS WORK INPUT
#
# renders PDFS/INPUT.pdf with `SHEM render --dpi 72 --format ppm --jobs 1`
# into a directory of WORK, and writes WORK/new/INPUT.txt: a line
# `<SHA-256>  page-<n>` per page, in the order of the pages (LC_ALL=C). The
# PPMs are removed at once. When shem fails, WORK/new/INPUT.txt is not
# written, and WORK/err/INPUT holds the stderr of shem. The exit code is 0
# either way, so that xargs goes on with the other inputs; check.sh reads
# the result from the files.
set -eu
[ $# -eq 4 ] || { echo "usage: page-hashes.sh SHEM PDFS WORK INPUT" >&2; exit 2; }
SHEM=$1 PDFS=$2 WORK=$3 input=$4
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
echo "check: rendering $input" >&2
PPM=$WORK/ppm/$input
rm -rf "$PPM"
# --jobs 1: the PDFs run side by side instead, each in a process of its own
# (docs/adr/0097)
if ! "$SHEM" render --dpi 72 --format ppm --jobs 1 "$PDFS/$input.pdf" "$PPM" >/dev/null 2>"$WORK/err/$input"; then
  rm -rf "$PPM"
  exit 0
fi
rm -f "$WORK/err/$input"
# the SHA-256 of every page, by the name of the page, in the order of the
# pages; mktemp gives a path without spaces, which xargs would split
: >"$WORK/new/$input.part"
if [ -d "$PPM" ]; then
  find "$PPM" -type f -name 'page-*.ppm' >"$WORK/ppm/$input.files"
  if [ -s "$WORK/ppm/$input.files" ]; then
    xargs $SHA <"$WORK/ppm/$input.files" |
      sed 's#^\([0-9a-f]*\) [ *]*.*/\(page-[0-9]*\)\.ppm$#\1  \2#' | LC_ALL=C sort -k 2,2 >"$WORK/new/$input.part"
  fi
  rm -f "$WORK/ppm/$input.files"
fi
rm -rf "$PPM"
mv "$WORK/new/$input.part" "$WORK/new/$input.txt"
