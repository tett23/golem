#!/bin/sh
# Golem ADR 0352: compare Lean witnesses with the Alloy model.
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

cp "$root/docs/golem-layout/models/pagination.als" "$tmp/witnesses.als"
cat >> "$tmp/witnesses.als" <<'EOF'
run decidedFixture {
  inDomain
  Col.cap = 3 and Col.used = 0
  #Recto = 1 and #Line = 1 and no Heading - Recto
  no Figure and no Blank and no Space and no Need
  all r: Recto | r.pos = 0
  all l: Line | l.pos = 1
  some p: Placement | p.brk = 2 and base[p] and orphanH[p] and widowH[p] and keepHeadingR[p] and lineAfterHeadings[p] and recto[p]
} for 5 but 5 Int, 14 Placement

run keepAllFixture {
  inDomain
  Col.cap = 3 and Col.used = 1
  #Para = 1 and #AllLines = 1 and #Line = 1
  no Heading and no Figure and no Blank and no Space and no Need
  all l: Line | l.pos = 0
  some p: Placement | p.brk = 0 and base[p] and keepFirst[p] and keepLast[p] and keepAll[p]
} for 5 but 5 Int, 14 Placement

run needMore27Fixture {
  Col.cap = 3 and Col.used = 1
  no Heading and no Figure and no Blank
  #Line = 1 and #Para = 1 and #Need = 2 and #Space = 1
  no Kept and no AllLines
  some disj n, m: Need | n.pos = 0 and n.lines = 1 and
    m.pos = 2 and m.lines = 3
  all sp: Space | sp.pos = 1
  all l: Line | l.pos = 3
  no p: Placement | base27[p] and needMet[p] and spaceKeepsFirst[p]
} for 5 but 5 Int, exactly 3 Placement, exactly 4 Item
EOF

for command in decidedFixture keepAllFixture needMore27Fixture; do
  JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$tmp" "${ALLOY:-alloy6}" exec -q -n -t text \
    -c "$command" -o - "$tmp/witnesses.als" > "$tmp/result"
  grep -q '^---Trace---' "$tmp/result"
  echo "$command found"
done
