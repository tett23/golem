/- Golem ADR 0352: a finite cross-check of the transcribed Alloy predicates.
   It enumerates every input of at most four items (two paragraphs,
   headings, recto headings, figures of sizes 1, 3 and 4) with a capacity
   of 3 or 4 lines and 0..4 used lines that meets `alloyInputFact`, and
   prints the inputs on which the unsatisfiable commands of docs/adr/0206
   would have an instance, and the need-lines inputs on which no candidate
   placement of alloyNeedCandidates meets every rule. Every list must be
   empty. This is a check of the
   transcription, not a proof. -/
import Pagination
open GolemPagination

def relaxedAfterHeadingsAt (inp : AlloyInput) : Bool :=
  alloyInDomain inp && alloyNoRecto inp && !alloySome inp (fun p => alloyBase inp p &&
    alloyOrphanH inp p && alloyWidowH inp p && alloyKeepHeading21 inp p && alloyLineAfterHeadingsRule inp p)
def rectoKeptAt (inp : AlloyInput) : Bool :=
  alloyInDomain inp && !alloySome inp (fun p => alloyBase inp p && alloyOrphanH inp p &&
    alloyWidowH inp p && alloyKeepHeading21 inp p && alloyLineAfterHeadingsRule inp p && alloyRecto inp p)
def rectoEndsAt (inp : AlloyInput) : Bool :=
  alloyInDomain inp && !alloySome inp (fun p => alloyBase inp p && alloyOrphanH inp p &&
    alloyWidowH inp p && alloyKeepHeadingR inp p && alloyLineAfterHeadingsRule inp p && alloyRecto inp p)
def keep21At (inp : AlloyInput) : Bool :=
  alloyInDomain inp && alloyNoRecto inp && !alloySome inp (fun p => alloyBase inp p &&
    alloyOrphan inp p && alloyWidow inp p && alloyKeepHeading21 inp p)

def smallKinds : List AlloyItem :=
  [.line 0, .line 1, .heading, .recto, .figure 1, .figure 3, .figure 4]
def smallSequences : Nat → List (List AlloyItem)
  | 0 => [[]]
  | n+1 => let r := smallSequences n; r ++ (r.bind fun s => smallKinds.map fun k => s ++ [k])
def smallInputs : List AlloyInput :=
  (smallSequences 4).eraseDups.bind fun items => (List.range 5).bind fun used =>
    [3,4].filterMap fun cap =>
      let i : AlloyInput := ⟨cap,used,items⟩
      if alloyInputFact i then some i else none

def needKinds : List AlloyItem :=
  [.line 0, .line 1, .heading, .space, .need 2, .need 1, .need 3, .figure 1, .figure 2, .blank]
def needSequences : Nat → List (List AlloyItem)
  | 0 => [[]]
  | n+1 => let r := needSequences n; r ++ (r.bind fun s => needKinds.map fun k => s ++ [k])
def needInputs : List AlloyInput :=
  (needSequences 4).eraseDups.bind fun items => (List.range 4).bind fun used =>
    [3,4].filterMap fun cap =>
      let i : AlloyInput := ⟨cap,used,items⟩
      if alloyInputFact i then some i else none

#eval smallInputs.length
#eval smallInputs.filter relaxedAfterHeadingsAt
#eval smallInputs.filter rectoKeptAt
#eval smallInputs.filter rectoEndsAt
#eval smallInputs.filter keep21At

-- needSpaceNone and needMoreNone: a candidate of alloyNeedCandidates meets
-- every rule (both lists must be empty)
#eval needInputs.length
#eval needInputs.filter fun i => alloyInDomain27 i && !alloyRules27 i alloySpaceKeeps
#eval needInputs.filter fun i => alloyInDomain35 i && !alloyRules27 i alloySpaceKeeps35
