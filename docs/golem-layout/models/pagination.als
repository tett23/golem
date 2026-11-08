-- The rules of pagination at the boundary of one column and the next
-- (docs/adr/0204, section 5). The rules are predicates, not facts: the
-- commands look for inputs on which no placement meets a set of rules.
--
-- An input is a column of `cap` grid lines with `used` of them already
-- taken (0: an empty column), and items in the order of the flow: the
-- lines of paragraphs, headings of one grid line, at most two figures
-- and at most one blank line of one grid line (golem-layout ADR 0026).
-- A placement puts the text before `brk` in the column and the rest in
-- the next column, puts each figure in the column or sends it to the
-- next one, and places the blank line in the column or not. Every
-- placement of an input exists as an atom (fact allPlacements), so "no
-- placement meets the rules" is first order. The commands of
-- docs/adr/0204 and docs/adr/0206 look at inputs of at most one figure
-- and no blank line (pred inDomain).
module pagination

open util/integer

one sig Col {
  cap: one Int,
  used: one Int
}

sig Para {}

abstract sig Item {
  pos: one Int
}

abstract sig Text extends Item {}

sig Line extends Text {
  para: one Para
}

sig Heading extends Text {}

-- a heading at a recto (docs/adr/0206)
sig Recto extends Heading {}

sig Figure extends Item {
  size: one Int
}

-- a blank line of one grid line, @blank-line (docs/adr/0046)
sig Blank extends Item {}

-- a space of one grid line between blocks, placed as text is (golem-layout ADR 0027)
sig Space extends Text {}

-- @need-lines of `lines` grid lines (docs/adr/0030); two of them for golem-layout ADR 0035
sig Need extends Item {
  lines: one Int
}

sig Placement {
  brk: one Int,
  kept: set Figure,
  placed: set Blank
}

-- the input

fact input {
  Col.cap >= 3 and Col.cap <= 6
  Col.used >= 0 and Col.used <= Col.cap
  #Figure <= 2
  lone Blank
  lone Space
  #Need <= 2
  all n: Need | n.lines >= 1 and n.lines <= plus[Col.cap, 1]
  all f: Figure | f.size >= 1 and f.size <= plus[Col.cap, 1]
  -- the items take the places 0 .. #Item - 1, one each
  all i: Item | i.pos >= 0 and i.pos < #Item
  all disj i, j: Item | i.pos != j.pos
  -- the lines of a paragraph are together, nothing between them
  all l, m: Line | l.para = m.para implies
    (all i: Item | (i.pos > min[l.pos + m.pos] and i.pos < max[l.pos + m.pos]) implies (i in Line and i.para = l.para))
  all p: Para | some para.p
}

fact allPlacements {
  -- the figures kept are none, one, or both; the blank line placed or not
  all b: Int | (b >= 0 and b <= #Text) implies {
    some p: Placement | p.brk = b and no p.kept and no p.placed
    all f: Figure | some p: Placement | p.brk = b and p.kept = f and no p.placed
    some p: Placement | p.brk = b and p.kept = Figure and no p.placed
    some p: Placement | p.brk = b and no p.kept and p.placed = Blank
    all f: Figure | some p: Placement | p.brk = b and p.kept = f and p.placed = Blank
    some p: Placement | p.brk = b and p.kept = Figure and p.placed = Blank
  }
  all p: Placement | p.brk >= 0 and p.brk <= #Text
  all disj p, q: Placement | p.brk != q.brk or p.kept != q.kept or p.placed != q.placed
}

