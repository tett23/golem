#!/bin/sh
# The probe projects of the audit of 2026-11-08, made from the fixture
# kanikosen of golem-driver (its fonts, manifest and style) under DEST:
#
#   make-fixtures.sh REPO DEST
#
# proj         the fixture as it is (the baseline)
# proj-fig     a figure at an absolute path outside the root (DEST/outside)
# proj-link    [link] with URLs of other schemes and special characters
# proj-max     a table of 10,000 rows of 256 cells of one character (5 MB)
# proj-t2500   the same, 2,500 rows        proj-t5000   the same, 5,000 rows
# proj-c8      10,000 rows of 8 cells      proj-c64     10,000 rows of 64 cells
# proj-table   one row of 4,000,001 empty cells (G02088)
# proj-table2  2,000,000 rows of a,b (G02088)
# proj-notes   5,000 paragraphs of four notes each (20,000 notes)
# proj-figs    2,000 figures of one SVG
# proj-sym     style.toml as a symbolic link to DEST/outside
set -eu
REPO=$1; DEST=$2
FIX=$REPO/modules/golem-driver/test/fixtures
mkdir -p "$DEST/outside"
cp "$FIX/figures/images/chart.pdf" "$DEST/outside/secret.pdf"
new() { rm -rf "$DEST/$1"; cp -R "$FIX/kanikosen" "$DEST/$1"; rm -rf "$DEST/$1/build"; }
table() { # NAME ROWS CELLS
  new "$1"; mkdir -p "$DEST/$1/data"
  awk -v n="$2" -v cols="$3" 'BEGIN{for(r=0;r<n;r++){for(k=0;k<cols;k++){printf "%s%s", (k?",":""), "x"}; printf "\n"}}' > "$DEST/$1/data/t.csv"
  printf '# 表\n\n@table data/t.csv\n\n本文。\n' > "$DEST/$1/kanikosen.gm"
}
new proj
new proj-fig
printf '# 図\n\n@figure %s/outside/secret.pdf alt="外"\n\n本文。\n' "$DEST" > "$DEST/proj-fig/kanikosen.gm"
new proj-link
cat > "$DEST/proj-link/kanikosen.gm" <<'GM'
# リンク

[link "javascript:alert(1)": 一]

[link "https://example.invalid/a)b\\c(d": 二]

[link "https://example.invalid/x<script>": 三]

[link "https://example.invalid/%e3%81%82?q=\"": 四]

[link "HTTPS://EXAMPLE.INVALID/é": 五]

[link "https://example.invalid/あ": 六]

[link "data:text/html,x": 七]

[link "file:///etc/passwd": 八]
GM
table proj-max 10000 256
table proj-t2500 2500 256
table proj-t5000 5000 256
table proj-c8 10000 8
table proj-c64 10000 64
new proj-table; mkdir -p "$DEST/proj-table/data"
head -c 4000000 /dev/zero | tr '\0' ',' > "$DEST/proj-table/data/wide.csv"; echo >> "$DEST/proj-table/data/wide.csv"
printf '# 表\n\n@table data/wide.csv\n\n本文。\n' > "$DEST/proj-table/kanikosen.gm"
new proj-table2; mkdir -p "$DEST/proj-table2/data"
yes 'a,b' | head -n 2000000 > "$DEST/proj-table2/data/tall.csv"
printf '# 表\n\n@table data/tall.csv\n\n本文。\n' > "$DEST/proj-table2/kanikosen.gm"
new proj-notes
awk 'BEGIN{print "# 注\n"; for(i=0;i<5000;i++){printf "段落%d[note: 注%d]と[note: 注]と[note: 注]と[note: 注]。\n\n", i, i}}' > "$DEST/proj-notes/kanikosen.gm"
new proj-figs; mkdir -p "$DEST/proj-figs/images"
cp "$FIX/figures/images/diagram.svg" "$DEST/proj-figs/images/"
awk 'BEGIN{print "# 図\n"; for(i=0;i<2000;i++){printf "@figure images/diagram.svg alt=\"図%d\"\n\n本文%d。\n\n", i, i}}' > "$DEST/proj-figs/kanikosen.gm"
new proj-sym
mv "$DEST/proj-sym/style.toml" "$DEST/outside/style-linked.toml"
ln -s "$DEST/outside/style-linked.toml" "$DEST/proj-sym/style.toml"
