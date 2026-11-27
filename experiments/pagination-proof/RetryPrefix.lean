import Physical
namespace PhysicalPagination

private theorem fittingGo_count (env : Env) (st : St) (rows : List Line) (used notes : Int) :
    fittingGo env st used notes rows ≤ rows.length := by
  induction rows generalizing used notes with
  | nil => simp [fittingGo]
  | cons row rest ih =>
    simp only [fittingGo, List.length_cons]
    split <;> split <;> first
      | exact Nat.zero_le _
      | exact Nat.succ_le_succ (ih _ _)

private theorem fittingWrapGo_count (env : Env) (st : St) (edge : Int) (rows : List Line) (used notes : Int) :
    fittingWrapGo env st edge used notes rows ≤ rows.length := by
  induction rows generalizing used notes with
  | nil => simp [fittingWrapGo]
  | cons row rest ih =>
    simp only [fittingWrapGo, List.length_cons]
    split <;> split <;> first
      | exact Nat.zero_le _
      | exact Nat.succ_le_succ (ih _ _)

theorem root_adr0352_i4_fitting_count (env : Env) (region : Region) (st : St) (rows : List Line) :
    fittingHere env region st rows ≤ rows.length := by
  unfold fittingHere
  split
  · exact fittingGo_count env st rows _ _
  · exact fittingWrapGo_count env st _ rows _ _

private theorem restCount (env : Env) (region : Region) (cutoff : Option Nat) (keep : Keep)
    (isStart : Bool) (cursor : St) (rows : List Line) (fid count : Nat) (placed : St) (relaxed : Keep)
    (result : trialWrapRest env region cutoff keep isStart cursor rows fid = .ok (.placed count placed relaxed)) :
    count = (if limited cutoff (splitAtBreak keep isStart rows.length (fittingHere env region cursor rows)) = 0
      then max 1 (fittingHere env region cursor rows)
      else limited cutoff (splitAtBreak keep isStart rows.length (fittingHere env region cursor rows))) := by
  unfold trialWrapRest at result
  dsimp only at result
  split at result
  · cases result
  · split at result
    · cases result
    · injection result with same
      injection same with sameCount _ _
      exact sameCount.symm

private theorem rest_count_le_max (env : Env) (region : Region) (cutoff : Option Nat) (keep : Keep)
    (isStart : Bool) (cursor : St) (rows : List Line) (fid count : Nat) (placed : St) (relaxed : Keep)
    (result : trialWrapRest env region cutoff keep isStart cursor rows fid = .ok (.placed count placed relaxed)) :
    count ≤ max 1 rows.length := by
  have fitted := root_adr0352_i4_fitting_count env region cursor rows
  have splitBound := splitAtBreak_le keep isStart rows.length (fittingHere env region cursor rows)
  have selectedBound := limited_le cutoff (splitAtBreak keep isStart rows.length (fittingHere env region cursor rows))
  have value := restCount env region cutoff keep isStart cursor rows fid count placed relaxed result
  split at value <;> omega

private theorem trialFrom_count_bound (env : Env) (region : Region) (cutoff : Option Nat)
    (keep : Keep) (isStart : Bool) (cursor : St) (rows : List Line) (count : Nat) (placed : St) (relaxed : Keep)
    (result : trialWrapFrom env region cutoff keep isStart cursor rows = .ok (.placed count placed relaxed)) :
    count ≤ rows.length := by
  cases rows with
  | nil =>
    simp only [trialWrapFrom] at result
    injection result with same
    injection same with sameCount _ _
    subst count
    exact Nat.zero_le _
  | cons first rest =>
    simp only [trialWrapFrom] at result
    split at result
    · cases result
    · split at result
      · split at result
        · have bound := rest_count_le_max _ _ _ _ _ _ _ _ _ _ _ result
          simp only [List.length_cons] at bound ⊢
          omega
        · cases result
      · have bound := rest_count_le_max _ _ _ _ _ _ _ _ _ _ _ result
        simp only [List.length_cons] at bound ⊢
        omega

