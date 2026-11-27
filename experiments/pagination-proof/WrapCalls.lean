/- Root ADR 0352: every recursive parts cursor stays outside a past wrap
   or retains text in its active exclusion column. -/
import WrapPosition
open PhysicalPagination
namespace PhysicalPagination

/-- A region belongs to a column already reached; whenever it is active,
    that column has placed text (including the wrapped figure slot). -/
def WrapReady (region : Region) (st : St) : Prop :=
  RegionPast region st ∧ (0 < wrapEnd region st → 0 < (textSlots st.slots).length)

theorem Adv.same_done {st next : St} (h : Adv st next) (same : pos next = pos st) : next.done = st.done := by
  obtain ⟨_, new, done, positions⟩ := h
  have none : new = [] := by
    cases new with
    | nil => rfl
    | cons x xs =>
      have p := positions x (List.mem_cons_self _ _)
      rw [same] at p
      unfold PLe PLt at p
      omega
  simpa [none] using done


end PhysicalPagination

namespace PhysicalPagination

/-- A cursor does not go backwards, does not move closed text into an
    unchanged column, and does not discard already placed text. -/
def PreservesWrapCursor (a b : St) : Prop :=
  PLe (pos a) (pos b) ∧
  (pos b = pos a → (pagesText b.done.reverse).length = (pagesText a.done.reverse).length) ∧
  (text a).length ≤ (text b).length

