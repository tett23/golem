import DerivedJobs
namespace BesideFigureTable
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideDerivedJobs

def figurePairs (kindAt : Nat → Option Kind) (place : Nat → Option α) (start : Nat) : Nat → List (Nat × α)
  | 0 => []
  | fuel + 1 =>
    let rest := figurePairs kindAt place (start + 1) fuel
    if kindAt start = some .figure then
      match place start with | none => rest | some value => (start, value) :: rest
    else rest

theorem root_adr0352_i5_figure_pair_source
    (kindAt : Nat → Option Kind) (place : Nat → Option α) (start fuel key : Nat)
    (member : key ∈ pairKeys (figurePairs kindAt place start fuel)) :
    start ≤ key ∧ key < start + fuel ∧ kindAt key = some .figure := by
  induction fuel generalizing start with
  | zero => simp [figurePairs, pairKeys] at member
  | succ fuel ih =>
    by_cases figure : kindAt start = some .figure
    · cases placed : place start with
      | none =>
        simp only [figurePairs, figure, if_true, placed] at member
        have result := ih (start + 1) member
        exact ⟨by omega, by omega, result.2.2⟩
      | some value =>
        simp only [figurePairs, figure, if_true, placed, pairKeys] at member
        rcases List.mem_cons.mp member with atHead | inTail
        · subst key
          exact ⟨Nat.le_refl _, by omega, figure⟩
        · have result := ih (start + 1) inTail
          exact ⟨by omega, by omega, result.2.2⟩
    · simp only [figurePairs, figure, if_false] at member
      have result := ih (start + 1) member
      exact ⟨by omega, by omega, result.2.2⟩

theorem root_adr0352_i5_figure_table_typed
    (kindAt : Nat → Option Kind) (place : Nat → Option α) (start fuel key : Nat)
    (present : (fromPairs (figurePairs kindAt place start fuel) key).isSome = true) :
    kindAt key = some .figure := by
  have member : key ∈ pairKeys (figurePairs kindAt place start fuel) := by
    by_cases found : key ∈ pairKeys (figurePairs kindAt place start fuel)
    · exact found
    · have absent := root_adr0352_i5_store_missing_key _ key found
      rw [absent] at present
      cases present
  exact (root_adr0352_i5_figure_pair_source kindAt place start fuel key member).2.2

def selectedAt (table : Nat → Option α) (eligible : α → Bool) (key : Nat) : Bool :=
  match table key with | none => false | some value => eligible value

def tableJobs (table : Nat → Option α) (eligible : α → Bool) (stateAt : Nat → σ)
    (count start : Nat) : Nat → List (ReuseJob σ)
  | 0 => []
  | fuel + 1 =>
    let rest := tableJobs table eligible stateAt count (start + 1) fuel
    if selectedAt table eligible start then ⟨start, count - (start + 1), stateAt start⟩ :: rest else rest

theorem root_adr0352_i5_table_jobs_equal_derived
    (kindAt : Nat → Option Kind) (table : Nat → Option α) (eligible : α → Bool) (stateAt : Nat → σ)
    (count start fuel : Nat) (typed : ∀ key, (table key).isSome = true → kindAt key = some .figure) :
    tableJobs table eligible stateAt count start fuel =
      jobsFrom kindAt (selectedAt table eligible) stateAt count start fuel := by
  induction fuel generalizing start with
  | zero => rfl
  | succ fuel ih =>
    cases stored : table start with
    | none => simp [tableJobs, jobsFrom, selectedAt, stored, ih]
    | some value =>
      have figure := typed start (by simp [stored])
      simp [tableJobs, jobsFrom, selectedAt, stored, figure, ih]

theorem root_adr0352_i5_constructed_figure_jobs_legal
    (round : PayloadRound σ β) (place : Nat → Option α) (eligible : α → Bool) (stateAt : Nat → σ) :
    let table := fromPairs (figurePairs round.control.kindAt place 0 round.control.count)
    roundJobsLegal {round.control with jobs := tableJobs table eligible stateAt round.control.count 0 round.control.count} := by
  dsimp only
  rw [root_adr0352_i5_table_jobs_equal_derived round.control.kindAt _ eligible stateAt
    round.control.count 0 round.control.count
    (fun key present => root_adr0352_i5_figure_table_typed round.control.kindAt place 0 round.control.count key present)]
  exact root_adr0352_i5_derived_round_legal round _ stateAt

end BesideFigureTable