theorem root_adr0352_i4_trial_count_bound (env : Env) (region : Region) (cutoff : Option Nat)
    (keep : Keep) (isStart : Bool) (cursor : St) (rows : List Line) (count : Nat) (placed : St) (relaxed : Keep)
    (result : trialWrap env region cutoff keep isStart cursor rows = .ok (.placed count placed relaxed)) :
    count ≤ rows.length := by
  unfold trialWrap at result
  split at result
  · cases result
  · exact trialFrom_count_bound _ _ _ _ _ _ _ _ _ _ result

/-- The caller only needs this bound after a complete trial with a
    removable trailing line. The cutoff is positive, not a decreasing
    rank assumed as a hypothesis. -/
theorem root_adr0352_i4_complete_rest_respects_prefix
    (env : Env) (region : Region) (cutoff : Nat) (positivePrefix : 0 < cutoff) (keep : Keep)
    (isStart : Bool) (cursor : St) (rows : List Line) (fid count : Nat) (placed : St) (relaxed : Keep)
    (result : trialWrapRest env region (some cutoff) keep isStart cursor rows fid = .ok (.placed count placed relaxed))
    (complete : rows.length ≤ count) (large : 1 < count) : count ≤ cutoff := by
  have value := restCount env region (some cutoff) keep isStart cursor rows fid count placed relaxed result
  simp only [limited] at value
  by_cases zero : min cutoff (splitAtBreak keep isStart rows.length (fittingHere env region cursor rows)) = 0
  · rw [if_pos zero] at value
    have allFit : rows.length ≤ fittingHere env region cursor rows := by omega
    have splitValue : splitAtBreak keep isStart rows.length (fittingHere env region cursor rows) = fittingHere env region cursor rows := by
      simp only [splitAtBreak, if_pos allFit]
    rw [splitValue] at zero
    omega
  · rw [if_neg zero] at value
    have bound := Nat.min_le_left cutoff (splitAtBreak keep isStart rows.length (fittingHere env region cursor rows))
    omega

end PhysicalPagination

namespace PhysicalPagination

private theorem completeFrom_respects_prefix
    (env : Env) (region : Region) (cutoff : Nat) (positivePrefix : 0 < cutoff) (keep : Keep)
    (isStart : Bool) (cursor : St) (rows : List Line) (count : Nat) (placed : St) (relaxed : Keep)
    (result : trialWrapFrom env region (some cutoff) keep isStart cursor rows = .ok (.placed count placed relaxed))
    (complete : rows.length ≤ count) (large : 1 < count) : count ≤ cutoff := by
  cases rows with
  | nil => simp [trialWrapFrom] at result; omega
  | cons first rest =>
    simp only [trialWrapFrom] at result
    split at result
    · cases result
    · split at result
      · split at result
        · exact root_adr0352_i4_complete_rest_respects_prefix _ _ _ positivePrefix _ _ _ _ _ _ _ _ result complete large
        · cases result
      · exact root_adr0352_i4_complete_rest_respects_prefix _ _ _ positivePrefix _ _ _ _ _ _ _ _ result complete large

theorem root_adr0352_i4_complete_trial_respects_prefix
    (env : Env) (region : Region) (cutoff : Nat) (positivePrefix : 0 < cutoff) (keep : Keep)
    (isStart : Bool) (cursor : St) (rows : List Line) (count : Nat) (placed : St) (relaxed : Keep)
    (result : trialWrap env region (some cutoff) keep isStart cursor rows = .ok (.placed count placed relaxed))
    (complete : rows.length ≤ count) (large : 1 < count) : count ≤ cutoff := by
  unfold trialWrap at result
  split at result
  · cases result
  · exact completeFrom_respects_prefix _ _ _ positivePrefix _ _ _ _ _ _ _ result complete large

private theorem minFront_positive (isStart : Bool) (lastWanted : Nat) (keep : Keep) :
    0 < minimumFront isStart lastWanted keep := by
  unfold minimumFront
  split
  · split <;> omega
  · decide

