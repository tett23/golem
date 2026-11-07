#!/bin/sh
# Checks PDFs against PDF/A-2a and PDF/UA-1 with veraPDF
# (docs/adr/0183-tagged-pdf-and-pdf-a.md).
#
#   verapdf.sh VERAPDF DIR    checks every DIR/*.pdf
#
# First the untagged PDF of scripts/ci/testdata/verapdf must fail PDF/UA-1
# (exit code 1), so that a wrong call of veraPDF does not pass everything.
# Then every PDF is checked with -f 2a and -f ua1; for each check that does
# not pass (an exit code other than 0), the text report of veraPDF with
# --verbose names the PDF and the rules, and the script ends with exit
# code 1 after every check.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 2 ] || { echo "usage: verapdf.sh VERAPDF DIR" >&2; exit 2; }
VERAPDF=$1
DIR=$2
code=0
"$VERAPDF" -f ua1 --format text "$HERE/testdata/verapdf/untagged.pdf" >/dev/null 2>&1 || code=$?
if [ "$code" != 1 ]; then
  echo "verapdf: the untagged PDF did not fail PDF/UA-1 (exit code $code)" >&2
  exit 1
fi
found=0
failed=0
for pdf in "$DIR"/*.pdf; do
  [ -f "$pdf" ] || continue
  found=1
  for flavour in 2a ua1; do
    code=0
    report=$("$VERAPDF" -f "$flavour" --format text --verbose "$pdf" 2>/dev/null) || code=$?
    if [ "$code" = 0 ]; then
      echo "verapdf: $(basename "$pdf"): $flavour: passed"
    else
      echo "verapdf: $(basename "$pdf"): $flavour: failed (exit code $code)" >&2
      printf '%s\n' "$report" >&2
      failed=1
    fi
  done
done
if [ "$found" = 0 ]; then
  echo "verapdf: no PDF in $DIR" >&2
  exit 1
fi
[ "$failed" = 0 ]
