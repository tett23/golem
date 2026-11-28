import DerivedJobs
open BesideProducer BesideReuse BesidePayloadRounds BesideDerivedJobs

private def kinds : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | 2 => some .control
  | 3 => some .figure
  | 4 => some .paragraph
  | _ => none
private def yes (_ : Nat) : Bool := true
private def no (_ : Nat) : Bool := false
private def onlyThree (key : Nat) : Bool := decide (key = 3)
private def stateAt (key : Nat) : Nat := key + 10
private def jobView (jobs : List (ReuseJob Nat)) : List (Nat × (Nat × Nat)) :=
  jobs.map (fun job => (job.owner, (job.fuel, job.state)))

example : jobView (jobsFrom kinds yes stateAt 5 0 5) = [(0, (4, 10)), (3, (1, 13))] := by decide

example : jobView (jobsFrom kinds no stateAt 5 0 5) = [] := by decide
example : jobView (jobsFrom kinds onlyThree stateAt 5 0 5) = [(3, (1, 13))] := by decide
example : jobView (jobsFrom kinds yes stateAt 5 0 0) = [] := by decide
example : jobView (jobsFrom kinds yes stateAt 5 1 2) = [] := by decide
example : jobView (jobsFrom kinds yes stateAt 5 1 4) = [(3, (1, 13))] := by decide
example : jobView (jobsFrom kinds yes stateAt 5 3 1) = [(3, (1, 13))] := by decide
example : jobView (jobsFrom kinds yes stateAt 5 5 4) = [] := by decide
private def allow (_ _ : Nat) : Bool := true
private def step (_ state : Nat) : Nat := state + 1
private def payload (key state : Nat) : Nat := 100 + key + state
private def base : PayloadRound Nat Nat :=
  ⟨⟨kinds, 5, true, yes, true, no, allow, step, step, []⟩, payload⟩
private def pairsOf (cache : Option (PayloadCache Nat)) : List (Nat × Nat) :=
  match cache with | none => [] | some c => c.pairs
example : pairsOf (runPayloadRounds none [derivedRound base yes stateAt]) = [(1, 111), (4, 117)] := by decide
example : pairsOf (runPayloadRounds none (derivedRounds (fun _ => yes) (fun _ => stateAt) 0 [base, base])) = [(1, 111), (4, 117)] := by decide
example : pairsOf (runPayloadRounds none [derivedRound base onlyThree stateAt]) = [(4, 117)] := by decide
