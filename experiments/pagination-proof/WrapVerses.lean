/- Root ADR 0352: the entries reached by causalFreeFlow.tryVerses,
   including prefixes whose next trial reports a failure. -/
import WrapCalls

namespace PhysicalPagination

/-- The entry condition along precisely the recursive calls of tryVerses.
    A failed trial still requires its input cursor to be ready. -/
def verseEntriesSafe (env : Env) (region : Region) (b : Beside) (cursor : St) (indices : List Nat) : Prop :=
  WrapReady region cursor ∧
  (match indices with
  | [] => True
  | index :: later =>
    match trialWrap env region none ⟨1, 1, false⟩ true cursor (b.compose cursor index) with
    | .error _ => True
    | .ok (.placed count placed _) =>
      if count = (b.compose cursor index).length ∧ placed.page = cursor.page ∧ placed.column = cursor.column then
        verseEntriesSafe env region b placed later
      else True
    | .ok (.moved _ _) => True)

/-- No restrictions on composition, the number of verses, or the trial's
    result are needed: a ready entry gives ready recursive entries. -/
theorem root_adr0352_i3_verse_entries_safe (env : Env) (region : Region) (b : Beside)
    (indices : List Nat) (cursor : St) (ready : WrapReady region cursor) :
    verseEntriesSafe env region b cursor indices := by
  induction indices generalizing cursor with
  | nil => exact ⟨ready, trivial⟩
  | cons index later ih =>
    rw [verseEntriesSafe]
    refine ⟨ready, ?_⟩
    split
    · trivial
    · rename_i count placed relaxed trial
      split
      · exact ih placed (ready.trial env none ⟨1, 1, false⟩ true _ _ trial)
      · trivial
    · trivial

/-- beginWrap establishes the condition for all recursive verse trials,
    without assuming the condition as a caller premise. -/
theorem root_adr0352_i3_all_initial_verse_entries_safe (env : Env) (st placed : St)
    (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env st ident extent = .ok (placed, region))
    (b : Beside) (indices : List Nat) : verseEntriesSafe env region b placed indices :=
  root_adr0352_i3_verse_entries_safe env region b indices placed
    (root_adr0352_i3_begin_wrap_ready env st placed ident extent region begun)

/-- Each committed snapshot returned by a successful trial run is ready,
    so selecting a legal stanza prefix cannot lose this entry invariant. -/
theorem root_adr0352_i3_verse_snapshots_ready (env : Env) (region : Region) (b : Beside)
    (indices : List Nat) (cursor : St) (trials : List St) (ready : WrapReady region cursor)
    (result : tryVerses env region b cursor indices = .ok trials) :
    ∀ snapshot ∈ trials, WrapReady region snapshot := by
  intro snapshot member
  apply ready.preserved
  exact tryVerses_get_rel env region b PreservesWrapCursor
    (fun a c => a.trans c)
    (fun limit k first st rows p h => by
      have advance := adv_trialWrap env region limit k first st rows p h
      cases p with
      | moved next relaxed => exact PreservesWrapCursor.ofAdvStep advance (trialWrap_moved_step env region limit k first st rows next relaxed h)
      | placed n next relaxed => exact PreservesWrapCursor.ofAdvStep advance (trialWrap_placed_step env region limit k first st rows n next relaxed h))
    indices cursor trials result snapshot member

/-- A snapshot selected from the successful verse trials supplies both
    wrap-side premises for the putLine comparison, without a new cursor
    premise at that call site. -/
theorem root_adr0352_i3_verse_snapshot_trial (env : Env) (pitch : 0 < env.pagePitch)
    (region : Region) (b : Beside) (indices : List Nat) (cursor : St) (trials : List St)
    (ready : WrapReady region cursor) (result : tryVerses env region b cursor indices = .ok trials)
    (snapshot : St) (member : snapshot ∈ trials) (limit : Option Nat) (k : Keep)
    (isStart : Bool) (rows : List Line) (fid : Nat) :
    trialWrapRest env region limit k isStart snapshot rows fid =
      trialWrapRestLine env region limit k isStart snapshot rows fid := by
  have held := root_adr0352_i3_verse_snapshots_ready env region b indices cursor trials ready result snapshot member
  exact root_adr0352_i3_trial_wrap_rest_put_line env pitch region limit k isStart snapshot rows fid held.1 held.nonempty

end PhysicalPagination
