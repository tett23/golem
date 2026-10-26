#!/bin/sh
# Compares the pages of the PDFs of the visual regression test with the
# committed references (docs/adr/0094-visual-regression-page-hashes-at-72-dpi.md).
#
#   check.sh PDFS            compares; PDFS holds <input>.pdf of build.sh
#   check.sh --accept PDFS   writes the references from PDFS instead
#
# Each input of build.sh --list is rendered by
# `shem render --dpi 72 --format ppm --jobs 1` in page-hashes.sh; the
# inputs are rendered side by side, VISUAL_JOBS at once (default: the
# number of online processors), each by a shem of its own (docs/adr/0098).
# The bytes of shem depend on neither. The SHA-256 of each page's PPM is compared with
# scripts/visual/pages/<input>.txt, whose lines are `<SHA-256>  page-<n>`
# in the order of the pages (LC_ALL=C). The match must be exact: there is
# no threshold. Every difference is a line on stdout, and the exit code is
# then 1:
#
#   changed <input> page-<n>     the SHA-256 of the page differs
#   added <input> page-<n>       a page the reference does not have
#   removed <input> page-<n>     a page of the reference is missing
#   unlisted <input>             the input has no reference
#   stale <input>                a reference has no input
#   unreadable <input>           shem failed; its line of stderr follows
#   missing <input>              PDFS has no <input>.pdf
#
# --accept writes the references and removes the stale ones. It writes
# nothing and fails when an input is missing, has no page or is unreadable,
# so that an empty reference is never written.
#
#   check.sh --lists DIR PDFS
#
# compares as check.sh PDFS does, and also writes to DIR the references
# that --accept would write, when it would write them; the visual job puts
# them in its report, without rendering the pages again (docs/adr/0096).
#
# SHEM is the path of shem; without it, third_party/shem/shem of
# fetch-shem.sh is used. Either must print `shem <the pinned version>` to
# --version (docs/adr/0093). The name of each input goes to stderr when its
# rendering starts, so that a stopped run shows where it stopped
# (docs/adr/0095).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
ACCEPT=false
LISTS=
case "${1-}" in
  --accept) ACCEPT=true; shift ;;
  --lists) [ $# -ge 2 ] || { echo "usage: check.sh [--accept | --lists DIR] PDFS" >&2; exit 2; }; LISTS=$2; shift 2 ;;
esac
[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: check.sh [--accept | --lists DIR] PDFS" >&2; exit 2; }
PDFS=$(cd "$1" && pwd)
PAGES=$HERE/pages
VERSION=$(sed -n 's/^VERSION=//p' "$HERE/fetch-shem.sh")
SHEM=${SHEM:-$ROOT/third_party/shem/shem}
if [ ! -x "$SHEM" ]; then
  echo "check: no shem at $SHEM; run scripts/visual/fetch-shem.sh, or give the path of a shem $VERSION in SHEM" >&2
  exit 1
fi
GOT=$("$SHEM" --version 2>/dev/null || true)
if [ "$GOT" != "shem $VERSION" ]; then
  echo "check: $SHEM --version printed '$GOT', not 'shem $VERSION'; references made with another version of shem may differ in pixels (docs/adr/0093)" >&2
  exit 1
fi
JOBS=${VISUAL_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}
case "$JOBS" in
  "" | 0 | *[!0-9]*) echo "check: VISUAL_JOBS must be a positive integer: '$JOBS'" >&2; exit 2 ;;
esac
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
mkdir -p "$WORK/new" "$WORK/err" "$WORK/ppm"
sh "$HERE/build.sh" --list >"$WORK/inputs"

# the pages of every input that is there, JOBS inputs at once, each by a
# shem of its own with --jobs 1; the largest PDF first, so that a large one
# does not start last. The order does not change the hashes, and the
# results are read below in the order of the inputs (docs/adr/0098)
while IFS= read -r input; do
  [ ! -f "$PDFS/$input.pdf" ] || printf '%s %s\n' "$(wc -c <"$PDFS/$input.pdf" | tr -d ' ')" "$input"
done <"$WORK/inputs" | LC_ALL=C sort -k 1,1nr -k 2,2 | cut -d ' ' -f 2 >"$WORK/order"
if [ -s "$WORK/order" ]; then
  xargs -n 1 -P "$JOBS" sh "$HERE/page-hashes.sh" "$SHEM" "$PDFS" "$WORK" <"$WORK/order"
fi

FAILED=false   # a difference, or an input that cannot be accepted
BLOCKED=false  # an input that --accept refuses
while IFS= read -r input; do
  if [ ! -f "$PDFS/$input.pdf" ]; then
    echo "missing $input"
    FAILED=true BLOCKED=true
    continue
  fi
  if [ ! -f "$WORK/new/$input.txt" ]; then
    echo "unreadable $input"
    [ ! -f "$WORK/err/$input" ] || head -n 1 "$WORK/err/$input"
    FAILED=true BLOCKED=true
    continue
  fi
  if [ ! -s "$WORK/new/$input.txt" ]; then
    echo "check: $input has no page" >&2
    BLOCKED=true
  fi
  [ "$ACCEPT" = false ] || continue
  if [ ! -f "$PAGES/$input.txt" ]; then
    echo "unlisted $input"
    FAILED=true
    continue
  fi
  awk -v input="$input" '
    NR == FNR { ref[$2] = $1; next }
    { seen[$2] = 1
      if (!($2 in ref)) print "added " input " " $2
      else if (ref[$2] != $1) print "changed " input " " $2 }
    END { for (p in ref) if (!(p in seen)) print "removed " input " " p }
  ' "$PAGES/$input.txt" "$WORK/new/$input.txt" | LC_ALL=C sort -k 3,3 >"$WORK/diff"
  if [ -s "$WORK/diff" ]; then
    cat "$WORK/diff"
    FAILED=true
  fi
done <"$WORK/inputs"

# the references that no input has
: >"$WORK/stale"
if [ -d "$PAGES" ]; then
  find "$PAGES" -type f -name '*.txt' | LC_ALL=C sort | while IFS= read -r f; do
    name=${f##*/}
    name=${name%.txt}
    grep -qxF "$name" "$WORK/inputs" || printf '%s\n' "$name"
  done >"$WORK/stale"
fi

if [ "$ACCEPT" = true ]; then
  if [ "$BLOCKED" = true ]; then
    echo "check: --accept wrote no reference: an input is missing, has no page or is unreadable" >&2
    exit 1
  fi
  mkdir -p "$PAGES"
  while IFS= read -r input; do
    cp "$WORK/new/$input.txt" "$PAGES/$input.txt"
  done <"$WORK/inputs"
  while IFS= read -r name; do
    rm -f "$PAGES/$name.txt"
  done <"$WORK/stale"
  exit 0
fi
while IFS= read -r name; do
  echo "stale $name"
  FAILED=true
done <"$WORK/stale"
# --lists: the references that --accept would write, into DIR, when it
# would write them (docs/adr/0096)
if [ -n "$LISTS" ] && [ "$BLOCKED" = false ]; then
  mkdir -p "$LISTS"
  while IFS= read -r input; do
    cp "$WORK/new/$input.txt" "$LISTS/$input.txt"
  done <"$WORK/inputs"
fi
[ "$FAILED" = false ]
