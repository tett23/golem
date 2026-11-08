#!/bin/sh
# The typefaces of a PDF (docs/adr/0232): the BaseFont of every font
# dictionary, read with qpdf --json, without the tag of a subset (six
# capital letters and +), one per line, sorted, each once.
#
#   pdf-fonts.sh PDF [FONT...]
#
# Given FONTs, it fails (exit code 1) when the PDF has a typeface that is
# none of them, and names each such typeface on stderr. CI gives it the
# fonts of a manual, the files its fonts/ holds without .otf
# (scripts/manual/fetch-fonts.sh), so that the PDF of a manual uses no
# other typeface. qpdf and jq are needed; without them, or without a PDF,
# the exit code is 2.
set -eu
if [ $# -lt 1 ]; then
  echo "usage: pdf-fonts.sh PDF [FONT...]" >&2
  exit 2
fi
PDF=$1
shift
for tool in qpdf jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "pdf-fonts: $tool is not installed" >&2; exit 2; }
done
[ -f "$PDF" ] || { echo "pdf-fonts: no such file: $PDF" >&2; exit 2; }
LIST=$(mktemp)
trap 'rm -f "$LIST" "$LIST.json" "$LIST.err"' EXIT
# qpdf exits with 3 on warnings; the JSON is still written
CODE=0
qpdf --json=2 --json-key=qpdf "$PDF" >"$LIST.json" 2>"$LIST.err" || CODE=$?
if [ "$CODE" -ne 0 ] && [ "$CODE" -ne 3 ]; then
  cat "$LIST.err" >&2
  echo "pdf-fonts: qpdf could not read $PDF" >&2
  exit 2
fi
jq -r '.. | objects | select(."/Type" == "/Font" and has("/BaseFont")) | ."/BaseFont"' "$LIST.json" |
  sed -e 's|^/||' -e 's|^[A-Z][A-Z][A-Z][A-Z][A-Z][A-Z]+||' | LC_ALL=C sort -u >"$LIST"
cat "$LIST"
[ $# -gt 0 ] || exit 0
BAD=0
while read -r face; do
  found=0
  for allowed in "$@"; do
    if [ "$face" = "$allowed" ]; then found=1; fi
  done
  if [ "$found" = 0 ]; then
    echo "pdf-fonts: $PDF has $face, which is not a font of the list" >&2
    BAD=1
  fi
done <"$LIST"
exit "$BAD"