theorem root_adr0352_i4_front_retry_rank
    (env : Env) (region : Region) (cutoff : Option Nat)
    (positiveCutoff : ∀ n, cutoff = some n → 0 < n)
    (keep : Keep) (isStart : Bool) (cursor : St) (rows : List Line)
    (count lastWanted : Nat) (placed : St) (relaxed : Keep)
    (result : trialWrap env region cutoff keep isStart cursor rows = .ok (.placed count placed relaxed))
    (complete : rows.length ≤ count)
    (front : minimumFront isStart lastWanted keep ≤ count - max lastWanted (max 1 relaxed.last)) :
    count - max lastWanted (max 1 relaxed.last) < limitRank cutoff rows.length := by
  have minimum := minFront_positive isStart lastWanted keep
  have lower : 1 ≤ max lastWanted (max 1 relaxed.last) := by omega
  have decrease : count - max lastWanted (max 1 relaxed.last) < count := by omega
  cases cutoff with
  | none =>
    have bound := root_adr0352_i4_trial_count_bound _ _ _ _ _ _ _ _ _ _ result
    simp only [limitRank]
    omega
  | some n =>
    have bound := root_adr0352_i4_complete_trial_respects_prefix _ _ n (positiveCutoff n rfl)
      _ _ _ _ _ _ _ result complete (by omega)
    simp only [limitRank]
    omega

end PhysicalPagination

namespace PhysicalPagination

