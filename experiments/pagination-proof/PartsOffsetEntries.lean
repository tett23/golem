/- Root ADR 0352: connect the number of placed text rows and the parts before counter at every reached recursive entry. -/
import CausalCalls

namespace PhysicalPagination

set_option linter.unusedVariables false in
def partsOffsetSafe (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St) (base : Nat)
    (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St) : Prop :=
  (text at').length = base + before ∧
  (match hm : trialWrap env region limit k isStart at' ((breaker at' before start).map (·.1)) with
  | .error e => True
  | .ok (.moved moved relaxed) =>
    partsOffsetSafe env region breaker items lastWanted follows hold base none relaxed isStart start before moved
  | .ok (.placed count placed relaxed) =>
    if (breaker at' before start).length ≤ count then
      if follows (checkWaits placed) || (breaker at' before start).isEmpty then True
      else if h1 : minimumFront isStart lastWanted k ≤ count - max lastWanted (max 1 relaxed.last) ∧ relaxed.all = false then
        if h2 : count - max lastWanted (max 1 relaxed.last) < limitRank limit (breaker at' before start).length then
          partsOffsetSafe env region breaker items lastWanted follows hold base (some (count - max lastWanted (max 1 relaxed.last)))
            k isStart start before at'
        else True
      else if h3 : empty at' = false then
        partsOffsetSafe env region breaker items lastWanted follows hold base none k isStart start before (moveCursor env region at')
      else True
    else if h4 : start < nextItem (breaker at' before start) count start ∧ start < items then
      if (breaker (moveCursor env region placed) (before + count) (nextItem (breaker at' before start) count start)).length
          < relaxed.last then
        if h5 : minimumFront isStart lastWanted k < count then
          if h6 : count - 1 < limitRank limit (breaker at' before start).length then
            partsOffsetSafe env region breaker items lastWanted follows hold base (some (count - 1)) k isStart start before at'
          else True
        else if h7 : empty at' = false then
          partsOffsetSafe env region breaker items lastWanted follows hold base none k isStart start before (moveCursor env region at')
        else
          partsOffsetSafe env region breaker items lastWanted follows hold base none relaxed false
            (nextItem (breaker at' before start) count start) (before + count) (moveCursor env region placed)
      else
        partsOffsetSafe env region breaker items lastWanted follows hold base none relaxed false
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


private theorem take_count {α : Type} : ∀ (n : Nat) (xs : List α), (xs.take n).length = min n xs.length
  | 0, xs => by simp [List.take]
  | n + 1, [] => by simp [List.take]
  | n + 1, _ :: xs => by simp [List.take, take_count n xs, Nat.succ_min_succ]

theorem root_adr0352_i5_parts_offset_entries (env : Env) (region : Region)
    (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St) (base : Nat) :
    ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St),
    (text at').length = base + before → partsOffsetSafe env region breaker items lastWanted follows hold base limit k isStart start before at' := by
  have key : ∀ m, ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St),
      (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) = m →
      (text at').length = base + before → partsOffsetSafe env region breaker items lastWanted follows hold base limit k isStart start before at' := by
    intro m
    induction m using lex4_wf.induction with
    | _ m ih =>
    intro limit k isStart start before at' hm0 ready
    subst hm0
    rw [partsOffsetSafe]
    refine ⟨ready, ?_⟩
    split
    · trivial
    · rename_i moved relaxed hm
      have dec : lex4lt (items - start, keepRank relaxed, rank moved, limitRank none (breaker moved before start).length)
          (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
        apply Prod.Lex.right
        cases I4_trialWrap_moved env region limit k isStart at' _ moved relaxed hm with
        | inl l => exact Prod.Lex.left _ _ l
        | inr e => rw [e.1]; exact Prod.Lex.right _ (Prod.Lex.left _ _ e.2)
      exact ih _ dec none relaxed isStart start before moved rfl (by have h := trialWrap_moved_step env region limit k isStart at' _ moved relaxed hm; have hlen := congrArg List.length h.1; simp only [List.length_append, List.length_nil, Nat.add_zero] at hlen; omega)
    · rename_i count placed relaxed hm
      have placedLength : (text placed).length = (text at').length + min count (breaker at' before start).length := by
        have h := trialWrap_placed_step env region limit k isStart at' _ count placed relaxed hm
        have hlen := congrArg List.length h.1
        simpa [lineIds, List.length_append, List.length_map, take_count] using hlen
      have again : ∀ limit' k' isStart' start' before' at'',
          lex4lt (items - start', keepRank k', rank at'', limitRank limit' (breaker at'' before' start').length)
            (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) →
          (text at'').length = base + before' → partsOffsetSafe env region breaker items lastWanted follows hold base limit' k' isStart' start' before' at'' := by
        intro limit' k' isStart' start' before' at'' dec hready
        exact ih _ dec limit' k' isStart' start' before' at'' rfl hready
      repeat' split
      all_goals first
        | trivial
        | (apply again <;> try assumption)
      all_goals first
        | exact ready
        | (have h := step_moveCursor env region at'; have hlen := congrArg List.length h.1; simp only [List.length_append, List.length_nil, Nat.add_zero] at hlen; omega)
        | (have h := step_moveCursor env region placed; have hlen := congrArg List.length h.1; simp only [List.length_append, List.length_nil, Nat.add_zero] at hlen; omega)
        | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right
           simp only [limitRank] at *; omega)
        | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
           exact I4_moveCursor_rank env region at' (Or.inl ‹empty at' = false›))
        | (apply Prod.Lex.left; omega)
  intro limit k isStart start before at' h
  exact key _ limit k isStart start before at' rfl h
/-- An actual entry, unlike an arbitrary state, has the offset relation. -/
theorem root_adr0352_i5_causal_breaker_ids_at_offset (m : CausalBoundary.Ms)
    (region : Region) (origin : Int) (cursor : St) (index start before base : Nat)
    (offset : (text cursor).length = base + before) :
    lineIds ((CausalBoundary.breakLines m.w (CausalBoundary.measure m index) region origin cursor start (CausalBoundary.chars m index)).map (·.1)) =
      ids (base + before) (CausalBoundary.breakLines m.w (CausalBoundary.measure m index) region origin cursor start (CausalBoundary.chars m index)).length := by
  rw [CausalBoundary.breakLines_ids, offset]

theorem root_adr0352_i5_initial_parts_offset_entries (env : Env) (region : Region)
    (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St)
    (limit : Option Nat) (k : Keep) (cursor : St) :
    partsOffsetSafe env region breaker items lastWanted follows hold (text cursor).length limit k true 0 0 cursor :=
  root_adr0352_i5_parts_offset_entries env region breaker items lastWanted follows hold _ limit k true 0 0 cursor (by omega)

end PhysicalPagination
