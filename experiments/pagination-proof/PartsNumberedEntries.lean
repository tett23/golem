/- Root ADR 0352: local numbering at every reached parts entry, without a global hb over unreachable states. -/
import PartsOffsetEntries

namespace PhysicalPagination

set_option linter.unusedVariables false in
def partsNumberedEntriesSafe (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St) (base : Nat)
    (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St) : Prop :=
  lineIds ((breaker at' before start).map (·.1)) = ids (base + before) (breaker at' before start).length ∧
  (match hm : trialWrap env region limit k isStart at' ((breaker at' before start).map (·.1)) with
  | .error e => True
  | .ok (.moved moved relaxed) =>
    partsNumberedEntriesSafe env region breaker items lastWanted follows hold base none relaxed isStart start before moved
  | .ok (.placed count placed relaxed) =>
    if (breaker at' before start).length ≤ count then
      if follows (checkWaits placed) || (breaker at' before start).isEmpty then True
      else if h1 : minimumFront isStart lastWanted k ≤ count - max lastWanted (max 1 relaxed.last) ∧ relaxed.all = false then
        if h2 : count - max lastWanted (max 1 relaxed.last) < limitRank limit (breaker at' before start).length then
          partsNumberedEntriesSafe env region breaker items lastWanted follows hold base (some (count - max lastWanted (max 1 relaxed.last)))
            k isStart start before at'
        else True
      else if h3 : empty at' = false then
        partsNumberedEntriesSafe env region breaker items lastWanted follows hold base none k isStart start before (moveCursor env region at')
      else True
    else if h4 : start < nextItem (breaker at' before start) count start ∧ start < items then
      if (breaker (moveCursor env region placed) (before + count) (nextItem (breaker at' before start) count start)).length
          < relaxed.last then
        if h5 : minimumFront isStart lastWanted k < count then
          if h6 : count - 1 < limitRank limit (breaker at' before start).length then
            partsNumberedEntriesSafe env region breaker items lastWanted follows hold base (some (count - 1)) k isStart start before at'
          else True
        else if h7 : empty at' = false then
          partsNumberedEntriesSafe env region breaker items lastWanted follows hold base none k isStart start before (moveCursor env region at')
        else
          partsNumberedEntriesSafe env region breaker items lastWanted follows hold base none relaxed false
            (nextItem (breaker at' before start) count start) (before + count) (moveCursor env region placed)
      else
        partsNumberedEntriesSafe env region breaker items lastWanted follows hold base none relaxed false
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


theorem root_adr0352_i5_parts_numbered_of_offsets (env : Env) (region : Region)
    (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St) (base : Nat)
    (hb : ∀ at' before start, (text at').length = base + before →
      lineIds ((breaker at' before start).map (·.1)) = ids (base + before) (breaker at' before start).length) :
    ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St),
    partsOffsetSafe env region breaker items lastWanted follows hold base limit k isStart start before at' →
    partsNumberedEntriesSafe env region breaker items lastWanted follows hold base limit k isStart start before at' := by
  have key : ∀ m, ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St),
      (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) = m →
      partsOffsetSafe env region breaker items lastWanted follows hold base limit k isStart start before at' →
      partsNumberedEntriesSafe env region breaker items lastWanted follows hold base limit k isStart start before at' := by
    intro m
    induction m using lex4_wf.induction with
    | _ m ih =>
    intro limit k isStart start before at' hm0 safe
    subst hm0
    rw [partsOffsetSafe] at safe
    rw [partsNumberedEntriesSafe]
    refine ⟨hb at' before start safe.1, ?_⟩
    have trace := safe.2
    simp only [partsNumberedEntriesSafe.match_1, partsOffsetSafe.match_1] at trace ⊢
    generalize hm : trialWrap env region limit k isStart at' ((breaker at' before start).map (·.1)) = trial at trace ⊢
    cases trial with
    | error e => trivial
    | ok result =>
      cases result with
      | moved moved relaxed =>
        dsimp only at trace ⊢
        have dec : lex4lt (items - start, keepRank relaxed, rank moved, limitRank none (breaker moved before start).length)
            (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
          apply Prod.Lex.right
          cases I4_trialWrap_moved env region limit k isStart at' _ moved relaxed hm with
          | inl l => exact Prod.Lex.left _ _ l
          | inr e => rw [e.1]; exact Prod.Lex.right _ (Prod.Lex.left _ _ e.2)
        exact ih _ dec none relaxed isStart start before moved rfl (by simpa only using trace)
      | placed count placed relaxed =>
        dsimp only at trace ⊢
        have again : ∀ limit' k' isStart' start' before' at'',
            lex4lt (items - start', keepRank k', rank at'', limitRank limit' (breaker at'' before' start').length)
              (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) →
            partsOffsetSafe env region breaker items lastWanted follows hold base limit' k' isStart' start' before' at'' →
            partsNumberedEntriesSafe env region breaker items lastWanted follows hold base limit' k' isStart' start' before' at'' := by
          intro limit' k' isStart' start' before' at'' dec hsafe
          exact ih _ dec limit' k' isStart' start' before' at'' rfl hsafe
        repeat' split
        all_goals first
          | trivial
          | (apply again <;> try assumption)
        all_goals first
          | (simpa only [*] using trace)
          | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right
             simp only [limitRank] at *; omega)
          | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
             exact I4_moveCursor_rank env region at' (Or.inl ‹empty at' = false›))
          | (apply Prod.Lex.left; omega)
  intro limit k isStart start before at' safe
  exact key _ limit k isStart start before at' rfl safe

/-- The concrete breaker has the required numbering at every reached entry,
    including retries, moved cursors and continuations after consuming rows. -/
theorem root_adr0352_i5_causal_parts_numbered_entries (env : Env) (m : CausalBoundary.Ms)
    (region : Region) (origin : Int) (index lastWanted : Nat)
    (follows : St → Bool) (hold : St → St)
    (limit : Option Nat) (k : Keep) (cursor : St) :
    partsNumberedEntriesSafe env region
      (fun at' _ start => CausalBoundary.breakLines m.w (CausalBoundary.measure m index) region origin at' start (CausalBoundary.chars m index))
      (CausalBoundary.chars m index) lastWanted follows hold (text cursor).length limit k true 0 0 cursor := by
  apply root_adr0352_i5_parts_numbered_of_offsets
  · intro at' before start offset
    exact root_adr0352_i5_causal_breaker_ids_at_offset m region origin at' index start before _ offset
  · exact root_adr0352_i5_initial_parts_offset_entries _ _ _ _ _ _ _ _ _ _

end PhysicalPagination