def retryEntryValid (env : Env) (region : Region)
    (breaker : St → Nat → Nat → List (Line × Nat)) (lastWanted : Nat)
    (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St) : Prop :=
  (∀ bound, limit = some bound → 0 < bound) ∧
  ∀ count placed relaxed,
    trialWrap env region limit k isStart at' ((breaker at' before start).map Prod.fst) = .ok (.placed count placed relaxed) →
    (breaker at' before start).length ≤ count →
    minimumFront isStart lastWanted k ≤ count - max lastWanted (max 1 relaxed.last) →
    count - max lastWanted (max 1 relaxed.last) < limitRank limit (breaker at' before start).length

set_option linter.unusedVariables false in
def partsRetryEntriesSafe (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St)
    (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St) : Prop :=
  retryEntryValid env region breaker lastWanted limit k isStart start before at' ∧
  (match hm : trialWrap env region limit k isStart at' ((breaker at' before start).map (·.1)) with
  | .error e => True
  | .ok (.moved moved relaxed) =>
    partsRetryEntriesSafe env region breaker items lastWanted follows hold none relaxed isStart start before moved
  | .ok (.placed count placed relaxed) =>
    if (breaker at' before start).length ≤ count then
      if follows (checkWaits placed) || (breaker at' before start).isEmpty then True
      else if h1 : minimumFront isStart lastWanted k ≤ count - max lastWanted (max 1 relaxed.last) ∧ relaxed.all = false then
        if h2 : count - max lastWanted (max 1 relaxed.last) < limitRank limit (breaker at' before start).length then
          partsRetryEntriesSafe env region breaker items lastWanted follows hold (some (count - max lastWanted (max 1 relaxed.last)))
            k isStart start before at'
        else True
      else if h3 : empty at' = false then
        partsRetryEntriesSafe env region breaker items lastWanted follows hold none k isStart start before (moveCursor env region at')
      else True
    else if h4 : start < nextItem (breaker at' before start) count start ∧ start < items then
      if (breaker (moveCursor env region placed) (before + count) (nextItem (breaker at' before start) count start)).length
          < relaxed.last then
        if h5 : minimumFront isStart lastWanted k < count then
          if h6 : count - 1 < limitRank limit (breaker at' before start).length then
            partsRetryEntriesSafe env region breaker items lastWanted follows hold (some (count - 1)) k isStart start before at'
          else True
        else if h7 : empty at' = false then
          partsRetryEntriesSafe env region breaker items lastWanted follows hold none k isStart start before (moveCursor env region at')
        else
          partsRetryEntriesSafe env region breaker items lastWanted follows hold none relaxed false
            (nextItem (breaker at' before start) count start) (before + count) (moveCursor env region placed)
      else
        partsRetryEntriesSafe env region breaker items lastWanted follows hold none relaxed false
          (nextItem (breaker at' before start) count start) (before + count) (moveCursor env region placed)
    else True
)
termination_by (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.right
    cases I4_trialWrap_moved env region limit k isStart at' _ moved relaxed hm with
    | inl l => exact Prod.Lex.left _ _ l
    | inr e => rw [e.1]; exact Prod.Lex.right _ (Prod.Lex.left _ _ e.2)
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right
    simp only [limitRank] at h2 ⊢; exact h2
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
    exact I4_moveCursor_rank env region at' (Or.inl h3)
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right
    simp only [limitRank] at h6 ⊢; exact h6
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
    exact I4_moveCursor_rank env region at' (Or.inl h7)
  · apply Prod.Lex.left; have a := h4.1; have b := h4.2; omega
  · apply Prod.Lex.left; have a := h4.1; have b := h4.2; omega


theorem root_adr0352_i4_parts_retry_entries (env : Env) (region : Region)
    (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St) :
    ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St),
    (∀ bound, limit = some bound → 0 < bound) →
      partsRetryEntriesSafe env region breaker items lastWanted follows hold limit k isStart start before at' := by
  have key : ∀ m, ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St),
      (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) = m →
      (∀ bound, limit = some bound → 0 < bound) →
      partsRetryEntriesSafe env region breaker items lastWanted follows hold limit k isStart start before at' := by
    intro m
    induction m using lex4_wf.induction with
    | _ m ih =>
    intro limit k isStart start before at' hm0 ready
    subst hm0
    rw [partsRetryEntriesSafe]
    refine ⟨⟨ready, ?_⟩, ?_⟩
    · intro count placed relaxed result complete front
      have decrease := root_adr0352_i4_front_retry_rank env region limit ready k isStart at'
        ((breaker at' before start).map Prod.fst) count lastWanted placed relaxed result
        (by simpa only [List.length_map] using complete) front
      simpa only [List.length_map] using decrease
    split
    · trivial
    · rename_i moved relaxed hm
      have dec : lex4lt (items - start, keepRank relaxed, rank moved, limitRank none (breaker moved before start).length)
          (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
        apply Prod.Lex.right
        cases I4_trialWrap_moved env region limit k isStart at' _ moved relaxed hm with
        | inl l => exact Prod.Lex.left _ _ l
        | inr e => rw [e.1]; exact Prod.Lex.right _ (Prod.Lex.left _ _ e.2)
      exact ih _ dec none relaxed isStart start before moved rfl (by simp)
    · rename_i count placed relaxed _hm
      have again : ∀ limit' k' isStart' start' before' at'',
          lex4lt (items - start', keepRank k', rank at'', limitRank limit' (breaker at'' before' start').length)
            (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) →
          (∀ bound, limit' = some bound → 0 < bound) →
          partsRetryEntriesSafe env region breaker items lastWanted follows hold limit' k' isStart' start' before' at'' := by
        intro limit' k' isStart' start' before' at'' dec hready
        exact ih _ dec limit' k' isStart' start' before' at'' rfl hready
      repeat' split
      all_goals first
        | trivial
        | (apply again <;> try assumption)
      all_goals first
        | (solve | simp)
        | (intro bound same; cases same; have positive := minFront_positive isStart lastWanted k; omega)
        | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right
           simp only [limitRank] at *; omega)
        | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
           exact I4_moveCursor_rank env region at' (Or.inl ‹empty at' = false›))
        | (apply Prod.Lex.left; omega)
  intro limit k isStart start before at' h
  exact key _ limit k isStart start before at' rfl h

theorem root_adr0352_i4_initial_parts_retry_entries (env : Env) (region : Region)
    (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St) (k : Keep) (cursor : St) :
    partsRetryEntriesSafe env region breaker items lastWanted follows hold none k true 0 0 cursor :=
  root_adr0352_i4_parts_retry_entries env region breaker items lastWanted follows hold none k true 0 0 cursor (by simp)

/-- An externally supplied zero cutoff uses the existing forced fallback.
    The positive cutoff condition cannot simply be removed. -/
theorem root_adr0352_i4_external_zero_cutoff :
    let selected := limited (some 0) (splitAtBreak defaultKeep true 4 4)
    let taken := if selected = 0 then max 1 4 else selected
    taken = 4 ∧ ¬ (taken - max 0 (max 1 defaultKeep.last) < limitRank (some 0) 4) := by decide

end PhysicalPagination
