import PayloadRounds

namespace BesideDerivedJobs
open BesideOwnership BesideProducer BesideReuse BesidePayloadRounds

def jobsFrom (kindAt : Nat → Option Kind) (selected : Nat → Bool) (stateAt : Nat → σ)
    (count start : Nat) : Nat → List (ReuseJob σ)
  | 0 => []
  | fuel + 1 =>
    let rest := jobsFrom kindAt selected stateAt count (start + 1) fuel
    if kindAt start = some .figure ∧ selected start = true then
      ⟨start, count - (start + 1), stateAt start⟩ :: rest else rest

theorem root_adr0352_i5_derived_job_source
    (kindAt : Nat → Option Kind) (selected : Nat → Bool) (stateAt : Nat → σ)
    (count start fuel : Nat) (job : ReuseJob σ)
    (member : job ∈ jobsFrom kindAt selected stateAt count start fuel) :
    start ≤ job.owner ∧ job.owner < start + fuel ∧ kindAt job.owner = some .figure ∧
      selected job.owner = true ∧ job.fuel = count - (job.owner + 1) ∧ job.state = stateAt job.owner := by
  induction fuel generalizing start with
  | zero => simp [jobsFrom] at member
  | succ fuel ih =>
    by_cases chosen : kindAt start = some .figure ∧ selected start = true
    · simp only [jobsFrom, chosen, if_true] at member
      rcases List.mem_cons.mp member with atHead | inTail
      · cases atHead
        exact ⟨Nat.le_refl _, by change start < start + (fuel + 1); omega, chosen.1, chosen.2, rfl, rfl⟩
      · rcases ih (start + 1) inTail with ⟨lower, upper, figure, picked, amount, state⟩
        exact ⟨by omega, by omega, figure, picked, amount, state⟩
    · simp only [jobsFrom, chosen, if_false] at member
      rcases ih (start + 1) member with ⟨lower, upper, figure, picked, amount, state⟩
      exact ⟨by omega, by omega, figure, picked, amount, state⟩

theorem root_adr0352_i5_derived_jobs_ordered
    (kindAt : Nat → Option Kind) (selected : Nat → Bool) (stateAt : Nat → σ)
    (count start fuel : Nat) : jobsOrdered (jobsFrom kindAt selected stateAt count start fuel) := by
  induction fuel generalizing start with
  | zero => trivial
  | succ fuel ih =>
    by_cases chosen : kindAt start = some .figure ∧ selected start = true
    · simp only [jobsFrom, chosen, if_true, jobsOrdered]
      constructor
      · intro later member
        have bound := root_adr0352_i5_derived_job_source kindAt selected stateAt count (start + 1) fuel later member
        exact Nat.lt_of_lt_of_le (Nat.lt_succ_self start) bound.1
      · exact ih (start + 1)
    · simpa [jobsFrom, chosen] using ih (start + 1)

noncomputable def derivedRound (round : PayloadRound σ α) (selected : Nat → Bool) (stateAt : Nat → σ) : PayloadRound σ α :=
  ⟨{round.control with jobs := jobsFrom round.control.kindAt selected stateAt round.control.count 0 round.control.count}, round.payload⟩

theorem root_adr0352_i5_derived_round_legal (round : PayloadRound σ α) (selected : Nat → Bool) (stateAt : Nat → σ) :
    roundJobsLegal (derivedRound round selected stateAt).control := by
  constructor
  · exact root_adr0352_i5_derived_jobs_ordered round.control.kindAt selected stateAt round.control.count 0 round.control.count
  · intro job member
    exact (root_adr0352_i5_derived_job_source round.control.kindAt selected stateAt round.control.count 0 round.control.count job member).2.2.1


noncomputable def derivedRounds (selectedAt : Nat → Nat → Bool) (stateAt : Nat → Nat → σ) : Nat → List (PayloadRound σ α) → List (PayloadRound σ α)
  | _, [] => []
  | index, round :: later => derivedRound round (selectedAt index) (stateAt index) :: derivedRounds selectedAt stateAt (index + 1) later

theorem root_adr0352_i5_derived_rounds_legal
    (selectedAt : Nat → Nat → Bool) (stateAt : Nat → Nat → σ) (index : Nat) (rounds : List (PayloadRound σ α)) :
    ∀ round, round ∈ derivedRounds selectedAt stateAt index rounds → roundJobsLegal round.control := by
  induction rounds generalizing index with
  | nil => intro round member; simp [derivedRounds] at member
  | cons first later ih =>
    intro round member
    rcases List.mem_cons.mp member with atHead | inTail
    · cases atHead
      exact root_adr0352_i5_derived_round_legal first (selectedAt index) (stateAt index)
    · exact ih (index + 1) round inTail

theorem root_adr0352_i5_derived_payload_readback
    (selectedAt : Nat → Nat → Bool) (stateAt : Nat → Nat → σ) (index : Nat) (rounds : List (PayloadRound σ α)) :
    ∀ cache, runPayloadRounds none (derivedRounds selectedAt stateAt index rounds) = some cache →
      BesideStore.readPairs (BesideStore.pairKeys cache.pairs) (BesideStore.fromPairs cache.pairs) = cache.pairs := by
  apply root_adr0352_i5_payload_from_empty_readback
  exact root_adr0352_i5_derived_rounds_legal selectedAt stateAt index rounds

end BesideDerivedJobs
