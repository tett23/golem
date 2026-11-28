/- Root ADR 0352: the local reached-entry guard proves ordered output without a numbering premise on all states. -/
import PartsNumberedEntries

namespace PhysicalPagination

theorem root_adr0352_i5_parts_lines_of_entries (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St) (base : Nat)
    (hh : ∀ s, Step s (hold s) [] []) :
    ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St) (s : St),
    partsNumberedEntriesSafe env region breaker items lastWanted follows hold base limit k isStart start before at' →
    parts env region breaker items lastWanted follows hold limit k isStart start before at' = .ok s →
    ∃ n, Step at' s (ids (base + before) n) [] := by
  have key : ∀ m, ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St),
      (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) = m → ∀ s,
      partsNumberedEntriesSafe env region breaker items lastWanted follows hold base limit k isStart start before at' →
      parts env region breaker items lastWanted follows hold limit k isStart start before at' = .ok s →
      ∃ n, Step at' s (ids (base + before) n) [] := by
    intro m
    induction m using lex4_wf.induction with
    | _ m ih =>
    intro limit k isStart start before at' hm0 s numbered h
    subst hm0
    rw [partsNumberedEntriesSafe] at numbered
    have currentIds := numbered.1
    have trace := numbered.2
    rw [parts] at h
    try simp only [partsNumberedEntriesSafe.match_1] at trace h
    generalize hm : trialWrap env region limit k isStart at' ((breaker at' before start).map (·.1)) = trial at trace h
    cases trial with
    | error e => cases h
    | ok result =>
      cases result with
      | moved moved relaxed =>
        dsimp only at h trace
        have a := trialWrap_moved_step env region limit k isStart at' _ moved relaxed hm
        have dec : lex4lt (items - start, keepRank relaxed, rank moved, limitRank none (breaker moved before start).length)
            (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
          apply Prod.Lex.right
          cases I4_trialWrap_moved env region limit k isStart at' _ moved relaxed hm with
          | inl l => exact Prod.Lex.left _ _ l
          | inr e => rw [e.1]; exact Prod.Lex.right _ (Prod.Lex.left _ _ e.2)
        obtain ⟨n, b⟩ := ih _ dec none relaxed isStart start before moved rfl s trace h
        exact ⟨n, by simpa using a.trans b⟩
      | placed count placed relaxed =>
        dsimp only at h trace
        have a := trialWrap_placed_step env region limit k isStart at' _ count placed relaxed hm
        rw [lineIds_take, currentIds, ids_take] at a
        have done : Step at' (hold (checkWaits placed)) (ids (base + before) (min count (breaker at' before start).length)) [] := by
          simpa using (a.trans (step_checkWaits placed)).trans (hh _)
        have movePart : ∀ s, empty at' = false →
            partsNumberedEntriesSafe env region breaker items lastWanted follows hold base none k isStart start before (moveCursor env region at') →
            parts env region breaker items lastWanted follows hold none k isStart start before (moveCursor env region at') = .ok s →
            ∃ n, Step at' s (ids (base + before) n) [] := by
          intro s e3 subtrace e
          have dec : lex4lt (items - start, keepRank k, rank (moveCursor env region at'),
              limitRank none (breaker (moveCursor env region at') before start).length)
              (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
            apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
            exact I4_moveCursor_rank env region at' (Or.inl e3)
          obtain ⟨n, b⟩ := ih _ dec none k isStart start before _ rfl s subtrace e
          exact ⟨n, by simpa using (step_moveCursor env region at').trans b⟩
        have retry : ∀ s n, n < limitRank limit (breaker at' before start).length →
            partsNumberedEntriesSafe env region breaker items lastWanted follows hold base (some n) k isStart start before at' →
            parts env region breaker items lastWanted follows hold (some n) k isStart start before at' = .ok s →
            ∃ n, Step at' s (ids (base + before) n) [] := by
          intro s n hn subtrace e
          have dec : lex4lt (items - start, keepRank k, rank at', limitRank (some n) (breaker at' before start).length)
              (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
            apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; exact hn
          exact ih _ dec (some n) k isStart start before at' rfl s subtrace e
        split at h
        · split at h
          · injection h with h; subst h; exact ⟨_, done⟩
          · split at h
            · split at h
              · rename_i h2; exact retry s _ h2 (by simpa only [*] using trace) h
              · cases h
            · split at h
              · rename_i h3; exact movePart s h3 (by simpa only [*] using trace) h
              · injection h with h; subst h; exact ⟨_, done⟩
        · rename_i full
          have mc : min count (breaker at' before start).length = count := by omega
          rw [mc] at a
          split at h
          · rename_i h4
            have go : ∀ s,
                  partsNumberedEntriesSafe env region breaker items lastWanted follows hold base none relaxed false
                    (nextItem (breaker at' before start) count start) (before + count) (moveCursor env region placed) →
                  parts env region breaker items lastWanted follows hold none relaxed false
                (nextItem (breaker at' before start) count start) (before + count) (moveCursor env region placed) = .ok s →
                ∃ n, Step at' s (ids (base + before) n) [] := by
              intro s subtrace e
              have dec : lex4lt (items - nextItem (breaker at' before start) count start, keepRank relaxed,
                  rank (moveCursor env region placed), limitRank none (breaker (moveCursor env region placed) (before + count)
                    (nextItem (breaker at' before start) count start)).length)
                  (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
                apply Prod.Lex.left; obtain ⟨_, _⟩ := h4; omega
              obtain ⟨n, b⟩ := ih _ dec none relaxed false _ (before + count) _ rfl s subtrace e
              refine ⟨count + n, ?_⟩
              have c := (a.trans (step_moveCursor env region placed)).trans b
              rw [← ids_append, Nat.add_assoc]; simpa using c
            split at h
            · split at h
              · split at h
                · rename_i h6; exact retry s _ h6 (by simpa only [*] using trace) h
                · cases h
              · split at h
                · rename_i h7; exact movePart s h7 (by simpa only [*] using trace) h
                · exact go s (by simpa only [*] using trace) h
            · exact go s (by simpa only [*] using trace) h
          · cases h
  intro limit k isStart start before at' s numbered h
  exact key _ limit k isStart start before at' rfl s numbered h


/-- The concrete paragraph caller derives both the reached-entry numbering
    and the empty hold step. The success condition is the modeled call itself. -/
theorem root_adr0352_i5_causal_paragraph_numbered_output (env : Env) (m : CausalBoundary.Ms)
    (job : Nat) (region : Region) (origin : Int) (index : Nat) (later : List Nat)
    (k : Keep) (lastWanted wanted : Nat) (cursor finished : St)
    (success : CausalBoundary.paragraphAt env m job region origin index later k lastWanted wanted cursor = .ok finished) :
    ∃ count, Step cursor finished (ids (text cursor).length count) [] := by
  unfold CausalBoundary.paragraphAt at success
  apply root_adr0352_i5_parts_lines_of_entries _ _ _ _ _ _ _ (text cursor).length ?_ none k true 0 0 cursor finished ?_ success
  · intro st
    dsimp only
    split
    · exact CausalBoundary.step_holdNext _ _ st
    · exact Step.refl st
  · exact root_adr0352_i5_causal_parts_numbered_entries _ _ _ _ _ _ _ _ _ _ _


/-- Small direct cases include empty content, a full column, and a continuation
    after consuming rows, with and without an already placed prefix. -/
def numberedOutputBoundary (capacity chars : Nat) (placedPrefix : Bool) : Bool :=
  let env := CausalBoundary.env capacity
  let cursor := if placedPrefix then putSlot (initial env) CausalBoundary.pitch (.line 0) else initial env
  let m : CausalBoundary.Ms := ⟨1, .column, [.para none chars], []⟩
  match CausalBoundary.paragraphAt env m 0 none 0 0 [] defaultKeep 0 0 cursor with
  | .error (.lineTooTall ident) => decide (capacity = 1 ∧ 0 < chars) && ident == (if placedPrefix then 1 else 0)
  | .error _ => false
  | .ok finished =>
    !(decide (capacity = 1 ∧ 0 < chars)) &&
      text finished == List.range ((if placedPrefix then 1 else 0) + (chars + 11) / 12) && figs finished == []

/-- This executable check is finite; the two theorems above carry the general proof. -/
def numberedOutputBoundaries : Bool :=
  [1, 2].all fun capacity => [0, 1, 12, 13, 24, 25].all fun chars =>
    [false, true].all fun placedPrefix => numberedOutputBoundary capacity chars placedPrefix

#eval numberedOutputBoundaries

end PhysicalPagination