-- the place of the text: its index among the text items
fun tpos[t: Text]: Int { #{u: Text | u.pos < t.pos} }

pred here[p: Placement, t: Text] { tpos[t] < p.brk }

fun load[p: Placement]: Int {
  plus[plus[plus[Col.used, #{t: Text | here[p, t]}], (sum f: p.kept | f.size)], #p.placed]
}

-- a placement fits the column
pred fits[p: Placement] { load[p] <= Col.cap }

fun first[q: Para]: Line { {l: para.q | no m: para.q | m.pos < l.pos} }
fun second[q: Para]: Line { {l: para.q | #{m: para.q | m.pos < l.pos} = 1} }
fun last[q: Para]: Line { {l: para.q | no m: para.q | m.pos > l.pos} }
fun beforeLast[q: Para]: Line { {l: para.q | #{m: para.q | m.pos > l.pos} = 1} }

-- nothing is before the item in the column: the column is empty and no text or kept figure precedes it
pred startsColumn[p: Placement, i: Item] {
  Col.used = 0
  no t: Text | t.pos < i.pos and here[p, t]
  no p.kept or p.kept.pos > i.pos
}

-- the rules

-- the column is filled from the start: the text stops where the next text does not fit
pred greedy[p: Placement] {
  p.brk = #Text or plus[load[p], 1] > Col.cap
}

-- I3: a kept figure follows every text before it; text goes in order (by brk)
pred order[p: Placement] {
  all f: p.kept | all t: Text | t.pos < f.pos implies here[p, t]
}

-- a figure is placed where it is when it fits there, else sent to the next column
pred figure[p: Placement] {
  all f: Figure |
    (f in p.kept) iff (
      (all t: Text | t.pos < f.pos implies here[p, t])
      and plus[plus[Col.used, #{t: Text | t.pos < f.pos}], f.size] <= Col.cap)
}

-- I4: the first line of a paragraph of two lines or more is not alone at the end, but in an empty column
pred orphan[p: Placement] {
  all q: Para | #para.q >= 2 and here[p, first[q]] and not here[p, second[q]]
    implies startsColumn[p, first[q]]
}

-- I5: the last line is not alone in the next column, but after a column the paragraph starts empty
pred widow[p: Placement] {
  all q: Para | #para.q >= 2 and here[p, beforeLast[q]] and not here[p, last[q]]
    implies startsColumn[p, first[q]]
}

-- I6: a heading not first in the column keeps the headings after it and the first two lines of the paragraph after them
pred keepHeading[p: Placement] {
  all h: Heading | (here[p, h] and not startsColumn[p, h]) implies {
    all t: Text | (t.pos > h.pos and (all i: Item | (i.pos > h.pos and i.pos < t.pos) implies i in Heading)) implies {
      t in Heading implies here[p, t]
      t in Line implies (here[p, first[t.para]] and (some second[t.para] implies here[p, second[t.para]]))
    }
  }
}

-- nothing is sent on from an empty column: the first item stays (a blank line and a need-lines place nothing of their own)
pred noSendFromEmpty[p: Placement] {
  Col.used = 0 implies all i: Item - Blank - Need | (no j: Item - Blank - Need | j.pos < i.pos) implies (i in Text implies p.brk >= 1 else i in p.kept)
}

pred all7[p: Placement] {
  fits[p] and greedy[p] and order[p] and figure[p] and orphan[p] and widow[p] and keepHeading[p] and noSendFromEmpty[p]
}

-- a figure always fits an empty column (it is shrunk, 「図版」 in docs/specifications.md)
pred figuresFit { all f: Figure | f.size <= Col.cap }

-- the inputs the commands of docs/adr/0204 and docs/adr/0206 allow: at most one figure, no blank line
pred inDomain { figuresFit and lone Figure and no Blank and no Space and no Need }

-- the commands

-- the model is not empty: with no rule but fitting, a placement exists
run someFits { some p: Placement | fits[p] } for 5 but 5 Int, 14 Placement

-- the model is not all false: every rule together fails on some input
run noneMeetsAll { inDomain and (no p: Placement | all7[p]) } for 5 but 5 Int, 14 Placement

-- every rule but the greedy fill together: the fill gives way to the others
run noneMeetsAllButGreedy {
  inDomain
  no p: Placement | fits[p] and order[p] and figure[p] and orphan[p] and widow[p] and keepHeading[p] and noSendFromEmpty[p]
} for 5 but 5 Int, 14 Placement

-- the pairs: an input where some placement meets each rule, and none meets both
run greedyOrphan { inDomain and ((some p: Placement | fits[p] and greedy[p]) and (some p: Placement | fits[p] and orphan[p]) and no p: Placement | fits[p] and greedy[p] and orphan[p]) } for 5 but 5 Int, 14 Placement
run greedyWidow { inDomain and ((some p: Placement | fits[p] and greedy[p]) and (some p: Placement | fits[p] and widow[p]) and no p: Placement | fits[p] and greedy[p] and widow[p]) } for 5 but 5 Int, 14 Placement
run greedyKeepHeading { inDomain and ((some p: Placement | fits[p] and greedy[p]) and (some p: Placement | fits[p] and keepHeading[p]) and no p: Placement | fits[p] and greedy[p] and keepHeading[p]) } for 5 but 5 Int, 14 Placement
run greedyFigure { inDomain and ((some p: Placement | fits[p] and greedy[p]) and (some p: Placement | fits[p] and figure[p]) and no p: Placement | fits[p] and greedy[p] and figure[p]) } for 5 but 5 Int, 14 Placement
run orphanEmpty { inDomain and ((some p: Placement | fits[p] and orphan[p]) and (some p: Placement | fits[p] and noSendFromEmpty[p]) and no p: Placement | fits[p] and orphan[p] and noSendFromEmpty[p]) } for 5 but 5 Int, 14 Placement
run widowEmpty { inDomain and ((some p: Placement | fits[p] and widow[p]) and (some p: Placement | fits[p] and noSendFromEmpty[p]) and no p: Placement | fits[p] and widow[p] and noSendFromEmpty[p]) } for 5 but 5 Int, 14 Placement
run keepHeadingEmpty { inDomain and ((some p: Placement | fits[p] and keepHeading[p]) and (some p: Placement | fits[p] and noSendFromEmpty[p]) and no p: Placement | fits[p] and keepHeading[p] and noSendFromEmpty[p]) } for 5 but 5 Int, 14 Placement
run orphanWidow { inDomain and ((some p: Placement | fits[p] and orphan[p]) and (some p: Placement | fits[p] and widow[p]) and no p: Placement | fits[p] and orphan[p] and widow[p]) } for 5 but 5 Int, 14 Placement
run keepHeadingOrphan { inDomain and ((some p: Placement | fits[p] and keepHeading[p]) and (some p: Placement | fits[p] and orphan[p]) and no p: Placement | fits[p] and keepHeading[p] and orphan[p]) } for 5 but 5 Int, 14 Placement
run keepHeadingWidow { inDomain and ((some p: Placement | fits[p] and keepHeading[p]) and (some p: Placement | fits[p] and widow[p]) and no p: Placement | fits[p] and keepHeading[p] and widow[p]) } for 5 but 5 Int, 14 Placement
run keepHeadingFigure { inDomain and ((some p: Placement | fits[p] and keepHeading[p]) and (some p: Placement | fits[p] and figure[p]) and no p: Placement | fits[p] and keepHeading[p] and figure[p]) } for 5 but 5 Int, 14 Placement
run figureOrder { inDomain and ((some p: Placement | fits[p] and figure[p]) and (some p: Placement | fits[p] and order[p]) and no p: Placement | fits[p] and figure[p] and order[p]) } for 5 but 5 Int, 14 Placement
run figureEmpty { inDomain and ((some p: Placement | fits[p] and figure[p]) and (some p: Placement | fits[p] and noSendFromEmpty[p]) and no p: Placement | fits[p] and figure[p] and noSendFromEmpty[p]) } for 5 but 5 Int, 14 Placement

-- a figure taller than the column, outside the inputs the specification allows
run tallFigure { lone Figure and no Blank and no Space and no Need and not figuresFit and (no p: Placement | fits[p] and figure[p] and noSendFromEmpty[p]) } for 5 but 5 Int, 14 Placement

-- the decisions of docs/adr/0206

-- nothing but headings is before the item in the column, from its top
pred afterHeadingsOnly[p: Placement, i: Item] {
  Col.used = 0
  all t: Text | (t.pos < i.pos and here[p, t]) implies t in Heading
  no p.kept or p.kept.pos > i.pos
}

-- 「段の先頭から見出しだけを置いた段では、見出しの後の行を一行は置き」
pred lineAfterHeadings[p: Placement] {
  (Col.used = 0 and p.brk >= 1 and no p.kept and (all t: Text | here[p, t] implies t in Heading))
    implies (no l: Line | tpos[l] = p.brk)
}

-- I4 and I5 with the column of nothing but headings counted as empty (decision 2)
pred orphanH[p: Placement] {
  all q: Para | #para.q >= 2 and here[p, first[q]] and not here[p, second[q]]
    implies afterHeadingsOnly[p, first[q]]
}
pred widowH[p: Placement] {
  all q: Para | #para.q >= 2 and here[p, beforeLast[q]] and not here[p, last[q]]
    implies afterHeadingsOnly[p, first[q]]
}

-- the lines a heading keeps: all of a paragraph of three lines or fewer, else two (golem-layout ADR 0021)
pred keptLines[p: Placement, q: Para] {
  #para.q <= 3 implies (all l: para.q | here[p, l]) else (here[p, first[q]] and here[p, second[q]])
}

-- I6 as the specification says it after golem-layout ADR 0021, a recto heading counted as any heading
pred keepHeading21[p: Placement] {
  all h: Heading | (here[p, h] and not startsColumn[p, h]) implies {
    all t: Text | (t.pos > h.pos and (all i: Item | (i.pos > h.pos and i.pos < t.pos) implies i in Heading)) implies {
      t in Heading implies here[p, t]
      t in Line implies keptLines[p, t.para]
    }
  }
}

-- I6 whose run of headings ends before a recto heading (decision 4)
pred keepHeadingR[p: Placement] {
  all h: Heading - Recto | (here[p, h] and not startsColumn[p, h]) implies {
    all t: Text | (t.pos > h.pos and (all i: Item | (i.pos > h.pos and i.pos < t.pos) implies i in Heading - Recto)) implies {
      t in Heading - Recto implies here[p, t]
      t in Line implies keptLines[p, t.para]
    }
  }
}

-- I8 at one boundary: a recto heading starts a column with nothing before it
pred recto[p: Placement] {
  all r: Recto | here[p, r] implies startsColumn[p, r]
}

pred base[p: Placement] { fits[p] and order[p] and figure[p] and noSendFromEmpty[p] }

-- decision 2: the line after headings with the strict orphan and widow rules has no placement on some input
run strictAfterHeadings { inDomain and no Recto and (no p: Placement | base[p] and orphan[p] and widow[p] and keepHeading21[p] and lineAfterHeadings[p]) } for 5 but 5 Int, 14 Placement
-- and with the column of nothing but headings counted as empty, every input has one
run relaxedAfterHeadings { inDomain and no Recto and (no p: Placement | base[p] and orphanH[p] and widowH[p] and keepHeading21[p] and lineAfterHeadings[p]) } for 5 but 5 Int, 14 Placement
-- decision 4: a heading kept with the recto heading after it cannot meet I8
run rectoKept { inDomain and (no p: Placement | base[p] and orphanH[p] and widowH[p] and keepHeading21[p] and lineAfterHeadings[p] and recto[p]) } for 5 but 5 Int, 14 Placement
run rectoEnds { inDomain and (no p: Placement | base[p] and orphanH[p] and widowH[p] and keepHeadingR[p] and lineAfterHeadings[p] and recto[p]) } for 5 but 5 Int, 14 Placement
-- decision 5: I6 with the whole of a three-line paragraph, every rule but the greedy fill
run keep21 { inDomain and no Recto and (no p: Placement | base[p] and orphan[p] and widow[p] and keepHeading21[p]) } for 5 but 5 Int, 14 Placement
-- the model is not empty with the decisions
run decidedSome { inDomain and some Recto and some Line and (some p: Placement | base[p] and orphanH[p] and widowH[p] and keepHeadingR[p] and lineAfterHeadings[p] and recto[p]) } for 5 but 5 Int, 14 Placement

-- golem-layout ADR 0026: figures that wait, and the blank line before them

-- the inputs of the commands of golem-layout ADR 0026: two figures or a blank line may be there
pred inDomain26 { figuresFit and no Space and no Need }

-- the figures sent on after a figure sent on: they wait (golem-layout ADR 0015)
fun waitingIn[p: Placement]: set Figure {
  {f: Figure - p.kept | some g: Figure - p.kept | g.pos < f.pos}
}

-- the next block of a blank line: the first item after it that is not a figure that waits
fun nextOf[p: Placement, b: Blank]: set Item {
  {i: Item - Blank - Need - waitingIn[p] | i.pos > b.pos and
    no j: Item - Blank - Need - waitingIn[p] | j.pos > b.pos and j.pos < i.pos}
}

-- the next block of a blank line before golem-layout ADR 0026: the first item after it
fun nextOf25[b: Blank]: set Item {
  {i: Item - Blank | i.pos > b.pos and no j: Item - Blank | j.pos > b.pos and j.pos < i.pos}
}

-- whether an item is in this column
pred inColumn[p: Placement, i: Item] { (i in Text and here[p, i]) or i in p.kept }

-- nothing is before the blank line in the column: there it is dropped
pred blankAtTop[p: Placement, b: Blank] {
  Col.used = 0
  no t: Text | t.pos < b.pos and here[p, t]
  no g: p.kept | g.pos < b.pos
}

-- a figure is placed where it is when it fits there after the text, the
-- figures and the blank line before it, and no figure before it is sent
-- on; else it is sent to the next column (golem-layout ADR 0015). The
-- blank line before it counts unless it is at the top of the column: a
-- blank line goes with its next block, and the two fit together or go on
-- together (docs/adr/0046)
pred figures[p: Placement] {
  all f: Figure |
    (f in p.kept) iff (
      (all t: Text | t.pos < f.pos implies here[p, t])
      and (all g: Figure | g.pos < f.pos implies g in p.kept)
      and plus[plus[plus[plus[Col.used, #{t: Text | t.pos < f.pos}], (sum g: {g: Figure | g.pos < f.pos} | g.size)], #{b: Blank | b.pos < f.pos and not blankAtTop[p, b]}], f.size] <= Col.cap)
}

-- I3 for two figures: a figure kept follows every figure before it
pred figureOrder[p: Placement] {
  all f: p.kept | all g: Figure | g.pos < f.pos implies g in p.kept
}

-- the blank line is in the column of its next block, not at its top; with no next block it is placed nowhere (P4', P5)
pred blankWithNext[p: Placement] {
  all b: Blank | (b in p.placed) iff (some nextOf[p, b] and inColumn[p, nextOf[p, b]] and not blankAtTop[p, b])
}

-- the same before golem-layout ADR 0026: the next block may be a figure that waits
pred blankWithNext25[p: Placement] {
  all b: Blank | (b in p.placed) iff (some nextOf25[b] and inColumn[p, nextOf25[b]] and not blankAtTop[p, b])
}

pred base26[p: Placement] { fits[p] and order[p] and figures[p] and figureOrder[p] and noSendFromEmpty[p] }

-- the shape of golem-layout ADR 0026 is an input: a figure sent on, a blank line, a figure that waits, and text after them
run waitingBlankSome {
  inDomain26
  some p: Placement, b: Blank, f: Figure, t: Text |
    base26[p] and blankWithNext[p] and f in waitingIn[p] and b.pos < f.pos and f.pos < t.pos and here[p, t] and b in p.placed
} for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- the rules of the figures and of the blank line together: no input has no placement
run waitingBlankNone { inDomain26 and (no p: Placement | base26[p] and blankWithNext[p]) } for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- with the rules of the lines and the headings but the greedy fill
run waitingBlankAllButGreedy {
  inDomain26
  no p: Placement | base26[p] and blankWithNext[p] and orphan[p] and widow[p] and keepHeading21[p]
} for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- the pair: the blank line with its next block, and the figures in order
run blankFigureOrder {
  inDomain26
  (some p: Placement | fits[p] and blankWithNext[p])
  (some p: Placement | fits[p] and figures[p] and figureOrder[p])
  no p: Placement | fits[p] and blankWithNext[p] and figures[p] and figureOrder[p]
} for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- before golem-layout ADR 0026: an input where the blank line goes with the figure that waits, and the text after it is in the column without it
run blankBeforeWaiting25 {
  inDomain26
  some p: Placement, b: Blank, f: Figure, t: Text |
    base26[p] and blankWithNext25[p] and f in waitingIn[p] and nextOf25[b] = f and f.pos < t.pos and here[p, t] and b not in p.placed
} for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- and the rules of golem-layout ADR 0026 and before it give placements on the same inputs
run blankRules25 { inDomain26 and (no p: Placement | base26[p] and blankWithNext25[p]) } for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- golem-layout ADR 0027: need-lines and the spaces after it

-- the inputs of the commands of golem-layout ADR 0027: a need-lines, a space, a blank line and two figures may be there
pred inDomain27 { figuresFit and lone Need and (all n: Need | n.lines = 2) }

-- the next block of a need-lines: the first item after it that is not a space, a blank line or a figure that waits
fun needNext[p: Placement, n: Need]: set Item {
  {i: Item - Space - Blank - Need - waitingIn[p] | i.pos > n.pos and
    no j: Item - Space - Blank - Need - waitingIn[p] | j.pos > n.pos and j.pos < i.pos}
}

-- the grid lines placed in the column before an item, the spaces and the blank lines not counted
fun placedBefore[p: Placement, i: Item]: Int {
  plus[plus[Col.used, #{t: Text - Space | t.pos < i.pos and here[p, t]}], (sum g: {g: p.kept | g.pos < i.pos} | g.size)]
}

-- the grid lines in the column before an item, the spaces counted, and the blank lines before it not at the top of the column:
-- a blank line goes with its next block, and the two fit together or go on together (docs/adr/0046)
fun loadBefore[p: Placement, i: Item]: Int {
  plus[plus[plus[Col.used, #{t: Text | t.pos < i.pos and here[p, t]}], (sum g: {g: p.kept | g.pos < i.pos} | g.size)], #{b: Blank | b.pos < i.pos and not blankAtTop[p, b]}]
}

-- the first part of a block: of a paragraph, all of three lines or fewer, else two (golem-layout ADR 0021); a heading's line; a figure
fun firstPart[i: Item]: Int {
  i in Line implies (#para.(i.para) <= 3 implies #para.(i.para) else 2)
  else (i in Figure implies i.size else 1)
}

-- nothing but spaces is before the item in the column, and the column was empty
pred firstInColumn[p: Placement, i: Item] {
  Col.used = 0
  no t: Text - Space | t.pos < i.pos and here[p, t]
  no g: p.kept | g.pos < i.pos
}

-- P1: the next block of a need-lines, placed in this column but not first in it, has its lines or more before it, the spaces and the blank lines not counted
pred needMet[p: Placement] {
  all n: Need | all b: needNext[p, n] |
    (inColumn[p, b] and not firstInColumn[p, b]) implies minus[Col.cap, placedBefore[p, b]] >= n.lines
}

-- P7: when need-lines is met where it is written and the first part of its next block fits after the spaces, the block is in this column
pred spaceKeeps[p: Placement] {
  all n: Need | all b: needNext[p, n] |
    (minus[Col.cap, placedBefore[p, n]] >= n.lines
      and (all t: Text | t.pos < n.pos implies here[p, t])
      and (all g: Figure - waitingIn[p] | g.pos < n.pos implies g in p.kept)
      and plus[loadBefore[p, b], firstPart[b]] <= Col.cap
      and (b in Line implies b = first[b.para]))
      implies inColumn[p, b]
}

-- the figures as 'figures' places them, and a figure that is the next block of a need-lines not met goes to the next column:
-- need-lines applies before the block is placed (docs/adr/0030)
pred figures27[p: Placement] {
  all f: Figure |
    (f in p.kept) iff (
      (all t: Text | t.pos < f.pos implies here[p, t])
      and (all g: Figure | g.pos < f.pos implies g in p.kept)
      and plus[plus[plus[plus[Col.used, #{t: Text | t.pos < f.pos}], (sum g: {g: Figure | g.pos < f.pos} | g.size)], #{b: Blank | b.pos < f.pos and not blankAtTop[p, b]}], f.size] <= Col.cap
      and (all n: Need | f in needNext[p, n] implies (minus[Col.cap, placedBefore[p, f]] >= n.lines or firstInColumn[p, f])))
}

pred base27[p: Placement] { fits[p] and order[p] and figures27[p] and figureOrder[p] and noSendFromEmpty[p] and blankWithNext[p] }

-- the shape of golem-layout ADR 0027 is an input: need-lines, a space, and the block after them in this column
run needSpaceSome {
  inDomain27
  some p: Placement, n: Need, sp: Space, b: Text - Space |
    base27[p] and needMet[p] and spaceKeeps[p] and n.pos < sp.pos and sp.pos < b.pos and b in needNext[p, n] and here[p, sp] and here[p, b]
} for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- need-lines, the spaces, the blank line and the figures together: no input has no placement
run needSpaceNone { inDomain27 and (no p: Placement | base27[p] and needMet[p] and spaceKeeps[p]) } for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- with the rules of the lines and the headings but the greedy fill
run needSpaceAllButGreedy {
  inDomain27
  no p: Placement | base27[p] and needMet[p] and spaceKeeps[p] and orphan[p] and widow[p] and keepHeading21[p]
} for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- the pair: need-lines and placing a figure where it fits, which gives way to need-lines
run needFigure {
  inDomain27
  (some p: Placement | fits[p] and figures[p] and figureOrder[p])
  (some p: Placement | fits[p] and needMet[p])
  no p: Placement | fits[p] and figures[p] and figureOrder[p] and needMet[p]
} for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- the pair: need-lines and the greedy fill, which gives way to need-lines
run needGreedy {
  inDomain27
  (some p: Placement | fits[p] and greedy[p])
  (some p: Placement | fits[p] and needMet[p])
  no p: Placement | fits[p] and greedy[p] and needMet[p]
} for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- golem-layout ADR 0035: a larger need-lines after one judged before a space

-- the inputs of the commands of golem-layout ADR 0035: two need-lines of any lines, a space, a blank line and two figures may be there
pred inDomain35 { figuresFit and #Need = 2 }

-- the grid lines placed in the column before an item, the spaces counted and the blank lines not:
-- a need-lines judged again after a space is judged with the space placed before it
fun judgedBefore[p: Placement, i: Item]: Int {
  plus[placedBefore[p, i], #{s: Space | s.pos < i.pos and here[p, s]}]
}

-- the need-lines before a need-lines with the same next block
fun needsBefore[p: Placement, n: Need, b: Item]: set Need { {m: Need | m.pos < n.pos and b in needNext[p, m]} }

-- P7 before golem-layout ADR 0035, for two need-lines: only the first of the need-lines of a block is judged where it is written
pred spaceKeepsFirst[p: Placement] {
  all n: Need | all b: needNext[p, n] |
    (no needsBefore[p, n, b]
      and minus[Col.cap, placedBefore[p, n]] >= n.lines
      and (all t: Text | t.pos < n.pos implies here[p, t])
      and (all g: Figure - waitingIn[p] | g.pos < n.pos implies g in p.kept)
      and plus[loadBefore[p, b], firstPart[b]] <= Col.cap
      and (b in Line implies b = first[b.para]))
      implies inColumn[p, b]
}

-- P7 after golem-layout ADR 0035: the first need-lines of a block is judged where it is written; a need-lines after it,
-- larger than the ones before it, is judged again where it is written, the spaces placed before it counted; one no larger
-- is met already. The block stays in this column, when its first part fits, only when all those judged are met.
pred spaceKeeps35[p: Placement] {
  all n: Need | all b: needNext[p, n] |
    ((all m: Need | (b in needNext[p, m] and (no k: needsBefore[p, m, b] | k.lines >= m.lines)) implies
        minus[Col.cap, (some needsBefore[p, m, b] => judgedBefore[p, m] else placedBefore[p, m])] >= m.lines)
      and (all t: Text | t.pos < n.pos implies here[p, t])
      and (all g: Figure - waitingIn[p] | g.pos < n.pos implies g in p.kept)
      and plus[loadBefore[p, b], firstPart[b]] <= Col.cap
      and (b in Line implies b = first[b.para]))
      implies inColumn[p, b]
}

-- the shape of golem-layout ADR 0035 is an input: need-lines, a space, a larger need-lines that fits a column, and their next block in this column, not first in it
run needMoreSome {
  inDomain35
  some p: Placement, n, m: Need, sp: Space, b: Text - Space |
    base27[p] and needMet[p] and spaceKeeps35[p] and n.pos < sp.pos and sp.pos < m.pos and m.lines > n.lines
      and m.lines <= Col.cap and b in needNext[p, n] and b in needNext[p, m] and here[p, sp] and here[p, b]
      and not firstInColumn[p, b]
} for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- before golem-layout ADR 0035: P7 keeps the block where the first need-lines is met, and P1 asks for the larger one after the space
run needMore27 {
  inDomain35
  some n, m: Need, sp: Space | n.pos < sp.pos and sp.pos < m.pos
  no p: Placement | base27[p] and needMet[p] and spaceKeepsFirst[p]
} for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank

-- after golem-layout ADR 0035: no input has no placement
run needMoreNone { inDomain35 and (no p: Placement | base27[p] and needMet[p] and spaceKeeps35[p]) } for 5 but 5 Int, 24 Placement, 2 Figure, 1 Blank
