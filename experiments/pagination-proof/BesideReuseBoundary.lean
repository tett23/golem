import BesideReuse

open BesideProducer BesideReuse

private def before : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | _ => none
private def changed : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .figure
  | _ => none
private def body : Nat → Option Unit
  | 1 => some ()
  | _ => none
private def noBody (_ : Nat) : Option Unit := none
private def yes (_ : Nat) : Bool := true
private def no (_ : Unit) : Bool := false
private def allowed (_ : Nat) (_ : Unit) : Bool := true
private def step (_ : Nat) (s : Unit) : Unit := s

-- Old membership takes priority over the changed current figure.
example : candidateKeys body changed 0 2 = [1] := by decide
example : reuseAllowed true true 2 2 0 body before changed yes = false := by decide
example : reuseAllowed true true 2 2 0 body before before yes = true := by decide
example : reuseAllowed false true 2 2 0 body before before yes = false := by decide
example : reuseAllowed true false 2 2 0 body before before yes = false := by decide
example : reuseAllowed true true 3 2 0 body before before yes = false := by decide
example : reuseAllowed true true 2 2 0 body before before (fun k => decide (k ≠ 1)) = false := by decide
example : reuseAllowed true true 1 1 0 noBody before before yes = true := by decide
example : chooseKeys true true 2 2 0 body before changed yes true no allowed step step 2 () = [] := by decide
example : chooseKeys true true 2 2 0 body before before yes true no allowed step step 2 () = [1] := by decide
example : chooseAll true true 2 2 body before changed yes true no allowed step step
    [⟨0, 2, ()⟩] = [] := by decide
example : chooseAll false true 2 2 noBody before before yes true no allowed step step
    [⟨0, 2, ()⟩] = [1] := by decide
