#!/bin/sh
# make-tables.sh REPO DEST: the tables of one-character cells of docs/adr/0290,
# made as make-fixtures.sh of the audit of 2026-11-09 makes them
set -eu
REPO=$1; DEST=$2
FIX=$REPO/modules/golem-driver/test/fixtures
table() { # NAME ROWS CELLS
  rm -rf "$DEST/$1"; cp -R "$FIX/kanikosen" "$DEST/$1"; rm -rf "$DEST/$1/build"; mkdir -p "$DEST/$1/data"
  awk -v n="$2" -v cols="$3" 'BEGIN{for(r=0;r<n;r++){for(k=0;k<cols;k++){printf "%s%s", (k?",":""), "x"}; printf "\n"}}' > "$DEST/$1/data/t.csv"
  printf '# 表\n\n@table data/t.csv\n\n本文。\n' > "$DEST/$1/kanikosen.gm"
}
mkdir -p "$DEST"
table c10-r1000 1000 10
table c10-r2000 2000 10
table c10-r4000 4000 10
table c10-r8000 8000 10
table c10-r10000 10000 10
table c8-r10000 10000 8
