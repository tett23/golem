import FigureTable
namespace BesideFigureWindow
open BesideStore BesideFigureTable BesideProducer

def readWindow (table : Nat → Option α) (start : Nat) : Nat → List (Nat × α)
  | 0 => []
  | fuel + 1 => match table start with
    | none => readWindow table (start + 1) fuel
    | some value => (start, value) :: readWindow table (start + 1) fuel

private theorem other_key (pairs : List (Nat × α)) (head key : Nat) (value : α) (different : key ≠ head) :
    fromPairs ((head, value) :: pairs) key = fromPairs pairs key := by
  cases found : fromPairs pairs key <;> simp [fromPairs, found, different]

private theorem window_congr (left right : Nat → Option α) (start fuel : Nat)
    (equal : ∀ key, start ≤ key → key < start + fuel → left key = right key) :
    readWindow left start fuel = readWindow right start fuel := by
  induction fuel generalizing start with
  | zero => rfl
  | succ fuel ih =>
    have head := equal start (Nat.le_refl _) (by omega)
    have tail := ih (start + 1) (fun key low high => equal key (by omega) (by omega))
    simp only [readWindow, head, tail]

theorem root_adr0352_i5_current_figure_sorted_readback
    (kindAt : Nat → Option Kind) (place : Nat → Option α) (start fuel : Nat) :
    readWindow (fromPairs (figurePairs kindAt place start fuel)) start fuel = figurePairs kindAt place start fuel := by
  induction fuel generalizing start with
  | zero => rfl
  | succ fuel ih =>
    have absent : fromPairs (figurePairs kindAt place (start + 1) fuel) start = none := by
      apply root_adr0352_i5_store_missing_key
      intro member
      have bound := root_adr0352_i5_figure_pair_source kindAt place (start + 1) fuel start member
      omega
    by_cases figure : kindAt start = some .figure
    · cases placed : place start with
      | none =>
        simp only [figurePairs, figure, if_true, placed]
        rw [readWindow, absent]
        exact ih (start + 1)
      | some value =>
        simp only [figurePairs, figure, if_true, placed]
        have atHead : fromPairs ((start, value) :: figurePairs kindAt place (start + 1) fuel) start = some value := by
          simp [fromPairs, absent]
        rw [readWindow, atHead]
        have tail := window_congr
          (fromPairs ((start, value) :: figurePairs kindAt place (start + 1) fuel))
          (fromPairs (figurePairs kindAt place (start + 1) fuel)) (start + 1) fuel
          (fun key lower _upper => other_key _ start key value (by omega))
        rw [tail, ih]
    · simp only [figurePairs, figure, if_false]
      rw [readWindow, absent]
      exact ih (start + 1)


theorem root_adr0352_i5_window_key_bounds
    (table : Nat → Option α) (start fuel key : Nat)
    (member : key ∈ pairKeys (readWindow table start fuel)) : start ≤ key ∧ key < start + fuel := by
  induction fuel generalizing start with
  | zero => simp [readWindow, pairKeys] at member
  | succ fuel ih =>
    cases found : table start with
    | none =>
      simp only [readWindow, found] at member
      have bound := ih (start + 1) member
      exact ⟨by omega, by omega⟩
    | some value =>
      simp only [readWindow, found, pairKeys] at member
      rcases List.mem_cons.mp member with first | later
      · subst key; exact ⟨Nat.le_refl _, by omega⟩
      · have bound := ih (start + 1) later
        exact ⟨by omega, by omega⟩

theorem root_adr0352_i5_window_keys_increasing (table : Nat → Option α) (start fuel : Nat) :
    BesideOwnership.Increasing (pairKeys (readWindow table start fuel)) := by
  induction fuel generalizing start with
  | zero => trivial
  | succ fuel ih =>
    cases found : table start with
    | none => simp only [readWindow, found]; exact ih (start + 1)
    | some value =>
      simp only [readWindow, found, pairKeys, BesideOwnership.Increasing]
      constructor
      · intro key member
        have bound := root_adr0352_i5_window_key_bounds table (start + 1) fuel key member
        omega
      · exact ih (start + 1)

theorem root_adr0352_i5_figure_pairs_keys_increasing
    (kindAt : Nat → Option Kind) (place : Nat → Option α) (start fuel : Nat) :
    BesideOwnership.Increasing (pairKeys (figurePairs kindAt place start fuel)) := by
  rw [← root_adr0352_i5_current_figure_sorted_readback kindAt place start fuel]
  exact root_adr0352_i5_window_keys_increasing _ start fuel


def rowJobs (eligible : α → Bool) (stateAt : Nat → σ) (count : Nat) : List (Nat × α) → List (BesideReuse.ReuseJob σ)
  | [] => []
  | (key, value) :: later =>
    let rest := rowJobs eligible stateAt count later
    if eligible value then ⟨key, count - (key + 1), stateAt key⟩ :: rest else rest

theorem root_adr0352_i5_window_job_selection
    (table : Nat → Option α) (eligible : α → Bool) (stateAt : Nat → σ) (count start fuel : Nat) :
    tableJobs table eligible stateAt count start fuel = rowJobs eligible stateAt count (readWindow table start fuel) := by
  induction fuel generalizing start with
  | zero => rfl
  | succ fuel ih =>
    cases found : table start <;> simp [readWindow, tableJobs, selectedAt, rowJobs, found, ih]

theorem root_adr0352_i5_figure_row_jobs_legal
    (round : BesidePayloadRounds.PayloadRound σ β) (place : Nat → Option α) (eligible : α → Bool) (stateAt : Nat → σ) :
    BesideReuse.roundJobsLegal {round.control with jobs := (rowJobs eligible stateAt round.control.count
      (figurePairs round.control.kindAt place 0 round.control.count))} := by
  rw [← root_adr0352_i5_current_figure_sorted_readback round.control.kindAt place 0 round.control.count]
  rw [← root_adr0352_i5_window_job_selection]
  exact root_adr0352_i5_constructed_figure_jobs_legal round place eligible stateAt

end BesideFigureWindow
