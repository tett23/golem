/- Root ADR 0352: the concrete stanza hold and display-row fallback
   preserve the cursor needed by subsequent wrapped paragraphs. -/
import CausalBoundary
import WrapCalls

namespace PhysicalPagination

theorem PreservesWrapCursor.trial_wrap (env : Env) (region : Region)
    (limit : Option Nat) (keep : Keep) (isStart : Bool) (cursor : St)
    (rows : List Line) (result : Part)
    (trial : trialWrap env region limit keep isStart cursor rows = .ok result) :
    PreservesWrapCursor cursor result.st := by
  have forward := adv_trialWrap env region limit keep isStart cursor rows result trial
  cases result with
  | moved next relaxed => exact PreservesWrapCursor.ofAdvStep forward (trialWrap_moved_step env region limit keep isStart cursor rows next relaxed trial)
  | placed count next relaxed => exact PreservesWrapCursor.ofAdvStep forward (trialWrap_placed_step env region limit keep isStart cursor rows count next relaxed trial)

/-- Discharge parts_rel for the actual wait-for-prior shape of keepPhysicalNext,
    without assuming that the breaker preserves line IDs or content. -/
theorem root_adr0352_i4_kept_parts_cursor (env : Env) (region : Region)
    (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows enabled : St → Bool) (span : Nat) (required : St → Nat × Bool)
    (limit : Option Nat) (keep : Keep) (isStart : Bool) (start before : Nat) (cursor out : St)
    (result : parts env region breaker items lastWanted follows
      (fun st => if enabled st then waitForPrior (.keepNext span) (required st) st else st)
      limit keep isStart start before cursor = .ok out) : PreservesWrapCursor cursor out := by
  exact (parts_rel env region breaker items lastWanted follows
    (fun st => if enabled st then waitForPrior (.keepNext span) (required st) st else st)
    PreservesWrapCursor (fun _ => True)
    (fun a b => a.trans b)
    (fun limit keep first st rows p h => PreservesWrapCursor.trial_wrap env region limit keep first st rows p h)
    (fun st => PreservesWrapCursor.ofAdvStep (adv_moveCursor env region st) (step_moveCursor env region st))
    (fun st => by
      dsimp only
      split
      · exact ⟨(PreservesWrapCursor.check_waits st).trans (PreservesWrapCursor.wait_for_prior _ _ _), trivial⟩
      · exact ⟨PreservesWrapCursor.check_waits st, trivial⟩)
    limit keep isStart start before cursor out result).1

/-- Instantiate the general stanza relation with the hold and fallback
    defined by the causal correspondence model, for any manuscript Ms.
    These are function definitions, not assumed preservation conclusions. -/
