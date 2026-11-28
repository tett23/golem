import MixedRoundOrder

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

private def chosen (available : Bool) (extra : Nat → Bool) (tasks : List (ReuseJob Unit)) : List Nat :=
  chooseAll available true 4 4 bodies kinds kinds extra true no allowed step step tasks

example : NoRepeat (chosen true yes jobs) := by change NoRepeat [1, 3]; simp [NoRepeat]
example : NoRepeat (chosen false yes jobs) := by change NoRepeat [1, 3]; simp [NoRepeat]
example : NoRepeat (chosen true firstFresh jobs) := by change NoRepeat [1, 3]; simp [NoRepeat]
example : NoRepeat (chosen true secondFresh jobs) := by change NoRepeat [1, 3]; simp [NoRepeat]
example : ¬ NoRepeat (chosen true yes [⟨0, 4, ()⟩, ⟨0, 4, ()⟩]) := by change ¬ NoRepeat [1, 1]; simp [NoRepeat]
example : ¬ Increasing (chosen true yes [⟨2, 4, ()⟩, ⟨0, 4, ()⟩]) := by
  intro ordered
  change Increasing [3, 1] at ordered
  exact (by decide : ¬ (3 < 1)) (ordered.1 1 (by decide))
example : NoRepeat (chooseAll true true 4 4 bodies kinds changed yes true no allowed step step jobs) := by change NoRepeat [3]; simp [NoRepeat]
example : ¬ jobsOrdered ([⟨0, 4, ()⟩, ⟨0, 4, ()⟩] : List (ReuseJob Unit)) := by
  intro ordered
  have wrong : 0 < 0 := ordered.1 ⟨0, 4, ()⟩ (List.mem_cons_self _ _)
  exact Nat.lt_irrefl 0 wrong
