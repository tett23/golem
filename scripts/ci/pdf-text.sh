#!/bin/sh
# The text of a PDF as Poppler reads it (docs/adr/0232, docs/adr/0233):
# pdftotext writes the text of every page, and the checks look for
# strings in it, each within a line of the text.
#
#   pdf-text.sh PDF [--has TEXT | --lacks TEXT]...
#
# Without a check it writes the text to stdout. --has fails when no line
# of the text holds TEXT, --lacks when a line does; each failure is named
# on stderr and the exit code is 1. CI checks with it that the code of the
# developer manual written \| in the source shows | (docs/adr/0233).
# pdftotext is needed; without it, without a PDF or with a check that is
# not --has or --lacks followed by its TEXT, the exit code is 2.
set -eu
usage() {
  echo "usage: pdf-text.sh PDF [--has TEXT | --lacks TEXT]..." >&2
  exit 2
}
[ $# -ge 1 ] || usage
PDF=$1
shift
# the checks are read before pdftotext runs: a wrong one is a usage error
n=$#
while [ "$n" -gt 0 ]; do
  case "$1" in
    --has | --lacks) [ "$n" -ge 2 ] || usage ;;
    *) usage ;;
  esac
  set -- "$@" "$1" "$2"
  shift 2
  n=$((n - 2))
done
command -v pdftotext >/dev/null 2>&1 || { echo "pdf-text: pdftotext is not installed" >&2; exit 2; }
[ -f "$PDF" ] || { echo "pdf-text: no such file: $PDF" >&2; exit 2; }
TEXT=$(mktemp)
trap 'rm -f "$TEXT" "$TEXT.err"' EXIT
pdftotext -enc UTF-8 "$PDF" "$TEXT" 2>"$TEXT.err" || {
  cat "$TEXT.err" >&2
  echo "pdf-text: pdftotext could not read $PDF" >&2
  exit 2
}
if [ $# -eq 0 ]; then
  cat "$TEXT"
  exit 0
fi
BAD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --has)
      if ! grep -qF -e "$2" "$TEXT"; then
        echo "pdf-text: $PDF does not have: $2" >&2
        BAD=1
      fi
      ;;
    --lacks)
      if grep -qF -e "$2" "$TEXT"; then
        echo "pdf-text: $PDF has: $2" >&2
        grep -nF -e "$2" "$TEXT" >&2
        BAD=1
      fi
      ;;
  esac
  shift 2
done
exit "$BAD"