private theorem causal_stanza_rel (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (measure : Nat × Nat × Nat × Nat × Nat) :
    (∀ later keep isStart cursor indices out,
      (indices.length, keepRank keep, rank cursor, 1, 0) = measure →
      stanza env region (CausalBoundary.beside m region origin) (CausalBoundary.stanzaArgs env m job region origin)
        later keep isStart cursor indices = .ok out → PreservesWrapCursor cursor out ∧ True) ∧
    (∀ later keep isStart cursor indices trials count problems out,
      (indices.length, keepRank keep, rank cursor, 0, count) = measure →
      (∀ snapshot ∈ trials, PreservesWrapCursor cursor snapshot) →
      accept env region (CausalBoundary.beside m region origin) (CausalBoundary.stanzaArgs env m job region origin)
        later keep isStart cursor indices trials count problems = .ok out → PreservesWrapCursor cursor out ∧ True) := by
  apply stanza_accept_rel env region (CausalBoundary.beside m region origin)
    (CausalBoundary.stanzaArgs env m job region origin) PreservesWrapCursor (fun _ => True)
  · exact fun a b => a.trans b
  · exact fun limit keep first st rows p h => PreservesWrapCursor.trial_wrap env region limit keep first st rows p h
  · exact fun st => PreservesWrapCursor.ofAdvStep (adv_moveCursor env region st) (step_moveCursor env region st)
  · intro st problem
    exact ⟨PLe.refl _, fun _ => rfl, by simp [text, addUnmet]⟩
  · intro st problems
    exact ⟨PLe.refl _, fun _ => rfl, by simp [text]⟩
  · exact fun st => ⟨PreservesWrapCursor.check_waits st, trivial⟩
  · intro index requested linesOnly st
    exact ⟨(PreservesWrapCursor.check_waits st).trans (PreservesWrapCursor.wait_for_prior _ _ _), trivial⟩
  · intro index later cursor out result
    apply root_adr0352_i4_kept_parts_cursor env region
      (fun at' _ start => CausalBoundary.breakLines m.w (CausalBoundary.measure m index) region origin at' start (CausalBoundary.chars m index))
      (CausalBoundary.chars m index) 0 (fun _ => true)
      (fun _ => decide (0 < CausalBoundary.wantOf m index)) 0 (fun _ => (1, true))
      none defaultKeep true 0 0 cursor out
    simpa [CausalBoundary.stanzaArgs, CausalBoundary.paragraphAt, CausalBoundary.holdNext] using result

theorem root_adr0352_i4_causal_stanza_cursor (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (later : List Nat) (keep : Keep) (isStart : Bool)
    (cursor : St) (indices : List Nat) (out : St)
    (result : stanza env region (CausalBoundary.beside m region origin) (CausalBoundary.stanzaArgs env m job region origin)
      later keep isStart cursor indices = .ok out) : PreservesWrapCursor cursor out :=
  ((causal_stanza_rel env m job region origin _).1 later keep isStart cursor indices out rfl result).1

theorem root_adr0352_i4_causal_accept_cursor (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (later : List Nat) (keep : Keep) (isStart : Bool)
    (cursor : St) (indices : List Nat) (trials : List St) (count : Nat) (problems : List Unmet) (out : St)
    (tried : tryVerses env region (CausalBoundary.beside m region origin) cursor indices = .ok trials)
    (result : accept env region (CausalBoundary.beside m region origin) (CausalBoundary.stanzaArgs env m job region origin)
      later keep isStart cursor indices trials count problems = .ok out) : PreservesWrapCursor cursor out := by
  have snapshots := tryVerses_get_rel env region (CausalBoundary.beside m region origin) PreservesWrapCursor
    (fun a b => a.trans b)
    (fun limit keep first st rows p h => PreservesWrapCursor.trial_wrap env region limit keep first st rows p h)
    indices cursor trials tried
  exact ((causal_stanza_rel env m job region origin _).2 later keep isStart cursor indices trials count problems out rfl snapshots result).1

theorem root_adr0352_i3_causal_stanza_ready (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (later : List Nat) (keep : Keep) (isStart : Bool)
    (cursor : St) (indices : List Nat) (out : St) (ready : WrapReady region cursor)
    (result : stanza env region (CausalBoundary.beside m region origin) (CausalBoundary.stanzaArgs env m job region origin)
      later keep isStart cursor indices = .ok out) : WrapReady region out :=
  ready.preserved (root_adr0352_i4_causal_stanza_cursor env m job region origin later keep isStart cursor indices out result)

theorem root_adr0352_i3_causal_accept_ready (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (later : List Nat) (keep : Keep) (isStart : Bool)
    (cursor : St) (indices : List Nat) (trials : List St) (count : Nat) (problems : List Unmet) (out : St)
    (ready : WrapReady region cursor)
    (tried : tryVerses env region (CausalBoundary.beside m region origin) cursor indices = .ok trials)
    (result : accept env region (CausalBoundary.beside m region origin) (CausalBoundary.stanzaArgs env m job region origin)
      later keep isStart cursor indices trials count problems = .ok out) : WrapReady region out :=
  ready.preserved (root_adr0352_i4_causal_accept_cursor env m job region origin later keep isStart cursor indices trials count problems out tried result)

theorem root_adr0352_i3_initial_causal_stanza_ready (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (st cursor : St) (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env st ident extent = .ok (cursor, region))
    (origin : Int) (later : List Nat) (keep : Keep) (isStart : Bool) (indices : List Nat) (out : St)
    (result : stanza env region (CausalBoundary.beside m region origin) (CausalBoundary.stanzaArgs env m job region origin)
      later keep isStart cursor indices = .ok out) : WrapReady region out :=
  root_adr0352_i3_causal_stanza_ready env m job region origin later keep isStart cursor indices out
    (root_adr0352_i3_begin_wrap_ready env st cursor ident extent region begun) result

end PhysicalPagination
