#!/bin/sh
# Golem ADR 0352: compare the Lean decidedSome witness with the Alloy model.
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

cp "$root/docs/golem-layout/models/pagination.als" "$tmp/decided-fixture.als"
cat >> "$tmp/decided-fixture.als" <<'EOF'
run decidedFixture {
  inDomain
  Col.cap = 3 and Col.used = 0
  #Recto = 1 and #Line = 1 and no Heading - Recto
  no Figure and no Blank and no Space and no Need
  all r: Recto | r.pos = 0
  all l: Line | l.pos = 1
  some p: Placement | p.brk = 2 and base[p] and orphanH[p] and widowH[p] and keepHeadingR[p] and lineAfterHeadings[p] and recto[p]
} for 5 but 5 Int, 14 Placement
EOF

JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$tmp" "${ALLOY:-alloy6}" exec -q -n -t text \
  -c decidedFixture -o - "$tmp/decided-fixture.als" > "$tmp/result"
grep -q '^---Trace---' "$tmp/result"
echo 'decidedFixture found'
