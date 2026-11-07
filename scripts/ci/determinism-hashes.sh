#!/bin/sh
# Compares the list of scripts/determinism.sh with the committed list, to
# see a change of the outputs across commits (docs/adr/0173).
#
#   determinism-hashes.sh LIST HASHES
#
# LIST is the output of scripts/determinism.sh, with or without the
# manuals; the lines of the manuals (manual/ and manual-dev/) are left out,
# as their colophons have the commit. HASHES is the committed list,
# scripts/determinism/hashes.txt, made with --no-manuals.
#
# Exit code 0: the two are the same, line for line.
# Exit code 1: they differ. Each line only in HASHES is written to stdout
# as `hashes.txt: <line>`, each line only in LIST as `outputs: <line>`; a
# change of the order alone is one line, `order: the lines are in another
# order`.
# Exit code 2: a file cannot be read.
set -eu

cannot() {
  printf 'determinism-hashes: %s\n' "$*" >&2
  exit 2
}

[ $# -eq 2 ] || cannot "usage: determinism-hashes.sh LIST HASHES"
[ -f "$1" ] || cannot "no such file: $1"
[ -f "$2" ] || cannot "no such file: $2"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

grep -vE '^[^ ]+ +manual(-dev)?/' "$1" >"$WORK/outputs" || true
cp "$2" "$WORK/hashes"
cmp -s "$WORK/outputs" "$WORK/hashes" && exit 0

LC_ALL=C sort "$WORK/outputs" >"$WORK/outputs.sorted"
LC_ALL=C sort "$WORK/hashes" >"$WORK/hashes.sorted"
LC_ALL=C comm -13 "$WORK/outputs.sorted" "$WORK/hashes.sorted" | sed 's/^/hashes.txt: /' >"$WORK/diff"
LC_ALL=C comm -23 "$WORK/outputs.sorted" "$WORK/hashes.sorted" | sed 's/^/outputs: /' >>"$WORK/diff"
if [ -s "$WORK/diff" ]; then
  cat "$WORK/diff"
else
  printf 'order: the lines are in another order\n'
fi
exit 1
