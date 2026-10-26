#!/bin/sh
# Compares the pages of the PDFs of the visual regression test with the
# committed references (docs/adr/0094-visual-regression-page-hashes-at-72-dpi.md).
#
#   check.sh PDFS            compares; PDFS holds <input>.pdf of build.sh
#   check.sh --accept PDFS   writes the references from PDFS instead
#
# Each input of build.sh --list is rendered, one PDF after another, by
# `shem render --dpi 72 --format ppm`; shem renders the pages of a PDF in
# parallel on every core by itself, and its bytes do not depend on that.
# The SHA-256 of each page's PPM is compared with
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
# SHEM is the path of shem; without it, third_party/shem/shem of
# fetch-shem.sh is used. Either must print `shem <the pinned version>` to
# --version (docs/adr/0093). The name of each input goes to stderr as it is
# rendered, so that a stopped run shows where it stopped (docs/adr/0095).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
ACCEPT=false
if [ "${1-}" = --accept ]; then ACCEPT=true; shift; fi
[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: check.sh [--accept] PDFS" >&2; exit 2; }
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
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
mkdir -p "$WORK/new"
sh "$HERE/build.sh" --list >"$WORK/inputs"

FAILED=false   # a difference, or an input that cannot be accepted
BLOCKED=false  # an input that --accept refuses
while IFS= read -r input; do
  echo "check: rendering $input" >&2
  if [ ! -f "$PDFS/$input.pdf" ]; then
    echo "missing $input"
    FAILED=true BLOCKED=true
    continue
  fi
  rm -rf "$WORK/ppm"
  if ! "$SHEM" render --dpi 72 --format ppm "$PDFS/$input.pdf" "$WORK/ppm" >/dev/null 2>"$WORK/err"; then
    echo "unreadable $input"
    head -n 1 "$WORK/err"
    FAILED=true BLOCKED=true
    continue
  fi
  # the SHA-256 of every page, by the name of the page, in the order of
  # the pages; the PPMs are removed at once
  : >"$WORK/new/$input.txt"
  : >"$WORK/files"
  [ ! -d "$WORK/ppm" ] || find "$WORK/ppm" -type f -name 'page-*.ppm' >"$WORK/files"
  if [ -s "$WORK/files" ]; then
    # mktemp gives a path without spaces, which xargs would split
    xargs $SHA <"$WORK/files" |
      sed 's#^\([0-9a-f]*\) [ *]*.*/\(page-[0-9]*\)\.ppm$#\1  \2#' | LC_ALL=C sort -k 2,2 >"$WORK/new/$input.txt"
  fi
  rm -rf "$WORK/ppm"
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
[ "$FAILED" = false ]