theorem PreservesWrapCursor.trans {a b c : St}
    (h : PreservesWrapCursor a b) (h' : PreservesWrapCursor b c) : PreservesWrapCursor a c := by
  refine ⟨h.1.trans h'.1, ?_, Nat.le_trans h.2.2 h'.2.2⟩
  intro same
  have ab : pos b = pos a := by
    have x := h.1; have y := h'.1
    rw [same] at y
    unfold PLe at x y
    apply Prod.ext <;> omega
  rw [h'.2.1 (same.trans ab.symm), h.2.1 ab]

theorem PreservesWrapCursor.ofAdvStep {a b : St} {t g : List Nat}
    (advance : Adv a b) (step : Step a b t g) : PreservesWrapCursor a b := by
  refine ⟨advance.1, ?_, ?_⟩
  · intro same; rw [advance.same_done same]
  · have lengths := congrArg List.length step.1
    simp only [List.length_append] at lengths
    omega

theorem PreservesWrapCursor.check_waits (st : St) : PreservesWrapCursor st (checkWaits st) := by
  have fields := checkWaits_fields st
  have same : pos (checkWaits st) = pos st := by
    unfold pos; rw [fields.2.1, fields.2.2.1]
  have step := step_checkWaits st
  have lengths := congrArg List.length step.1
  simp only [List.length_append, List.length_nil, Nat.add_zero] at lengths
  refine ⟨by rw [same]; exact PLe.refl _, ?_, by omega⟩
  intro _
  simp only [text, List.length_append, checkWaits_slots] at lengths
  omega

theorem PreservesWrapCursor.wait_for_prior (u : Unmet) (req : Nat × Bool) (st : St) :
    PreservesWrapCursor st (waitForPrior u req st) := by
  apply PreservesWrapCursor.ofAdvStep ?_ (step_waitForPrior u req st)
  unfold waitForPrior
  split <;> exact Adv.same rfl rfl rfl

theorem WrapReady.preserved {region : Region} {st next : St}
    (ready : WrapReady region st) (preserve : PreservesWrapCursor st next) : WrapReady region next := by
  refine ⟨ready.1.advance preserve.1, ?_⟩
  intro active
  cases region with
  | none => simp [wrapEnd] at active
  | some r =>
    obtain ⟨p,c,extent⟩ := r
    have pp : p = next.page ∧ c = next.column := by
      change 0 < (if p = next.page ∧ c = next.column then extent else 0) at active
      split at active
      · assumption
      · omega
    have prior := ready.1
    simp only [RegionPast, PLe, pos] at prior
    have forward := preserve.1
    simp only [PLe, pos] at forward
    have page : next.page = st.page := by omega
    have column : next.column = st.column := by omega
    have same : pos next = pos st := by simp [pos, page, column]
    have initial : 0 < wrapEnd (some (p,c,extent)) st := by
      simpa [wrapEnd, page, column] using active
    have nonempty := ready.2 initial
    have closed := preserve.2.1 same
    have lengths := preserve.2.2
    simp only [text, List.length_append] at lengths
    omega

theorem root_adr0352_i3_kept_parts_output_ready (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat))
    (items lastWanted : Nat) (follows enabled : St → Bool) (span : Nat) (required : St → Nat × Bool)
    (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' placed : St)
    (ready : WrapReady region at')
    (result : parts env region breaker items lastWanted follows
      (fun st => if enabled st then waitForPrior (.keepNext span) (required st) st else st)
      limit k isStart start before at' = .ok placed) : WrapReady region placed := by
  have forward := parts_rel env region breaker items lastWanted follows
    (fun st => if enabled st then waitForPrior (.keepNext span) (required st) st else st)
    PreservesWrapCursor (fun _ => True)
    (fun a b => a.trans b)
    (fun limit k first st rows p h => by
      have adv := adv_trialWrap env region limit k first st rows p h
      cases p with
      | moved next relaxed => exact PreservesWrapCursor.ofAdvStep adv (trialWrap_moved_step env region limit k first st rows next relaxed h)
      | placed n next relaxed => exact PreservesWrapCursor.ofAdvStep adv (trialWrap_placed_step env region limit k first st rows n next relaxed h))
    (fun st => PreservesWrapCursor.ofAdvStep (adv_moveCursor env region st) (step_moveCursor env region st))
    (fun st => by
      dsimp only
      split
      · exact ⟨(PreservesWrapCursor.check_waits st).trans (PreservesWrapCursor.wait_for_prior _ _ _), trivial⟩
      · exact ⟨PreservesWrapCursor.check_waits st, trivial⟩)
    limit k isStart start before at' placed result
  exact ready.preserved forward.1

end PhysicalPagination

namespace PhysicalPagination
set_option linter.unusedVariables false in
/-- The entry invariant along exactly the recursion tree of parts.
    The harness compares its normalized branch structure with parts.
    The predicate also checks calls ending with an error. -/
def partsEntrySafe (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St)
    (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St) : Prop :=
  WrapReady region at' ∧
  (match hm : trialWrap env region limit k isStart at' ((breaker at' before start).map (·.1)) with
  | .error e => True
  | .ok (.moved moved relaxed) =>
    partsEntrySafe env region breaker items lastWanted follows hold none relaxed isStart start before moved
  | .ok (.placed count placed relaxed) =>
    if (breaker at' before start).length ≤ count then
      if follows (checkWaits placed) || (breaker at' before start).isEmpty then True
      else if h1 : minimumFront isStart lastWanted k ≤ count - max lastWanted (max 1 relaxed.last) ∧ relaxed.all = false then
        if h2 : count - max lastWanted (max 1 relaxed.last) < limitRank limit (breaker at' before start).length then
          partsEntrySafe env region breaker items lastWanted follows hold (some (count - max lastWanted (max 1 relaxed.last)))
            k isStart start before at'
        else True
      else if h3 : empty at' = false then
        partsEntrySafe env region breaker items lastWanted follows hold none k isStart start before (moveCursor env region at')
      else True
    else if h4 : start < nextItem (breaker at' before start) count start ∧ start < items then
      if (breaker (moveCursor env region placed) (before + count) (nextItem (breaker at' before start) count start)).length
          < relaxed.last then
        if h5 : minimumFront isStart lastWanted k < count then
          if h6 : count - 1 < limitRank limit (breaker at' before start).length then
            partsEntrySafe env region breaker items lastWanted follows hold (some (count - 1)) k isStart start before at'
          else True
        else if h7 : empty at' = false then
          partsEntrySafe env region breaker items lastWanted follows hold none k isStart start before (moveCursor env region at')
        else
          partsEntrySafe env region breaker items lastWanted follows hold none relaxed false
            (nextItem (breaker at' before start) count start) (before + count) (moveCursor env region placed)
      else
        partsEntrySafe env region breaker items lastWanted follows hold none relaxed false
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


end PhysicalPagination
namespace PhysicalPagination

theorem WrapReady.move_cursor (env : Env) {region : Region} {st : St}
    (ready : WrapReady region st) : WrapReady region (moveCursor env region st) :=
  ready.preserved (PreservesWrapCursor.ofAdvStep (adv_moveCursor env region st) (step_moveCursor env region st))

theorem WrapReady.trial (env : Env) {region : Region} (limit : Option Nat) (k : Keep) (start : Bool)
    {st : St} (rows : List Line) (result : Part) (ready : WrapReady region st)
    (h : trialWrap env region limit k start st rows = .ok result) : WrapReady region result.st := by
  have adv := adv_trialWrap env region limit k start st rows result h
  cases result with
  | moved next relaxed => exact ready.preserved (PreservesWrapCursor.ofAdvStep adv (trialWrap_moved_step env region limit k start st rows next relaxed h))
  | placed n next relaxed => exact ready.preserved (PreservesWrapCursor.ofAdvStep adv (trialWrap_placed_step env region limit k start st rows n next relaxed h))

theorem root_adr0352_i3_parts_entry_safe (env : Env) (region : Region)
    (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St) :
    ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St),
    WrapReady region at' → partsEntrySafe env region breaker items lastWanted follows hold limit k isStart start before at' := by
  have key : ∀ m, ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St),
      (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) = m →
      WrapReady region at' → partsEntrySafe env region breaker items lastWanted follows hold limit k isStart start before at' := by
    intro m
    induction m using lex4_wf.induction with
    | _ m ih =>
    intro limit k isStart start before at' hm0 ready
    subst hm0
    rw [partsEntrySafe]
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
      exact ih _ dec none relaxed isStart start before moved rfl (ready.trial env limit k isStart _ _ hm)
    · rename_i count placed relaxed hm
      have placedReady := ready.trial env limit k isStart _ _ hm
      have again : ∀ limit' k' isStart' start' before' at'',
          lex4lt (items - start', keepRank k', rank at'', limitRank limit' (breaker at'' before' start').length)
            (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) →
          WrapReady region at'' → partsEntrySafe env region breaker items lastWanted follows hold limit' k' isStart' start' before' at'' := by
        intro limit' k' isStart' start' before' at'' dec hready
        exact ih _ dec limit' k' isStart' start' before' at'' rfl hready
      repeat' split
      all_goals first
        | trivial
        | (apply again <;> try assumption)
      all_goals first
        | exact ready
        | exact ready.move_cursor env
        | exact placedReady.move_cursor env
        | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right
           simp only [limitRank] at *; omega)
        | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
           exact I4_moveCursor_rank env region at' (Or.inl ‹empty at' = false›))
        | (apply Prod.Lex.left; omega)
  intro limit k isStart start before at' h
  exact key _ limit k isStart start before at' rfl h
end PhysicalPagination
namespace PhysicalPagination

theorem root_adr0352_i3_begin_wrap_ready (env : Env) (st placed : St)
    (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env st ident extent = .ok (placed, region)) : WrapReady region placed := by
  refine ⟨root_adr0352_i3_begin_wrap_region_past env st placed ident extent region begun, ?_⟩
  unfold beginWrap at begun
  split at begun
  · cases begun
  · injection begun with pair
    cases pair
    intro _
    simp only [checkWaits_slots, putSlot, textSlots_append, textSlots, List.length_append, List.length_cons, List.length_nil]
    omega

theorem WrapReady.nonempty {region : Region} {st : St} (ready : WrapReady region st)
    (active : 0 < wrapEnd region st) : empty st = false := by
  have positive := ready.2 active
  cases h : st.slots with
  | nil => simp [h, textSlots] at positive
  | cons slot rest => simp [empty, h, List.isEmpty]

theorem root_adr0352_i3_all_initial_parts_entries_safe (env : Env) (st placed : St)
    (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env st ident extent = .ok (placed, region))
    (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St)
    (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) :
    partsEntrySafe env region breaker items lastWanted follows hold limit k isStart start before placed :=
  root_adr0352_i3_parts_entry_safe env region breaker items lastWanted follows hold limit k isStart start before placed
    (root_adr0352_i3_begin_wrap_ready env st placed ident extent region begun)

theorem root_adr0352_i3_safe_parts_entry_trial (env : Env) (pitch : 0 < env.pagePitch) (region : Region)
    (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St)
    (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (st : St)
    (safe : partsEntrySafe env region breaker items lastWanted follows hold limit k isStart start before st)
    (rows : List Line) (fid : Nat) :
    trialWrapRest env region limit k isStart st rows fid = trialWrapRestLine env region limit k isStart st rows fid := by
  have ready : WrapReady region st := by rw [partsEntrySafe] at safe; exact safe.1
  exact root_adr0352_i3_trial_wrap_rest_put_line env pitch region limit k isStart st rows fid ready.1 ready.nonempty
end PhysicalPagination
