-- The rules of pagination at the boundary of one column and the next
-- (docs/adr/0204, section 5). The rules are predicates, not facts: the
-- commands look for inputs on which no placement meets a set of rules.
--
-- An input is a column of `cap` grid lines with `used` of them already
-- taken (0: an empty column), and items in the order of the flow: the
-- lines of paragraphs, headings of one grid line, and at most one
-- figure. A placement puts the text before `brk` in the column and the
-- rest in the next column, and puts the figure in the column or sends
-- it to the next one. Every placement of an input exists as an atom
-- (fact allPlacements), so "no placement meets the rules" is first
-- order.
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

sig Figure extends Item {
  size: one Int
}

sig Placement {
  brk: one Int,
  kept: lone Figure
}

-- the input

fact input {
  Col.cap >= 3 and Col.cap <= 6
  Col.used >= 0 and Col.used <= Col.cap
  lone Figure
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
  all b: Int | (b >= 0 and b <= #Text) implies {
    some p: Placement | p.brk = b and no p.kept
    all f: Figure | some p: Placement | p.brk = b and p.kept = f
  }
  all p: Placement | p.brk >= 0 and p.brk <= #Text
  all disj p, q: Placement | p.brk != q.brk or p.kept != q.kept
}

-- the place of the text: its index among the text items
fun tpos[t: Text]: Int { #{u: Text | u.pos < t.pos} }

pred here[p: Placement, t: Text] { tpos[t] < p.brk }

fun load[p: Placement]: Int {
  plus[plus[Col.used, #{t: Text | here[p, t]}], (some p.kept implies p.kept.size else 0)]
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

-- nothing is sent on from an empty column
pred noSendFromEmpty[p: Placement] {
  (Col.used = 0 and some Text) implies p.brk >= 1
}

pred all7[p: Placement] {
  fits[p] and greedy[p] and order[p] and figure[p] and orphan[p] and widow[p] and keepHeading[p] and noSendFromEmpty[p]
}

-- the commands

-- the model is not empty: with no rule but fitting, a placement exists
run someFits { some p: Placement | fits[p] } for 6 but 5 Int, 7 Placement

-- the model is not all false: every rule together fails on some input
run noneMeetsAll { no p: Placement | all7[p] } for 6 but 5 Int, 14 Placement

-- every rule but the greedy fill together: the fill gives way to the others
run noneMeetsAllButGreedy {
  no p: Placement | fits[p] and order[p] and figure[p] and orphan[p] and widow[p] and keepHeading[p] and noSendFromEmpty[p]
} for 6 but 5 Int, 14 Placement

-- the pairs: an input where some placement meets each rule, and none meets both
run greedyOrphan { (some p: Placement | fits[p] and greedy[p]) and (some p: Placement | fits[p] and orphan[p]) and no p: Placement | fits[p] and greedy[p] and orphan[p] } for 6 but 5 Int, 14 Placement
run greedyWidow { (some p: Placement | fits[p] and greedy[p]) and (some p: Placement | fits[p] and widow[p]) and no p: Placement | fits[p] and greedy[p] and widow[p] } for 6 but 5 Int, 14 Placement
run greedyKeepHeading { (some p: Placement | fits[p] and greedy[p]) and (some p: Placement | fits[p] and keepHeading[p]) and no p: Placement | fits[p] and greedy[p] and keepHeading[p] } for 6 but 5 Int, 14 Placement
run greedyFigure { (some p: Placement | fits[p] and greedy[p]) and (some p: Placement | fits[p] and figure[p]) and no p: Placement | fits[p] and greedy[p] and figure[p] } for 6 but 5 Int, 14 Placement
run orphanEmpty { (some p: Placement | fits[p] and orphan[p]) and (some p: Placement | fits[p] and noSendFromEmpty[p]) and no p: Placement | fits[p] and orphan[p] and noSendFromEmpty[p] } for 6 but 5 Int, 14 Placement
run widowEmpty { (some p: Placement | fits[p] and widow[p]) and (some p: Placement | fits[p] and noSendFromEmpty[p]) and no p: Placement | fits[p] and widow[p] and noSendFromEmpty[p] } for 6 but 5 Int, 14 Placement
run keepHeadingEmpty { (some p: Placement | fits[p] and keepHeading[p]) and (some p: Placement | fits[p] and noSendFromEmpty[p]) and no p: Placement | fits[p] and keepHeading[p] and noSendFromEmpty[p] } for 6 but 5 Int, 14 Placement
run orphanWidow { (some p: Placement | fits[p] and orphan[p]) and (some p: Placement | fits[p] and widow[p]) and no p: Placement | fits[p] and orphan[p] and widow[p] } for 6 but 5 Int, 14 Placement
run keepHeadingOrphan { (some p: Placement | fits[p] and keepHeading[p]) and (some p: Placement | fits[p] and orphan[p]) and no p: Placement | fits[p] and keepHeading[p] and orphan[p] } for 6 but 5 Int, 14 Placement
run keepHeadingWidow { (some p: Placement | fits[p] and keepHeading[p]) and (some p: Placement | fits[p] and widow[p]) and no p: Placement | fits[p] and keepHeading[p] and widow[p] } for 6 but 5 Int, 14 Placement
run keepHeadingFigure { (some p: Placement | fits[p] and keepHeading[p]) and (some p: Placement | fits[p] and figure[p]) and no p: Placement | fits[p] and keepHeading[p] and figure[p] } for 6 but 5 Int, 14 Placement
run figureOrder { (some p: Placement | fits[p] and figure[p]) and (some p: Placement | fits[p] and order[p]) and no p: Placement | fits[p] and figure[p] and order[p] } for 6 but 5 Int, 14 Placement
run figureEmpty { (some p: Placement | fits[p] and figure[p]) and (some p: Placement | fits[p] and noSendFromEmpty[p]) and no p: Placement | fits[p] and figure[p] and noSendFromEmpty[p] } for 6 but 5 Int, 14 Placement
