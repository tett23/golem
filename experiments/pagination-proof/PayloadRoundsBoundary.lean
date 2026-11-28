import PayloadRounds

open BesideProducer BesideReuse BesideStore BesidePayload BesidePayloadRounds

private def kinds : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | 2 => some .figure
  | 3 => some .paragraph
  | _ => none
private def no (_ : Nat) : Bool := false
private def yes (_ : Nat) : Bool := true
private def allow (_ _ : Nat) : Bool := true
private def step (_ n : Nat) : Nat := n + 1
private def payload (key state : Nat) : Nat := 100 + key + state
private def round : PayloadRound Nat Nat :=
  ⟨⟨kinds, 4, true, yes, true, no, allow, step, step, [⟨0, 4, 5⟩, ⟨2, 4, 8⟩]⟩, payload⟩

example : (nextPayloadCache none round).pairs = [(1, 106), (3, 111)] := by decide

private noncomputable def first : PayloadCache Nat := nextPayloadCache none round
private def changedPayload (key state : Nat) : Nat := 200 + key + state
private def changed : PayloadRound Nat Nat := ⟨round.control, changedPayload⟩
private def noWidth : PayloadRound Nat Nat := ⟨{round.control with widthsSame := false}, changedPayload⟩
private def newKinds : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .figure
  | 2 => some .figure
  | 3 => some .paragraph
  | _ => none
private def replacement : PayloadRound Nat Nat := ⟨{round.control with kindAt := newKinds}, changedPayload⟩
private def pairsOf (cache : Option (PayloadCache Nat)) : List (Nat × Nat) :=
  match cache with | none => [] | some c => c.pairs

example : pairsOf (runPayloadRounds none ([] : List (PayloadRound Nat Nat))) = [] := by decide
example : (nextPayloadCache (some first) changed).pairs = [(1, 106), (3, 111)] := by decide
example : (nextPayloadCache (some first) noWidth).pairs = [(1, 206), (3, 211)] := by decide
example : (nextPayloadCache (some first) replacement).pairs = [(3, 111)] := by decide
example : pairsOf (runPayloadRounds none [round, changed, noWidth]) = [(1, 206), (3, 211)] := by decide
example : pairKeys (nextPayloadCache (some first) replacement).pairs = [3] := by decide
example : readPairs [1, 3] (fromPairs (nextPayloadCache (some first) changed).pairs) = [(1, 106), (3, 111)] := by decide
example : (fromPairs (nextPayloadCache (some first) replacement).pairs 1).isSome = false := by decide
