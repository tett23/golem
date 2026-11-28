import ProducedPayloadKeys

open BesideProducer BesideReuse BesideStore BesidePayload

private def kinds : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | 2 => some .figure
  | 3 => some .paragraph
  | _ => none
private def controls : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .control
  | 2 => some .paragraph
  | 3 => some .paragraph
  | _ => none
private def body : Nat → Option Nat
  | 1 => some 111
  | 3 => some 333
  | _ => none
private def yes (_ : Nat) : Bool := true
private def no (_ : Nat) : Bool := false
private def allowed (_ _ : Nat) : Bool := true
private def paraStep (_ state : Nat) : Nat := state + 10
private def controlStep (_ state : Nat) : Nat := state + 100
private def payload (key state : Nat) : Nat := 1000 + key + state
private def halt (state : Nat) : Bool := decide (105 ≤ state)
private def firstFresh (key : Nat) : Bool := decide (key ≠ 0)
private def secondFresh (key : Nat) : Bool := decide (key ≠ 3)
private def jobs : List (ReuseJob Nat) := [⟨0, 4, 5⟩, ⟨2, 4, 7⟩]
private def result (available : Bool) (extra : Nat → Bool) : List (Nat × Nat) :=
  collectPayloads available true 4 4 body kinds kinds extra true no allowed paraStep controlStep payload jobs

example : composePayloads true no allowed paraStep controlStep kinds payload 1 5 4 = [(1, 1006)] := by decide
example : composePayloads true no allowed paraStep controlStep controls payload 1 1 4 = [(2, 1103), (3, 1114)] := by decide
example : composePayloads false no allowed paraStep controlStep controls payload 1 1 4 = [] := by decide
example : composePayloads true halt allowed paraStep controlStep controls payload 1 1 4 = [(2, 1103)] := by decide
example : choosePayloads true true 4 4 0 body kinds kinds yes true no allowed paraStep controlStep payload 4 5 = [(1, 111)] := by decide
example : result true yes = [(1, 111), (3, 333)] := by decide
example : result false yes = [(1, 1006), (3, 1010)] := by decide
example : result true firstFresh = [(1, 1006), (3, 333)] := by decide
example : result true secondFresh = [(1, 111), (3, 1010)] := by decide
example : readPairs [1, 3] (fromPairs (result true secondFresh)) = [(1, 111), (3, 1010)] := by decide
example : pairKeys (result false yes) = [1, 3] := by decide
example : composePayloads true no allowed paraStep controlStep kinds payload 1 5 0 = [] := by decide
