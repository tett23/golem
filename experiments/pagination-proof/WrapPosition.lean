/- Root ADR 0352: the exclusion belongs to a column already reached.
   This discharges the next-column premise of trialWrapRest_putLine
   from a positional invariant, rather than assuming that premise. -/
import Physical
open PhysicalPagination

namespace PhysicalPagination

/-- A wrap is created at the cursor, never in a future column. -/
def RegionPast (region : Region) (st : St) : Prop :=
  match region with
  | none => True
  | some (p, c, _) => PLe (p, c) (pos st)

theorem RegionPast.advance {region : Region} {st next : St}
    (h : RegionPast region st) (advance : PLe (pos st) (pos next)) : RegionPast region next := by
  cases region with
  | none => trivial
  | some r => exact h.trans advance

theorem root_adr0352_i3_wrap_next_column_past_region (env : Env) (region : Region) (st : St)
    (past : RegionPast region st) : wrapEnd region (nextColumn env st) = 0 := by
  cases region with
  | none => rfl
  | some r =>
    obtain ⟨p, c, extent⟩ := r
    have later := past.lt_trans (nextColumn_lt env st)
    simp only [RegionPast, pos, PLe, PLt] at past later
    simp only [wrapEnd]
    split
    · rename_i same
      omega
    · rfl

theorem root_adr0352_i3_begin_wrap_region_past (env : Env) (st placed : St)
    (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env st ident extent = .ok (placed, region)) : RegionPast region placed := by
  unfold beginWrap at begun
  split at begun
  · cases begun
  · injection begun with pair
    cases pair
    have fields := checkWaits_fields (putSlot (fit env st extent) 0 (.wrapped ident))
    change PLe ((fit env st extent).page, (fit env st extent).column)
      ((checkWaits (putSlot (fit env st extent) 0 (.wrapped ident))).page,
       (checkWaits (putSlot (fit env st extent) 0 (.wrapped ident))).column)
    rw [fields.2.1, fields.2.2.1]
    exact PLe.refl _

/-- The next-column premise is automatic at the state beginWrap returns. -/
theorem root_adr0352_i3_begin_wrap_next_column_outside (env : Env) (st placed : St)
    (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env st ident extent = .ok (placed, region)) :
    wrapEnd region (nextColumn env placed) = 0 :=
  root_adr0352_i3_wrap_next_column_past_region env region placed
    (root_adr0352_i3_begin_wrap_region_past env st placed ident extent region begun)

theorem checkWaits_slots (st : St) : (checkWaits st).slots = st.slots := by
  have one (st : St) (w : Wait) : (checkWait st w).slots = st.slots := by
    unfold checkWait
    split
    · rfl
    · split <;> rfl
  have fold : ∀ (ws : List Wait) (st : St), (ws.foldl checkWait st).slots = st.slots := by
    intro ws
    induction ws with
    | nil => intro st; rfl
    | cons w ws ih => intro st; rw [List.foldl, ih, one]
  exact fold st.waits { st with waits := [] }

/-- The wrapped figure's slot makes the initial exclusion column nonempty. -/
theorem root_adr0352_i3_begin_wrap_nonempty (env : Env) (st placed : St)
    (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env st ident extent = .ok (placed, region)) : empty placed = false := by
  unfold beginWrap at begun
  split at begun
  · cases begun
  · injection begun with pair
    cases pair
    simp only [empty, checkWaits_slots, putSlot]
    cases (fit env st extent).slots <;> simp [List.isEmpty]

/-- Only the nonempty-column premise remains to identify putWrappedLine
    with putLine; absence from the next column follows from position. -/
theorem root_adr0352_i3_trial_wrap_rest_put_line (env : Env) (pitch : 0 < env.pagePitch)
    (region : Region) (limit : Option Nat) (keep : Keep) (start : Bool)
    (st : St) (rows : List Line) (fid : Nat) (past : RegionPast region st)
    (nonempty : 0 < wrapEnd region st → empty st = false) :
    trialWrapRest env region limit keep start st rows fid =
      trialWrapRestLine env region limit keep start st rows fid :=
  trialWrapRest_putLine env pitch region limit keep start st rows fid nonempty
    (root_adr0352_i3_wrap_next_column_past_region env region st past)

/-- Both premises of trialWrapRest_putLine follow at beginWrap's result. -/
theorem root_adr0352_i3_initial_trial_wrap_rest_put_line (env : Env) (pitch : 0 < env.pagePitch)
    (initial placed : St) (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env initial ident extent = .ok (placed, region))
    (limit : Option Nat) (keep : Keep) (start : Bool) (rows : List Line) (fid : Nat) :
    trialWrapRest env region limit keep start placed rows fid =
      trialWrapRestLine env region limit keep start placed rows fid :=
  root_adr0352_i3_trial_wrap_rest_put_line env pitch region limit keep start placed rows fid
    (root_adr0352_i3_begin_wrap_region_past env initial placed ident extent region begun)
    (fun _ => root_adr0352_i3_begin_wrap_nonempty env initial placed ident extent region begun)

/-- Every successful parts call preserves the positional invariant when
    its final hold leaves the position alone or advances it.  No
    assumption on line breaks, numbering or the number of retries is
    needed for this positional property. -/
theorem root_adr0352_i4_parts_preserve_region_position
    (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat))
    (items lastWanted : Nat) (follows : St → Bool) (hold : St → St)
    (holdForward : ∀ st, PLe (pos st) (pos (hold (checkWaits st))))
    (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' placed : St)
    (past : RegionPast region at')
    (result : parts env region breaker items lastWanted follows hold limit k isStart start before at' = .ok placed) :
    RegionPast region placed := by
  have forward := parts_rel env region breaker items lastWanted follows hold
    (fun a b => PLe (pos a) (pos b)) (fun _ => True)
    (fun a b => a.trans b)
    (fun limit k first st rows p h => (adv_trialWrap env region limit k first st rows p h).1)
    (fun st => (adv_moveCursor env region st).1)
    (fun st => ⟨holdForward st, trivial⟩)
    limit k isStart start before at' placed result
  exact past.advance forward.1

theorem waitForPrior_pos (u : Unmet) (required : Nat × Bool) (st : St) :
    pos (waitForPrior u required st) = pos st := by
  unfold waitForPrior
  split <;> rfl

/-- keepPhysicalNext only changes waiting controls, including when its
    requested lines and its lines-only flag depend on a probe result.
    Thus the actual hold form does not require a forwardness assumption. -/
theorem root_adr0352_i4_kept_parts_preserve_region_position
    (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat))
    (items lastWanted : Nat) (follows enabled : St → Bool) (span : Nat)
    (required : St → Nat × Bool)
    (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' placed : St)
    (past : RegionPast region at')
    (result : parts env region breaker items lastWanted follows
      (fun st => if enabled st then waitForPrior (.keepNext span) (required st) st else st)
      limit k isStart start before at' = .ok placed) : RegionPast region placed := by
  apply root_adr0352_i4_parts_preserve_region_position env region breaker items lastWanted follows
    (fun st => if enabled st then waitForPrior (.keepNext span) (required st) st else st)
    ?_ limit k isStart start before at' placed past result
  intro st
  have fields := checkWaits_fields st
  have same : pos (checkWaits st) = pos st := by
    unfold pos
    rw [fields.2.1, fields.2.2.1]
  dsimp only
  split
  · rw [waitForPrior_pos, same]
    exact PLe.refl _
  · rw [same]
    exact PLe.refl _

end PhysicalPagination
