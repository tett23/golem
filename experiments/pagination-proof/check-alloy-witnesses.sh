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

run needMoreSomeFixture {
  Col.cap = 4 and Col.used = 1
  no Heading and no Figure and no Blank
  #Line = 1 and #Para = 1 and #Need = 2 and #Space = 1
  no Kept and no AllLines
  some disj n, m: Need | n.pos = 0 and n.lines = 1 and
    m.pos = 2 and m.lines = 3
  all sp: Space | sp.pos = 1
  all l: Line | l.pos = 3
  some p: Placement | p.brk = 2 and base27[p] and needMet[p] and
    spaceKeeps35[p]
} for 5 but 5 Int, exactly 3 Placement, exactly 4 Item

run needSpaceSomeFixture {
  Col.cap = 3 and Col.used = 1
  no Heading and no Figure and no Blank
  #Line = 1 and #Para = 1 and #Need = 1 and #Space = 1
  no Kept and no AllLines
  all n: Need | n.pos = 0 and n.lines = 2
  all sp: Space | sp.pos = 1
  all l: Line | l.pos = 2
  some p: Placement | p.brk = 2 and base27[p] and needMet[p] and
    spaceKeeps[p]
} for 5 but 5 Int, exactly 3 Placement, exactly 3 Item

run relaxedHeadingFixture {
  inDomain and no Recto
  Col.cap = 3 and Col.used = 0
  #Heading = 1 and #Line = 3 and #Para = 1
  no Figure and no Blank and no Space and no Need
  all h: Heading | h.pos = 0
  all l: Line | l.pos >= 1 and l.pos <= 3
  some p: Placement | p.brk = 2 and base[p] and orphanH[p] and
    widowH[p] and keepHeading21[p] and lineAfterHeadings[p]
} for 5 but 5 Int, exactly 5 Placement, exactly 4 Item

run headingFigureFitsFixture {
  inDomain and no Recto
  Col.cap = 3 and Col.used = 0
  #Heading = 1 and #Line = 1 and #Para = 1 and #Figure = 1
  no Blank and no Space and no Need
  all h: Heading | h.pos = 0
  all f: Figure | f.pos = 1 and f.size = 2
  all l: Line | l.pos = 2
  some p: Placement | p.brk = 1 and p.kept = Figure and
    base[p] and orphanH[p] and widowH[p] and
    keepHeading21[p] and lineAfterHeadings[p]
} for 5 but 5 Int, exactly 6 Placement, exactly 3 Item

run headingFigureWaitsFixture {
  inDomain and no Recto
  Col.cap = 3 and Col.used = 0
  #Heading = 1 and #Line = 1 and #Para = 1 and #Figure = 1
  no Blank and no Space and no Need
  all h: Heading | h.pos = 0
  all f: Figure | f.pos = 1 and f.size = 3
  all l: Line | l.pos = 2
  some p: Placement | p.brk = 2 and no p.kept and
    base[p] and orphanH[p] and widowH[p] and
    keepHeading21[p] and lineAfterHeadings[p]
} for 5 but 5 Int, exactly 6 Placement, exactly 3 Item

run rectoRunDifferenceFixture {
  inDomain
  Col.cap = 3 and Col.used = 0
  #Heading = 3 and #Recto = 1
  no Line and no Figure and no Blank and no Space and no Need
  all h: Heading - Recto | h.pos = 0 or h.pos = 1
  all r: Recto | r.pos = 2
  some p: Placement | p.brk = 2 and base[p] and
    keepHeadingR[p] and recto[p] and lineAfterHeadings[p] and
    not keepHeading21[p]
} for 5 but 5 Int, exactly 4 Placement, exactly 3 Item

run headingRunFixture {
  inDomain and no Recto
  Col.cap = 3 and Col.used = 0
  #Heading = 2 and #Line = 1 and #Para = 1
  no Figure and no Blank and no Space and no Need
  all h: Heading | h.pos = 0 or h.pos = 1
  all l: Line | l.pos = 2
  some p: Placement | p.brk = 1 and base[p] and
    orphanH[p] and widowH[p] and keepHeading21[p] and
    lineAfterHeadings[p]
} for 5 but 5 Int, exactly 4 Placement, exactly 3 Item

run headingBlankFigureParagraphFixture {
  inDomain26 and no Recto
  Col.cap = 3 and Col.used = 0
  #Heading = 1 and #Line = 2 and #Para = 1 and
    #Figure = 1 and #Blank = 1
  no Space and no Need
  all h: Heading | h.pos = 0
  all l: Line | l.pos = 1 or l.pos = 2
  all b: Blank | b.pos = 3
  all f: Figure | f.pos = 4 and f.size = 1
  some p: Placement | p.brk = 2 and no p.kept and
    no p.placed and base26[p] and blankWithNext[p] and
    orphanH[p] and widowH[p] and keepHeading21[p] and
    lineAfterHeadings[p]
} for 6 but 5 Int, exactly 16 Placement, exactly 5 Item
run needHeadingConflictFixture {
  inDomain27
  Col.cap = 4 and Col.used = 2
  no Figure and no Blank and no Space and no Line
  one n: Need | n.pos = 0
  some h: Heading - Recto | h.pos = 1
  some r, s: Recto | r.pos = 2 and s.pos = 3
  no p: Placement | base27[p] and needMet[p] and spaceKeeps[p] and orphan[p] and widow[p] and keepHeading21[p]
} for 4 but 5 Int, exactly 4 Item, exactly 4 Placement
run needAcrossWaitingFigureFixture {
  inDomain27
  Col.cap = 4 and Col.used = 0
  no Blank and no Space and no Heading
  some disj q, r: Para |
    (all l: Line | l.para = q iff l.pos in 0 + 1) and
    (all l: Line | l.para = r iff l.pos = 5)
  some disj f, g: Figure, n: Need, l: Line |
    f.pos = 2 and f.size = 3 and n.pos = 3 and n.lines = 2 and
    g.pos = 4 and g.size = 1 and l.pos = 5 and
    (some p: Placement | p.brk = 3 and no p.kept and
      g in waitingIn[p] and l in needNext[p, n] and
      base27[p] and needMet[p] and spaceKeeps[p])
} for 6 but 5 Int, exactly 3 Line, exactly 2 Para, exactly 6 Item, exactly 16 Placement
EOF

for command in decidedFixture keepAllFixture needMore27Fixture \
    needMoreSomeFixture needSpaceSomeFixture relaxedHeadingFixture \
    headingFigureFitsFixture headingFigureWaitsFixture \
    rectoRunDifferenceFixture headingRunFixture \
    headingBlankFigureParagraphFixture needHeadingConflictFixture \
    needAcrossWaitingFigureFixture; do
  JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$tmp" "${ALLOY:-alloy6}" exec -q -n -t text \
    -c "$command" -o - "$tmp/witnesses.als" > "$tmp/result"
  if ! grep -q '^---Trace---' "$tmp/result"; then
    cat "$tmp/result" >&2
    exit 1
  fi
  echo "$command found"
done
