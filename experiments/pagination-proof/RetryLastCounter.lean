import Physical

namespace PhysicalPagination

/-- Five synthetic source items, one per composed row. These are row-count
    inputs to parts, not a general model of the real-font line breaker. -/
def lastRetryRows (before start : Nat) : Nat → List (Line × Nat)
  | 0 => []
  | count + 1 => (⟨before, [], 0⟩, start + 1) :: lastRetryRows (before + 1) (start + 1) count

private def rowPitch (_ : Nat) : Int := 10
private def noHeading (_ : Nat) : Option (Int × Int) := none
private def noGap (_ : Nat) : Int := 0
private def noPadding (_ : Nat) : Option Int := none
private def noFollowing (_ : Bool) (_ : Nat) (_ : List Flow) : Int := 0
private def notHeld (_ : Nat) : Bool := false

def lastRetryEnv : Env :=
  { pagePitch := 10, fontSize := 10, capacity := 30, maxCapacity := 30, separator := 10,
    columns := 1, firstLine := 0, pitchOf := rowPitch, faceOf := rowPitch,
    headingBounds := noHeading, wrappedBefore := noGap, boxPadding := noPadding,
    firstNeed := noFollowing, retention := none, held := notHeld }

def lastRetryResult : Except Failure St :=
  parts lastRetryEnv none (fun _ before start => lastRetryRows before start (5 - start))
    5 0 (fun _ => true) id none ⟨2, 4, false⟩ true 0 0 (initial lastRetryEnv)

def lastRetryTrialCount (limit : Option Nat) : Option Nat :=
  match trialWrap lastRetryEnv none limit ⟨2, 4, false⟩ true (initial lastRetryEnv)
      ((lastRetryRows 0 0 5).map (·.1)) with
  | .ok (.placed count _ _) => some count
  | _ => none

theorem root_adr0352_i4_last_retry_trial_counts :
    lastRetryTrialCount none = some 3 ∧ lastRetryTrialCount (some 2) = some 3 ∧
      lastRetryTrialCount (some 1) = some 3 := by decide

set_option maxRecDepth 10000 in
set_option maxHeartbeats 1000000 in
theorem root_adr0352_i4_last_retry_no_progress :
    lastRetryResult = .error (.noProgress 0) := by rfl

theorem root_adr0352_i4_last_retry_rank_fails : ¬(3 - 1 < limitRank (some 2) 5) := by decide

end PhysicalPagination
