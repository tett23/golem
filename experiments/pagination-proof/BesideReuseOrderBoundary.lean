import BesideReuseOrder

open BesideOwnership BesideProducer BesideReuse

private def kinds : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | 2 => some .figure
  | 3 => some .paragraph
  | _ => none
private def changed : Nat → Option Kind
  | 1 => some .figure
  | k => kinds k
private def bodies : Nat → Option Unit
  | 1 => some ()
  | 3 => some ()
  | _ => none
private def yes (_ : Nat) : Bool := true
private def no (_ : Unit) : Bool := false
private def allowed (_ : Nat) (_ : Unit) : Bool := true
private def step (_ : Nat) (s : Unit) : Unit := s
private def firstFresh (key : Nat) : Bool := decide (key ≠ 0)
private def secondFresh (key : Nat) : Bool := decide (key ≠ 3)
private def jobs : List (ReuseJob Unit) := [⟨0, 4, ()⟩, ⟨2, 4, ()⟩]

example : chooseAll true true 4 4 bodies kinds kinds yes true no allowed step step jobs = [1, 3] := by decide
example : chooseAll false true 4 4 bodies kinds kinds yes true no allowed step step jobs = [1, 3] := by decide
example : chooseAll true true 4 4 bodies kinds kinds firstFresh true no allowed step step jobs = [1, 3] := by decide
example : chooseAll true true 4 4 bodies kinds kinds secondFresh true no allowed step step jobs = [1, 3] := by decide
example : (reuseAllowed true true 4 4 0 bodies kinds kinds firstFresh,
    reuseAllowed true true 4 4 2 bodies kinds kinds firstFresh) = (false, true) := by decide
example : (reuseAllowed true true 4 4 0 bodies kinds kinds secondFresh,
    reuseAllowed true true 4 4 2 bodies kinds kinds secondFresh) = (true, false) := by decide
example : chooseAll true true 4 4 bodies kinds changed yes true no allowed step step jobs = [3] := by decide
example : Increasing (chooseKeys true true 4 4 0 bodies kinds kinds yes true no allowed step step 4 ()) :=
  root_adr0352_i5_chosen_keys_increasing _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
