/-
Root ADR 0352: the premise `drainOk` of `drainCarry` in the free placement
(Physical.lean) holds at every state `paginate` reaches.

`Inv` asks every figure waiting to fit in an empty column, and the notes
carried on to be none unless a line of a note fits below the separator in
an empty column (`CF`).  Every function of the free placement keeps `Inv`
when the notes it reads are none or `CF` holds (`R`, in the shape of `Rel`
of PhysicalNotes.lean); a figure is sent on only after `placeFlow` has
checked its extent against the capacity.  `Inv` gives `drainOk`, and
`nextColumn` keeps it, so the last `drainCarry` of `paginate` leaves no
figure waiting and no note carried on (`I4_paginate_drained`).
-/
import PhysicalNotes

namespace PhysicalPagination
namespace Drain

open Notes

/-- A line of a note fits below the separator in an empty column. -/
def CF (env : Env) : Prop := 0 < env.pagePitch ∧ env.separator + env.pagePitch ≤ env.capacity

/-- The figures waiting fit in an empty column, and notes are carried on
    only when a line of a note fits in an empty column. -/
def Inv (env : Env) (st : St) : Prop :=
  (∀ w ∈ st.deferred, Waiting.fits env.capacity w) ∧ (st.carry = [] ∨ CF env)

/-- From `st` to `s`, `Inv` is kept. -/
def K (env : Env) (st s : St) : Prop := Inv env st → Inv env s

/-- From `st` to `s`, reading the notes `X`, `Inv` is kept when `X` is
    empty or a line of a note fits in an empty column. -/
def R (env : Env) (st s : St) (X : List Note) : Prop := (X = [] ∨ CF env) → Inv env st → Inv env s

theorem K.trans {env : Env} {a b c : St} (h1 : K env b c) (h2 : K env a b) : K env a c := fun i => h1 (h2 i)

theorem K.of {env : Env} {a b : St} (hd : ∀ w ∈ b.deferred, w ∈ a.deferred) (hc : a.carry = [] → b.carry = []) :
    K env a b := fun ⟨d, c⟩ =>
  ⟨fun w m => d w (hd w m), by rcases c with c | c; exact Or.inl (hc c); exact Or.inr c⟩

theorem K.same {env : Env} {a b : St} (hd : b.deferred = a.deferred) (hc : b.carry = a.carry) : K env a b :=
  K.of (fun w m => by rw [hd] at m; exact m) (fun c => by rw [hc]; exact c)

theorem R.refl {env : Env} (st : St) : R env st st [] := fun _ i => i

theorem R.trans {env : Env} {a b c : St} {X1 X2 : List Note} (h1 : R env a b X1) (h2 : R env b c X2) :
    R env a c (X1 ++ X2) := fun x i => by
  rcases x with x | x
  · rw [List.append_eq_nil] at x; exact h2 (Or.inl x.2) (h1 (Or.inl x.1) i)
  · exact h2 (Or.inr x) (h1 (Or.inr x) i)

theorem R.congr {env : Env} {st s : St} {X X' : List Note} (e : X = X') (h : R env st s X) : R env st s X' := e ▸ h

theorem R.pre {env : Env} {a b c : St} {X : List Note} (e : K env a b) (h : R env b c X) : R env a c X :=
  fun x i => h x (e i)

theorem R.post {env : Env} {a b c : St} {X : List Note} (h : R env a b X) (e : K env b c) : R env a c X :=
  fun x i => e (h x i)

theorem R.same {env : Env} {a b : St} (e : K env a b) : R env a b [] := fun _ i => e i

theorem R.tr {env : Env} {a b c : St} {X1 X2 X : List Note} (h1 : R env a b X1) (h2 : R env b c X2)
    (e : X1 ++ X2 = X) : R env a c X := e ▸ h1.trans h2

theorem R.ofEnv {env env' : Env} {a b : St} {X : List Note} (hc : env'.capacity = env.capacity)
    (hp : env'.pagePitch = env.pagePitch) (hs : env'.separator = env.separator) (h : R env' a b X) : R env a b X := by
  unfold R Inv CF at *
  rw [hc, hp, hs] at h
  exact h

theorem R.via {env : Env} {a b c : St} {X : List Note} (h : R env b c X) (e : K env a b) : R env a c X := R.pre e h

/-! ## The operations that move to a new column keep `Inv` -/

theorem dk_close (env : Env) (st : St) : K env st (close env st) := by
  obtain ⟨a, b, _⟩ := close_fields env st
  exact K.same a b

theorem dk_fresh (env : Env) (tp : Bool) (st : St) : K env st (fresh env tp st) := by
  obtain ⟨_, _, _, _, a, b, _⟩ := fresh_fields env tp st
  exact K.same a b

theorem dk_opened (env : Env) (tp : Bool) (st : St) : K env st (opened env tp st) := by
  obtain ⟨_, _, _, _, _, b, _, d⟩ := opened_fields env tp st
  exact K.of d (fun c => by rw [b]; exact c)

theorem dk_placeDeferred (env : Env) (st : St) : K env st (placeDeferred env st) := by
  obtain ⟨_, _, c, d⟩ := pdg_step env st st.deferred
  exact K.of d (fun e => by rw [placeDeferred, c]; exact e)

theorem dk_carryInto (env : Env) (st : St) : K env st (carryInto env st) := by
  obtain ⟨_, _, _, _, _, _, _, d, _⟩ := carryInto_fields env st
  refine K.of (fun w m => by rw [d] at m; exact m) (fun c => ?_)
  unfold carryInto
  split
  · exact c
  · rename_i ne; rw [c] at ne; exact absurd rfl ne

theorem dk_nextColumn (env : Env) (st : St) : K env st (nextColumn env st) :=
  ((dk_carryInto env _).trans (dk_placeDeferred env _)).trans (dk_opened env false st)

theorem dk_nextPage (env : Env) (st : St) : K env st (nextPage env st) :=
  ((dk_carryInto env _).trans (dk_placeDeferred env _)).trans (dk_opened env true st)

theorem dk_drainCarried (env : Env) (st : St) : K env st (drainCarried env st) := by
  obtain ⟨_, _, d⟩ := drainCarried_fields env st
  refine K.of (fun w m => by rw [d] at m; exact m) (fun c => ?_)
  unfold drainCarried; dsimp only; rw [if_pos (Or.inl (by rw [c]; rfl))]; exact c

theorem dk_fit (env : Env) (st : St) (a : Int) : K env st (fit env st a) := by
  unfold fit
  repeat' split
  all_goals first
    | exact id
    | exact dk_nextColumn env st
    | exact (dk_nextColumn env st : K env st _)

set_option linter.unusedVariables false in
theorem dk_drainCarry (env : Env) (st : St) : K env st (drainCarry env st) := by
  rw [drainCarry]
  split
  · rename_i h
    have dec := I4_drain_rank env st ⟨Or.inl h.1, h.2⟩
    exact (dk_drainCarry env (nextColumn env st)).trans (dk_nextColumn env st)
  · exact id
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

set_option linter.unusedVariables false in
theorem dk_seek (env : Env) (p : St → Bool) (st : St) : K env st (seek env p st) := by
  rw [seek]
  split
  · exact id
  · split
    · rename_i h
      have dec := I4_drain_rank env st ⟨seek_cond st h.2, h.1⟩
      exact (dk_seek env p (nextColumn env st)).trans (dk_nextColumn env st)
    · exact dk_nextColumn env st
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem dk_parityStart (env : Env) (accept : Nat → Bool) (st : St) :
    K env st (parityStart env accept st) := by
  have c : K env st (if empty (drainCarry env st) ∧ (drainCarry env st).column = 0 then drainCarry env st
      else nextPage env (drainCarry env st)) := by
    split
    · exact dk_drainCarry env st
    · exact (dk_nextPage env _).trans (dk_drainCarry env st)
  unfold parityStart
  dsimp only
  generalize (if empty (drainCarry env st) ∧ (drainCarry env st).column = 0 then drainCarry env st
      else nextPage env (drainCarry env st)) = nx at c
  split
  · exact c
  · split
    · exact fun i => c i
    · exact (dk_nextPage env nx).trans c

theorem dk_breakPage (env : Env) (st : St) : K env st (breakPage env st) := by
  unfold breakPage; split
  · exact id
  · exact dk_nextPage env st

theorem dk_breakAt (env : Env) (k : BreakKind) (st : St) : K env st (breakAt env k st) := by
  cases k <;> unfold breakAt <;> dsimp only
  · split
    · exact dk_nextColumn env st
    · exact dk_breakPage env st
  · exact dk_breakPage env st
  · exact dk_parityStart env _ st
  · exact dk_parityStart env _ st

theorem dk_sectionStart (env : Env) (k : BreakKind) (st : St) : K env st (sectionStart env k st) := by
  have a := dk_drainCarry env st
  unfold sectionStart
  cases k <;> dsimp only
  · split
    · exact a
    · exact (dk_breakAt env _ _).trans a
  · split
    · exact a
    · exact (dk_breakAt env _ _).trans a
  · exact (dk_breakAt env _ _).trans a
  · exact (dk_breakAt env _ _).trans a

theorem dk_switchColumns (env : Env) (cols : Nat) (st : St) : K env st (switchColumns env cols st) := by
  have a := dk_drainCarry env st
  unfold switchColumns
  dsimp only
  split
  · exact (K.same (close_fields env _).1 (close_fields env _).2.1 : K env (drainCarry env st) _).trans a
  · exact (dk_nextPage env (drainCarry env st) : K env _ (nextPage env (drainCarry env st))).trans a

theorem dk_restoreColumns (env : Env) (st : St) : K env st (restoreColumns env st) :=
  (dk_nextPage env st : K env st (nextPage env st))

set_option linter.unusedVariables false in
theorem dk_judgeNeed (env : Env) (b : Int) (st : St) : K env st (judgeNeed env b st) := by
  rw [judgeNeed]
  split
  · exact id
  · split
    · rename_i h
      have dec := I4_nextColumn_rank env st (Or.inr h.2)
      exact (dk_judgeNeed env b (nextColumn env st)).trans (dk_nextColumn env st)
    · split
      · exact id
      · rename_i h
        have dec := I4_nextColumn_rank env st (Or.inl (by simpa using h))
        exact (dk_judgeNeed env b (nextColumn env st)).trans (dk_nextColumn env st)
termination_by rank st
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem dk_checkWait {env : Env} (acc : St) (w : Wait) : K env acc (checkWait acc w) := by
  unfold checkWait
  split
  · exact id
  · split
    · exact id
    · exact id

theorem dk_checkWaits {env : Env} (st : St) : K env st (checkWaits st) := by
  unfold checkWaits
  have : ∀ (ws : List Wait) (a : St), K env a (ws.foldl checkWait a) := by
    intro ws
    induction ws with
    | nil => intro a; exact id
    | cons w ws ih => intro a; simp only [List.foldl]; exact (ih _).trans (dk_checkWait a w)
  exact (this _ _).trans id

theorem dk_waitForPrior {env : Env} (u : Unmet) (q : Nat × Bool) (st : St) : K env st (waitForPrior u q st) := by
  unfold waitForPrior; split <;> exact id

theorem dk_flush (env : Env) (st : St) : K env st (flushPendingRule env st) := by
  unfold flushPendingRule; split <;> exact id

theorem dk_keepFrom (env : Env) (st : St) (b : Bool) : K env st (keepFrom env st b) := by
  unfold keepFrom; split
  · exact dk_nextColumn env st
  · exact id

theorem dk_headingState (env : Env) (st : St) (recto b : Bool) : K env st (headingStateOf env st recto b) := by
  unfold headingStateOf; split
  · exact dk_parityStart env _ st
  · exact dk_keepFrom env st b

theorem dk_keepFollowing (inner : Inner) (env : Env) (hd : Bool) (st : St) (extent : Int) (ls : List Line)
    (later : List Flow) : K env st (keepFollowing inner env hd st extent ls later) := dk_keepFrom env st _

theorem dk_afterFront (env : Env) (st : St) : K env st (afterFront env st) := by
  unfold afterFront; split
  · exact id
  · exact dk_nextColumn env st

/-- A figure sent on that fits in an empty column keeps `Inv`. -/
theorem dk_send {env : Env} (w : Waiting) (ok : Waiting.fits env.capacity w) (st s : St)
    (hd : s.deferred = st.deferred ++ [w]) (hc : s.carry = st.carry) : K env st s := by
  intro ⟨d, c⟩
  refine ⟨fun x m => ?_, by rw [hc]; exact c⟩
  rw [hd] at m
  rcases mem_app m with m | m
  · exact d x m
  · cases m with
    | head => exact ok
    | tail _ m => cases m

/-! ## Lines -/

theorem splitNotes_nil' (n : Nat) : splitNotes n [] = ([], []) := by cases n <;> rfl

theorem dr_putLine (env : Env) (allow : Bool) (st s : St) (l : Line)
    (h : putLineWithReserve allow env st l = .ok s) : R env st s l.notes := by
  unfold putLineWithReserve at h
  split at h
  · cases h
  · split at h
    · rename_i c
      split at h
      · cases h
      · rename_i e
        exfalso
        have : noteLines l = 0 := by simp [noteLines, e]
        omega
    · injection h with h
      subst h
      intro x ⟨d, c⟩
      refine ⟨fun w m => d w m, ?_⟩
      rcases x with x | x
      · rcases c with c | c
        · left
          show st.carry ++ (lineNotes env st l).2 = []
          rw [c]; unfold lineNotes; rw [x, splitNotes_nil']; rfl
        · exact Or.inr c
      · exact Or.inr x

theorem dr_putLines (env : Env) (allow : Bool) (st s : St) (ls : List Line)
    (h : putLines allow env st ls = .ok s) : R env st s (notesOf ls) := by
  induction ls generalizing st with
  | nil => simp only [putLines, Except.ok.injEq] at h; subst h; exact R.refl _
  | cons l ls ih =>
    unfold putLines at h
    split at h
    · cases h
    · rename_i s1 e
      exact R.tr (dr_putLine env allow st s1 l e) (ih s1 h) rfl

theorem dr_putLinesKeeping (env : Env) (allow : Bool) (adj after : Int) (st s : St) (ls : List Line)
    (h : putLinesKeeping allow env adj after st ls = .ok s) : R env st s (notesOf ls) := by
  induction ls generalizing st with
  | nil => simp only [putLinesKeeping, Except.ok.injEq] at h; subst h; exact R.refl _
  | cons l ls ih =>
    unfold putLinesKeeping at h
    split at h
    · cases h
    · rename_i s1 e
      exact R.tr (R.pre (a := st) id (dr_putLine env allow { st with adjust := adj - (sumPitch env ls + after) } s1 l e)) (ih s1 h) rfl

theorem trialRest_moved_nm (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (fid : Nat)
    (next : St) (r : Keep) (h : trialRest env k start st rows fid = .ok (.moved next r)) :
    K env st next := by
  obtain ⟨_, n, _⟩ := trialRest_moved env k start st rows fid next r h
  rw [n]; exact dk_nextColumn env st

theorem trialRest_placed_rel (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (fid : Nat)
    (c : Nat) (next : St) (r : Keep) (h : trialRest env k start st rows fid = .ok (.placed c next r)) :
    R env st next (notesOf (rows.take c)) := by
  unfold trialRest at h
  dsimp only at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · rename_i placed e
      injection h with h; injection h with h1 h2 _
      subst h1; subst h2
      exact R.pre (dk_fit env st _) (R.post (dr_putLines env false _ placed _ e) id)

theorem trial_moved_nm (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line)
    (next : St) (r : Keep) (h : trial env k start st rows = .ok (.moved next r)) : K env st next := by
  unfold trial at h
  split at h
  · cases h
  unfold trialFrom at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · split at h
      · split at h
        · have := trialRest_moved_nm env _ start _ _ _ next r h; exact this
        · injection h with h; injection h with h1 _; subst h1; exact dk_nextColumn env st
      · exact trialRest_moved_nm env _ start _ _ _ next r h

theorem trial_placed_rel (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line)
    (c : Nat) (next : St) (r : Keep) (h : trial env k start st rows = .ok (.placed c next r)) :
    R env st next (notesOf (rows.take c)) := by
  unfold trial at h
  split at h
  · cases h
  unfold trialFrom at h
  split at h
  · injection h with h; injection h with h1 h2 _; subst h1; subst h2; exact R.refl st
  · split at h
    · simp at h
    · split at h
      · split at h
        · have := trialRest_placed_rel env _ start _ _ _ c next r h; exact R.pre id this
        · simp at h
      · exact trialRest_placed_rel env _ start _ _ _ c next r h

set_option linter.unusedVariables false in
theorem dr_placeLines (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (s : St)
    (h : placeLines env k start st rows = .ok s) : R env st s (notesOf rows) := by
  match rows with
  | [] =>
    simp only [placeLines, Except.ok.injEq] at h; subst h; exact R.refl _
  | r :: rs =>
    rw [placeLines] at h
    split at h
    · cases h
    · rename_i next relaxed e
      have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·))
          (Nat.succ rs.length, keepRank relaxed, rank next) (Nat.succ rs.length, keepRank k, rank st) := by
        apply Prod.Lex.right
        cases I4_trial_moved env k start st _ next relaxed e with
        | inl l => exact Prod.Lex.left _ _ l
        | inr e => rw [e.1]; exact Prod.Lex.right _ e.2
      exact R.pre (trial_moved_nm env k start st _ next relaxed e) (dr_placeLines env relaxed start next (r :: rs) s h)
    · rename_i count next relaxed e
      have a := trial_placed_rel env k start st _ count next relaxed e
      split at h
      · rename_i c
        injection h with h; subst h
        rw [c, take_length'] at a; exact a
      · have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·))
            (Nat.succ rs.length - count, keepRank relaxed, rank (nextColumn env next))
            (Nat.succ rs.length, keepRank k, rank st) := by
          apply Prod.Lex.left
          have := I4_trial_placed env k start st _ _ count next relaxed e
          omega
        have b := dr_placeLines env relaxed false (nextColumn env next) ((r :: rs).drop count) s h
        exact R.tr a (R.pre (dk_nextColumn env next) b) (notesOf_take_drop _ _)
termination_by (rows.length, keepRank k, rank st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem dr_placeWithNext (inner : Inner) (env : Env) (k : Keep) (start : Bool) (st : St) (ls : List Line)
    (l f : Nat) (later : List Flow) (s : St)
    (h : placeWithNext inner env k start st ls l f later = .ok s) : R env st s (notesOf ls) := by
  unfold placeWithNext at h
  split at h
  · cases h
  · rename_i full e
    split at h
    · injection h with h; subst h; exact dr_placeLines env k start st ls _ e
    · split at h
      · injection h with h; subst h; exact dr_placeLines env k start st ls _ e
      · split at h
        · cases h
        · rename_i before e2
          have a := dr_placeLines env k start st _ before e2
          have b := dr_placeLines env k _ _ _ s h
          exact R.tr a (R.via b (dk_afterFront env before)) (notesOf_take_drop _ _)

/-! ## Stanzas -/

theorem dr_placeStanza (env : Env) (k : Keep) (start : Bool) (st : St) (verses : List (List Line)) (s : St)
    (h : placeStanza env k start st verses = .ok s) : R env st s (notesOf verses.join) := by
  have key : ∀ m, ∀ (k : Keep) (start : Bool) (st : St) (verses : List (List Line)),
      stanzaRank k st verses = m → ∀ s, placeStanza env k start st verses = .ok s →
      R env st s (notesOf verses.join) := by
    intro m
    induction m using stanza_wf.induction with
    | _ m ih =>
    intro k start st verses hm s h
    subst hm
    match verses with
    | [] => simp only [placeStanza, Except.ok.injEq] at h; subst h; exact R.refl _
    | v :: vs =>
      rw [placeStanza] at h
      dsimp only at h
      split at h
      · rename_i h1
        split at h
        · have := ih _ (Prod.Lex.right _ (Prod.Lex.left _ _ (by simp [keepRank, h1.1]))) _ start _ (v :: vs) rfl s h
          exact R.via this id
        · rename_i h2
          have r : rank (nextColumn env st) < rank st := by
            apply I4_nextColumn_rank; left
            cases e : empty st
            · rfl
            · simp [e] at h2
          have := ih _ (Prod.Lex.right _ (Prod.Lex.right _ r)) k start _ (v :: vs) rfl s h
          exact R.via this (dk_nextColumn env st)
      · split at h
        · rename_i h3
          have r : rank (nextColumn env st) < rank st := by
            apply I4_nextColumn_rank; left
            have := h3.2; simp only [Bool.or_eq_false_iff] at this; exact this.1
          have := ih _ (Prod.Lex.right _ (Prod.Lex.right _ r)) k start _ (v :: vs) rfl s h
          exact R.via this (dk_nextColumn env st)
        · split at h
          · rename_i h4
            split at h
            · cases h
            · rename_i placed e
              have a := dr_placeLines env _ _ st _ placed e
              split at h
              · injection h with h; subst h
                rename_i c
                have : (v :: vs).drop (wholeVerses (fitting env st (v :: vs).join) (v :: vs)) = [] := by
                  rw [c]; simp
                refine R.congr ?_ (R.post a id)
                rw [← notes_join_take_drop (wholeVerses (fitting env st (v :: vs).join) (v :: vs)) (v :: vs), this]
                simp
              · have b := ih _ (by apply Prod.Lex.left; simp only [stanzaRank, List.length_drop, List.length_cons]; have := h4.2; omega) k false _ _ rfl s h
                exact R.tr (R.post a id) (R.via b ((dk_nextColumn env _).trans id)) (notes_join_take_drop _ _)
          · split at h
            · split at h
              · cases h
              · rename_i placed e
                have a := dr_placeLines env _ true st v placed e
                have b := ih _ (Prod.Lex.left _ _ (by simp)) k false placed vs rfl s h
                exact R.tr a b (notesOf_append v vs.join).symm
            · rename_i h5
              split at h
              · cases h
              · rename_i placed e
                have a := dr_placeLines env _ _ st _ placed e
                split at h
                · injection h with h; subst h
                  rename_i c
                  have : (v :: vs).drop (splitAtBreak k start (vs.length + 1) (wholeVerses (fitting env st (v :: vs).join) (v :: vs))) = [] := by
                    rw [c]; simp
                  refine R.congr ?_ a
                  rw [← notes_join_take_drop (splitAtBreak k start (vs.length + 1) (wholeVerses (fitting env st (v :: vs).join) (v :: vs))) (v :: vs), this]
                  simp
                · have b := ih _ (by apply Prod.Lex.left; simp only [stanzaRank, List.length_drop, List.length_cons]; omega) k false _ _ rfl s h
                  exact R.tr a (R.via b ((dk_nextColumn env _).trans id)) (notes_join_take_drop _ _)
  exact key _ k start st verses rfl s h

theorem dr_placeStanzaWithNext (inner : Inner) (env : Env) (k : Keep) (st : St) (verses : List (List Line))
    (l f : Nat) (later : List Flow) (s : St)
    (h : placeStanzaWithNext inner env k st verses l f later = .ok s) : R env st s (notesOf verses.join) := by
  unfold placeStanzaWithNext at h
  split at h
  · cases h
  · rename_i full e
    have a := dr_placeStanza env k true st verses full e
    split at h
    · injection h with h; subst h; exact a
    · split at h
      · cases h
      · rename_i before e2
        split at h
        · injection h with h; subst h; exact a
        · have a2 := dr_placeStanza env k true st _ before e2
          have b := dr_placeStanza env k true _ _ s h
          exact R.tr a2 (R.via b ((dk_nextColumn env _).trans id)) (notes_join_take_drop _ _)

/-! ## Headings and ruled blocks -/

theorem dr_putHeading (env : Env) (st : St) (firstId : Nat) (extent : Int) (ls : List Line) (s : St)
    (h : putHeading env st firstId extent ls = .ok s) : R env st s (notesOf ls) := by
  unfold putHeading at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    exact R.post (dr_putLine _ false st placed _ e) id

theorem dr_placeHeading (env : Env) (st : St) (firstId : Nat) (extent : Int) (ls : List Line) (s : St)
    (h : placeHeading env st firstId extent ls = .ok s) : R env st s (notesOf ls) := by
  unfold placeHeading at h
  split at h
  · cases h
  · split at h
    · exact R.via (dr_putHeading env _ firstId extent ls s h) id
    · exact R.via (dr_putHeading env _ firstId extent ls s h) (dk_fit env st _)

theorem dr_putRuledHeading (env : Env) (ready : St) (b a : Int) (sh ends : List Int) (j : Option Pending) (fid : Nat)
    (e : Int) (ls : List Line) (s : St) (h : putRuledHeading env ready b a sh ends j fid e ls = .ok s) :
    R env ready s (notesOf ls) := by
  unfold putRuledHeading at h
  split at h
  · cases h
  · rename_i placed e2
    injection h with h; subst h
    exact R.post (R.via (dr_putHeading env _ fid e ls placed e2) id) id

theorem dr_ruledPlaceAt (env : Env) (st : St) (r : Ruled) (first lastLine : Line) (later : List Flow)
    (ready p : St) (h : ruledPlaceAt env st r first lastLine later ready = .ok p) :
    R env ready p (notesOf r.lines) := by
  unfold ruledPlaceAt at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    exact R.post (R.via (dr_putLinesKeeping env true _ _ _ placed r.lines e) id) id

theorem dr_ruledLinesHere (env : Env) (st : St) (r : Ruled) (later : List Flow) (p : St)
    (h : ruledLinesHere env st r later = .ok (some p)) : R env st p (notesOf r.lines) := by
  unfold ruledLinesHere at h
  split at h
  · split at h
    · cases h
    · split at h
      · split at h
        · cases h
        · rename_i s0 e
          injection h with h; injection h with h; subst h
          exact R.via (dr_ruledPlaceAt env st r _ _ later _ s0 e) (dk_fit env st _)
      · cases h
  · cases h

theorem dk_headingReady (env : Env) (hs : St) (fid : Nat) (extent size : Int) :
    K env hs (headingReady env hs fid extent size) := by
  unfold headingReady
  split
  · exact id
  · exact dk_fit env hs size

theorem dr_placeRuled (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) (s : St)
    (h : placeRuled inner env st r later = .ok s) : R env st s (notesOf r.lines) :=
  gen_placeRuled inner env (N := K env) (F := fun a b => R env a b (notesOf r.lines))
    { nf := fun h1 h2 => R.via h2 h1
      flush := dk_flush env
      next := dk_nextColumn env
      fit := dk_fit env
      hs := dk_headingState env
      ready := dk_headingReady env
      put := fun r' _ _ _ _ _ _ _ _ _ e e2 => by
        rw [← e]; exact dr_putRuledHeading env _ _ _ _ _ _ _ _ _ _ e2
      head := fun r' _ _ _ _ e e2 => by rw [← e]; exact dr_placeHeading env _ _ _ _ _ e2
      lines := fun _ r' _ _ _ e e2 => by rw [← e]; exact dr_ruledLinesHere env _ r' _ _ e2
      place := fun r' _ _ _ e _ e2 => by rw [← e]; exact dr_placeLines env _ true _ _ _ e2
      nil := fun a _ e => by rw [e]; exact R.refl a }
    st r later s rfl rfl rfl h

theorem dr_placeRuledKeeping (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) (s : St)
    (h : placeRuledKeeping inner env st r later = .ok s) : R env st s (notesOf r.lines) := by
  unfold placeRuledKeeping at h
  split at h
  · cases h
  · rename_i full e
    dsimp only at h
    split at h
    · split at h
      · exact R.via (dr_placeRuled inner env _ { r with joined := false } later s h)
          ((dk_nextColumn env _).trans (dk_flush env st))
      · injection h with h; subst h; exact dr_placeRuled inner env st r later _ e
    · injection h with h; subst h; exact dr_placeRuled inner env st r later _ e

/-! ## Wrapped figures -/

theorem dr_putWrappedLine (env : Env) (fe : Int) (st s : St) (l : Line)
    (h : putWrappedLine env fe st l = .ok s) : R env st s l.notes := by
  unfold putWrappedLine at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    exact R.post (R.via (dr_putLine env false _ placed l e) id) id

theorem dr_putBeside (env : Env) (fe : Int) (st s : St) (ls : List Line)
    (h : putBeside env fe st ls = .ok s) : R env st s (notesOf ls) := by
  induction ls generalizing st with
  | nil => simp only [putBeside, Except.ok.injEq] at h; subst h; exact R.refl _
  | cons l ls ih =>
    unfold putBeside at h
    split at h
    · cases h
    · rename_i s1 e
      exact R.tr (R.via (dr_putWrappedLine env fe _ s1 l e) id) (ih s1 h) rfl

theorem dk_overflowMove (env : Env) (st : St) (l : Line) (gap : Int) : K env st (overflowMove env st l gap) := by
  unfold overflowMove; split
  · exact dk_nextColumn env st
  · exact id

theorem dk_overflowReady (env : Env) (st : St) (l : Line) : K env st (overflowReady env st l) := by
  unfold overflowReady
  dsimp only
  exact (dk_fit env _ _).trans (dk_overflowMove env st l _)

theorem dr_placeWrappedOverflow (env : Env) (st s : St) (ls : List Line)
    (h : placeWrappedOverflow env st ls = .ok s) : R env st s (notesOf ls) := by
  induction ls generalizing st with
  | nil => simp only [placeWrappedOverflow, Except.ok.injEq] at h; subst h; exact R.refl _
  | cons l ls ih =>
    unfold placeWrappedOverflow at h
    split at h
    · cases h
    · rename_i placed e
      exact R.tr (R.via (dr_putLine env false _ placed l e) (dk_overflowReady env st l)) (ih placed h) rfl

theorem dr_placeWrapped (env : Env) (st : St) (i : Nat) (e : Int) (ls : List Line)
    (s : St) (h : placeWrapped env st i e ls = .ok s) : R env st s (notesOf ls) := by
  unfold placeWrapped at h
  split at h
  · cases h
  · dsimp only at h
    split at h
    · cases h
    · rename_i placed eq
      generalize fittingWrapped env _ _ ls = c at h eq
      have ab : R env st placed (notesOf (ls.take c)) := R.via (dr_putBeside env _ _ placed _ eq) (dk_fit env st e)
      split at h
      · rename_i emp
        injection h with h; subst h
        have hd : ls.drop c = [] := by
          cases d : ls.drop c with
          | nil => rfl
          | cons _ _ => rw [d] at emp; cases emp
        refine R.congr ?_ (R.post ab id)
        rw [← notesOf_take_drop c ls, hd]; simp
      · have b := dr_placeWrappedOverflow env _ s _ h
        exact R.tr (R.post ab id) (R.via b ((dk_nextColumn env _).trans id)) (notesOf_take_drop _ _)

/-! ## Code: its rows put no notes -/

theorem dk_placeCode (env : Env) (caption : Int) (first : Nat) (continued : Bool) (spans : List Nat)
    (isFirst : Bool) (st : St) (rows : List Line) (s : St)
    (h : placeCode env caption first continued spans isFirst st rows = .ok s) : K env st s := by
  have key : ∀ n, ∀ (isFirst : Bool) (st : St) (rows : List Line), rows.length = n →
      ∀ s, placeCode env caption first continued spans isFirst st rows = .ok s → K env st s := by
    intro n
    induction n using Nat.strongInductionOn with
    | _ n ih =>
    intro isFirst st rows hn s h
    match rows with
    | [] => simp only [placeCode, Except.ok.injEq] at h; subst h; exact id
    | r :: rs =>
      rw [placeCode] at h
      dsimp only at h
      split at h
      · cases h
      · split at h
        · cases h
        · rename_i c0
          split at h
          · injection h with h; subst h
            exact (dk_fit env _ _).trans (dk_seek env _ st)
          · rename_i c
            have b := ih _ (by rw [← hn]; simp only [List.length_drop, List.length_cons]; exact Nat.sub_lt (Nat.succ_pos _) (Nat.pos_of_ne_zero c0))
              false _ _ rfl s h
            exact b.trans ((dk_nextColumn env _).trans ((dk_fit env _ _).trans (dk_seek env _ st)))
  exact key _ isFirst st rows rfl s h

/-! ## Tables -/

theorem dr_putReserved (env : Env) (reserve : Int) (st s : St) (ls : List Line)
    (h : putReserved env reserve st ls = .ok s) : R env st s (notesOf ls) := by
  induction ls generalizing st with
  | nil => simp only [putReserved, Except.ok.injEq] at h; subst h; exact R.refl _
  | cons l ls ih =>
    unfold putReserved at h
    split at h
    · cases h
    · rename_i s1 e
      have b := ih _ h
      exact R.tr (R.post (R.via (dr_putLine env true _ s1 l e) id) id) b rfl

theorem dk_putRepeated (env : Env) (st s : St) (ls : List Line) (h : putRepeated env st ls = .ok s) :
    K env st s := by
  induction ls generalizing st with
  | nil => simp only [putRepeated, Except.ok.injEq] at h; subst h; exact id
  | cons l ls ih =>
    unfold putRepeated at h
    split at h
    · cases h
    · exact (ih _ h).trans id

theorem dk_tableAt (env : Env) (b : Int) (ls : List Line) (s : St) : K env s (tableAt env b ls s) :=
  dk_fit env s _

theorem dr_tableRowsGo (env : Env) (header caption : List Line) (below : Bool) (ident : Nat) :
    ∀ m (seeking passed : Bool) (start : Int) (st : St) (rows : List (List Line)),
      (rows.length, tableRowsRank passed st seeking) = m →
      ∀ s, tableRowsGo env header caption below ident seeking passed start st rows = .ok s →
      R env st s (notesOf rows.join ++ (if below then notesOf caption else [])) := by
  intro m
  induction m using table_wf.induction with
  | _ m ih =>
  intro seeking passed start st rows hm s h
  subst hm
  match rows with
  | [] =>
    rw [tableRowsGo] at h
    split at h
    · rename_i b; exact R.congr (by simp [b]) (dr_putReserved env 0 st s caption h)
    · rename_i b; injection h with h; subst h; exact R.congr (by simp [b]) (R.refl st)
  | row :: rest =>
    rw [tableRowsGo] at h
    split at h
    · rename_i h1
      split at h
      · cases h
      · rename_i withHeader e
        have dec : tableLt ((row :: rest).length, tableRowsRank passed withHeader false)
            ((row :: rest).length, tableRowsRank passed st seeking) := by
          apply Prod.Lex.right
          obtain ⟨d1, c1, k1, n1, _⟩ := tableAt_fields env 0 _ st h1.2
          obtain ⟨d2, c2, k2, n2, _, _⟩ := putRepeated_fields env _ _ header e
          simp only [tableRowsRank, waiting, columnsLeft, d1, c1, k1, n1, d2, c2, k2, n2, h1.1]
          exact Prod.Lex.right _ (Prod.Lex.right _ (Prod.Lex.right _ (by decide)))
        have b := ih _ dec false passed _ withHeader (row :: rest) rfl s h
        exact R.via b ((dk_putRepeated env _ withHeader header e).trans (dk_tableAt env 0 _ st))
    · split at h
      · split at h
        · cases h
        · rename_i placed e
          have dec : tableLt (rest.length, tableRowsRank false placed false)
              ((row :: rest).length, tableRowsRank passed st seeking) := by
            apply Prod.Lex.left; simp
          have a := dr_putReserved env _ st placed row e
          have b := ih _ dec false false start placed rest rfl s h
          exact R.tr a b (by simp only [List.join, notesOf_append, List.append_assoc])
      · split at h
        · rename_i h2
          have dec : tableLt ((row :: rest).length, tableRowsRank passed (nextColumn env st) true)
              ((row :: rest).length, tableRowsRank passed st seeking) := by
            apply Prod.Lex.right; simp only [tableRowsRank]
            exact Prod.Lex.right _ (lex3_of_lex2 (I4_drain_rank env st ⟨seek_cond st h2.2, h2.1⟩))
          have b := ih _ dec true passed start _ (row :: rest) rfl s h
          exact R.via b (dk_nextColumn env st)
        · split at h
          · rename_i h3
            have dec : tableLt ((row :: rest).length, tableRowsRank true (nextColumn env st) true)
                ((row :: rest).length, tableRowsRank passed st seeking) := by
              apply Prod.Lex.right; simp only [tableRowsRank, h3]; exact Prod.Lex.left _ _ (by decide)
            have b := ih _ dec true true start _ (row :: rest) rfl s h
            exact R.via b (dk_nextColumn env st)
          · cases h

theorem dr_tableCaption (env : Env) (below : Bool) (reserve : Int) (start s : St) (caption : List Line)
    (h : tableCaption env below reserve start caption = .ok s) :
    R env start s (if below then [] else notesOf caption) := by
  unfold tableCaption at h
  split at h
  · rename_i b; injection h with h; subst h; exact R.congr (by simp [b]) (R.refl start)
  · rename_i b; exact R.congr (by simp [b]) (dr_putReserved env reserve start s caption h)

theorem dr_placeTableFrom (env : Env) (st : St) (ident : Nat) (before : Int) (header : List Line)
    (rows : List (List Line)) (caption : List Line) (below : Bool) (firstPart : List Line)
    (s : St) (h : placeTableFrom env st ident before header rows caption below firstPart = .ok s) :
    R env st s (tableNotes header rows caption below) := by
  unfold placeTableFrom at h
  have sk := dk_seek env (tableFits env before firstPart) st
  generalize seek env (tableFits env before firstPart) st = F at h sk
  dsimp only at h
  split at h
  · cases h
  · split at h
    · cases h
    · rename_i placed e1
      split at h
      · cases h
      · rename_i withHeader e2
        have b := dr_tableCaption env below _ _ placed caption e1
        have c := dr_putReserved env _ placed withHeader header e2
        have d := dr_tableRowsGo env header caption below ident _ false false _ withHeader rows rfl s h
        have all := R.via ((b.trans c).trans d) ((dk_tableAt env before firstPart F).trans sk)
        refine R.congr ?_ all
        unfold tableNotes
        cases below <;> simp [List.append_assoc]

theorem dr_placeTable (env : Env) (st : St) (ident : Nat) (before : Int) (header : List Line)
    (rows : List (List Line)) (caption : List Line) (below : Bool)
    (s : St) (h : placeTable env st ident before header rows caption below = .ok s) :
    R env st s (tableNotes header rows caption below) := by
  unfold placeTable at h
  split at h
  · cases h
  · exact dr_placeTableFrom env st ident before header rows caption below _ s h

/-! ## Boxes -/

theorem dr_putBoxPart (env : Env) (ident : Nat) (ready s : St) (origin b a : Int) (ls : List Line) (short : List Unmet)
    (h : putBoxPart env ident ready origin b a ls short = .ok s) : R env ready s (notesOf ls) := by
  unfold putBoxPart at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    exact R.post (R.via (dr_putLines env false _ placed ls e) id) id

set_option linter.unusedVariables false in
theorem dr_placeBoxedParagraph (env : Env) (ident : Nat) (fb fa : Int) (k : Keep) (start : Bool) (st : St)
    (ls : List Line) (s : St) (h : placeBoxedParagraph env ident fb fa k start st ls = .ok s) :
    R env st s (notesOf ls) := by
  match ls with
  | [] => simp only [placeBoxedParagraph, Except.ok.injEq] at h; subst h; exact R.refl _
  | first :: more =>
    rw [placeBoxedParagraph] at h
    dsimp only at h
    split at h
    · cases h
    · split at h
      · cases h
      · split at h
        · rename_i h1
          split at h
          · have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)) ((first :: more).length, keepRank { k with all := false }, rank (addUnmet (.splitKept first.id) st))
                ((first :: more).length, keepRank k, rank st) := by
              apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, h1.1]
            exact R.via (dr_placeBoxedParagraph env ident fb fa _ start _ (first :: more) s h) id
          · rename_i h2
            have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)) ((first :: more).length, keepRank k, rank (nextColumn env st))
                ((first :: more).length, keepRank k, rank st) := by
              apply Prod.Lex.right; apply Prod.Lex.right
              exact I4_nextColumn_rank env st (Or.inl (by simpa using h2))
            exact R.via (dr_placeBoxedParagraph env ident fb fa k start _ (first :: more) s h) (dk_nextColumn env st)
        · split at h
          · rename_i h3
            have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)) ((first :: more).length, keepRank k, rank (nextColumn env st))
                ((first :: more).length, keepRank k, rank st) := by
              apply Prod.Lex.right; apply Prod.Lex.right; exact I4_nextColumn_rank env st (Or.inl h3.2)
            exact R.via (dr_placeBoxedParagraph env ident fb fa k start _ (first :: more) s h) (dk_nextColumn env st)
          · split at h
            · cases h
            · rename_i finished e
              have a := R.via (dr_putBoxPart env ident _ finished _ _ _ _ _ e) (dk_fit env st _)
              split at h
              · rename_i h4
                have b := dr_placeBoxedParagraph env ident fb fa k false _ _ s h
                exact R.tr a (R.via b ((dk_nextColumn env _).trans id)) (notesOf_take_drop _ _)
              · rename_i h4
                injection h with h; subst h
                rw [take_of_le _ (first :: more) ?_] at a
                · exact a
                · simp; omega
termination_by (ls.length, keepRank k, rank st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | assumption
    | (apply Prod.Lex.left; try simp only [List.length_drop, List.length_cons]
       exact Nat.sub_lt (Nat.succ_pos _) (boxCount_pos _ _))

theorem dk_seal {env : Env} (o : BoxOpen) (st : St) : K env st (seal o st) := by
  cases o with
  | none => exact id
  | some p => obtain ⟨_, _⟩ := p; exact id

theorem dk_reopen (env : Env) (ident : Nat) (fb fa : Int) (verse : List Line) (st : St) :
    K env st (reopen env ident fb fa verse st).1 := by
  unfold reopen
  split
  · split
    · exact id
    · exact id
  · exact id

theorem dr_putUnits (env : Env) (m : BoxMaps) (st s : St) (first : Bool) (vs : List (List Line))
    (h : putUnits env m st first vs = .ok s) : R env st s (notesOf vs.join) := by
  induction vs generalizing st first with
  | nil => simp only [putUnits, Except.ok.injEq] at h; subst h; exact R.refl _
  | cons v vs ih =>
    unfold putUnits at h
    dsimp only at h
    split at h
    · cases h
    · rename_i s1 e
      have b := ih s1 false h
      exact R.tr (R.via (dr_putLines env false _ s1 v e) id) b (notesOf_append v vs.join).symm

theorem dr_putStanzaPart (env : Env) (m : BoxMaps) (ident : Nat) (ready s : St) (origin b g a : Int)
    (vs : List (List Line)) (short : List Unmet) (h : putStanzaPart env m ident ready origin b g a vs short = .ok s) :
    R env ready s (notesOf vs.join) := by
  unfold putStanzaPart at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    exact R.post (R.via (dr_putUnits env m _ placed true vs e) id) id

set_option linter.unusedVariables false in
theorem dr_placeBoxedStanza (env : Env) (ident : Nat) (fb fa : Int) (m : BoxMaps) (k : Keep) (start : Bool)
    (relaxed : List Nat) (o : BoxOpen) (st : St) (vs : List (List Line)) (s : St)
    (h : placeBoxedStanza env ident fb fa m k start relaxed o st vs = .ok s) : R env st s (notesOf vs.join) := by
  match vs with
  | [] =>
    simp only [placeBoxedStanza, Except.ok.injEq] at h; subst h
    exact R.same (dk_seal o st)
  | v :: more =>
    rw [placeBoxedStanza] at h
    dsimp only at h
    split at h
    · rename_i h1
      have hne := h1.2
      have b := dr_placeBoxedStanza env ident fb fa m k start relaxed none _ (v :: more) s h
      exact R.via b ((dk_nextColumn env _).trans (dk_seal o st))
    · split at h
      · rename_i h2
        have hk := h2.2.2.1
        have b := dr_placeBoxedStanza env ident fb fa m _ start relaxed o _ (v :: more) s h
        exact R.via b id
      · split at h
        · rename_i p hp
          have hp' : relaxFor m relaxed v = some p := by
            split at hp
            · exact hp
            · cases hp
          have b := dr_placeBoxedStanza env ident fb fa m k start (p :: relaxed) o _ (v :: more) s h
          exact R.via b id
        · split at h
          · split at h
            · cases h
            · rename_i placed e
              have a := dr_placeBoxedParagraph env ident fb fa _ true st v placed e
              have b := dr_placeBoxedStanza env ident fb fa m k false relaxed _ _ more s h
              exact R.tr a (R.via b (dk_reopen env ident fb fa v placed)) (notesOf_append v more.join).symm
          · rename_i h3
            split at h
            · cases h
            · rename_i finished e
              have a := R.via (dr_putStanzaPart env m ident _ finished _ _ _ _ _ _ e) (dk_fit env st _)
              split at h
              · have b := dr_placeBoxedStanza env ident fb fa m k false relaxed none _ _ s h
                exact R.tr a (R.via b ((dk_nextColumn env _).trans id)) (notes_join_take_drop _ _)
              · rename_i h4
                injection h with h; subst h
                rw [take_of_le _ (v :: more) ?_] at a
                · exact a
                · simp; omega
termination_by (vs.length, keepRank k, unrelaxed m relaxed vs, rank st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; exact rank_seal_lt env _ _ (by assumption))
    | (apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, hk])
    | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left; exact unrelaxed_lt _ _ _ _ _ hp')
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.left; try simp only [List.length_drop, List.length_cons]
       exact Nat.sub_lt (Nat.succ_pos _) (stanzaBoxCount_pos (by assumption)))

/-- `placeFlow` and `placeAll` one level below keep `Inv`, reading the notes of the flows. -/
def InvOk (inner : Inner) : Prop :=
  (∀ env st f s, inner.flow env st f = .ok s → R env st s (flowNotes f)) ∧
  (∀ env st fs s, inner.all env st fs = .ok s → R env st s (sourceNotes fs))

theorem dr_placeFlows (inner : Inner) (hi : InvOk inner) (env : Env) (st s : St) (body : List Flow)
    (h : placeFlows inner env st body = .ok s) : R env st s (sourceNotes body) := by
  induction body generalizing st with
  | nil => simp only [placeFlows, Except.ok.injEq] at h; subst h; exact R.congr (by simp [sourceNotes]) (R.refl st)
  | cons f fs ih =>
    unfold placeFlows at h
    split at h
    · cases h
    · rename_i s1 e
      exact R.tr (hi.1 env st f s1 e) (ih s1 h) (sourceNotes_cons f fs).symm

theorem dr_placeGeneric (inner : Inner) (hi : InvOk inner) (env : Env) (st : St) (ident : Nat) (fb fa : Int)
    (body : List Flow) (s : St) (h : placeGeneric inner env st ident fb fa body = .ok s) :
    R env st s (sourceNotes body) := by
  unfold placeGeneric at h
  split at h
  · cases h
  · dsimp only at h
    split at h
    · cases h
    · rename_i placed e
      injection h with h; subst h
      have b := dr_placeFlows inner hi env _ placed body e
      exact R.post (R.via b (dk_fit env st (genericMinimum env ident (bodyLines body)))) id

theorem dr_placeBox (inner : Inner) (hi : InvOk inner) (env : Env) (st : St) (ident : Nat) (fb fa : Int)
    (body : List Flow) (s : St) (h : placeBox inner env st ident fb fa body = .ok s) :
    R env st s (sourceNotes body) := by
  unfold placeBox at h
  split at h
  · exact R.congr (by simp [sourceNotes, flowNotes]) (dr_placeBoxedParagraph env ident fb fa _ true st _ s h)
  · have c := dr_placeBoxedStanza env ident fb fa _ _ true [] none st _ s h
    rw [join_nonempty] at c
    exact R.congr (by simp [sourceNotes, flowNotes]) c
  · split at h
    · rename_i gaps units e
      have t := collectMixed_notes body 0 [] [] gaps units e
      have c := dr_placeBoxedStanza env ident fb fa _ _ true [] none st units s h
      rw [t] at c; exact R.congr (by simp) c
    · exact dr_placeGeneric inner hi env st ident fb fa body s h

/-! ## Book parts and tables across a unit -/

set_option linter.unusedVariables false in
theorem dk_settle (env : Env) (ids : List Nat) (st : St) : K env st (settle env ids st) := by
  rw [settle]
  split
  · rename_i h
    have dec := I4_settle_rank env st ⟨fun e => (by have := h.1; rw [e] at this; cases this), h.2⟩
    exact (dk_settle env ids (nextColumn env st)).trans (dk_nextColumn env st)
  · exact id
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

set_option linter.unusedVariables false in
theorem dk_advanceUnit (env : Env) (u : PartUnit) (w : Nat × Nat) (st : St) :
    K env st (advanceUnit env u w st) := by
  rw [advanceUnit]
  split
  · rename_i h
    have dec : Prod.Lex (· < ·) (· < ·) (2 * w.1 + 2 - (nextColumn env st).page, columnsLeft (nextColumn env st))
        (2 * w.1 + 2 - st.page, columnsLeft st) := by
      have b := unitKey_page u st.page st.column
      rw [h] at b
      cases nextColumn_moves env st with
      | inl l => exact Prod.Lex.left _ _ (by omega)
      | inr r => rw [r.1]; exact Prod.Lex.right _ r.2
    exact (dk_advanceUnit env u w (nextColumn env st)).trans (dk_nextColumn env st)
  · exact id
termination_by (2 * w.1 + 2 - st.page, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem dk_nextUnit (env : Env) (u : PartUnit) (st : St) : K env st (nextUnit env u st) := by
  unfold nextUnit; exact (dk_advanceUnit env _ _ _).trans (dk_nextColumn env st)

theorem dr_retain (env : Env) (u : PartUnit) (table : Bool) (ids : List Nat) (st : St)
    (compose : St → Except Failure St) (X : List Note) (hc : ∀ a s, compose a = .ok s → R env a s X)
    (s : St) (h : retain env u table ids st compose = .ok s) : R env st s X := by
  have tryOk : ∀ a s, retainTry env ids compose a = .ok s → R env a s X := by
    intro a s e
    unfold retainTry at e
    split at e
    · cases e
    · rename_i s1 e1
      injection e with e; subst e
      exact R.post (hc a s1 e1) (dk_settle env ids s1)
  have rep : ∀ x, R env st x X → R env st (addUnmet (.splitPart table u) x) X := fun x hx => R.post hx id
  have mv : ∀ m, retainTry env ids compose (nextUnit env u st) = .ok m → R env st m X := fun m e =>
    R.via (tryOk _ m e) (dk_nextUnit env u st)
  unfold retain at h
  split at h
  · cases h
  · rename_i ordinary e0
    have o := tryOk st ordinary e0
    split at h
    · split at h
      · injection h with h; subst h
        split
        · exact o
        · exact rep _ o
      · split at h
        · cases h
        · injection h with h; subst h
          split
          · exact o
          · exact rep _ o
    · split at h
      · injection h with h; subst h; exact o
      · split at h
        · cases h
        · rename_i m e1
          injection h with h; subst h
          split
          · exact mv m e1
          · apply rep
            split
            · exact o
            · exact mv m e1

set_option linter.unusedVariables false in
theorem dr_acrossGo (env : Env) (header : List Line) (st : St) (gs : List (Bool × List Line)) (s : St)
    (h : acrossGo env header st gs = .ok s) : R env st s (notesOf (gs.map (·.2)).join) := by
  match gs with
  | [] => simp only [acrossGo, Except.ok.injEq] at h; subst h; exact R.refl st
  | (isRow, ls) :: rest =>
    rw [acrossGo] at h
    split at h
    · split at h
      · cases h
      · rename_i placed e
        have a := dr_putReserved env 0 st placed ls e
        have b := dr_acrossGo env header placed rest s h
        exact R.tr a b (by simp [notesOf_append])
    · rename_i hn
      split at h
      · split at h
        · cases h
        · rename_i withHeader e
          split at h
          · cases h
          · rename_i placed e2
            have c := dr_putReserved env 0 _ placed ls e2
            have b := dr_acrossGo env header placed rest s h
            refine R.tr (R.via c ?_) b (by simp [notesOf_append])
            refine K.trans ?_ ((dk_putRepeated env _ withHeader header e).trans (dk_nextColumn env st))
            split
            · exact id
            · exact dk_nextColumn env _
      · have dec : rank (nextColumn env st) < rank st := by
          apply I4_nextColumn_rank; left
          have := (not_or.1 hn).2; simpa using this
        have b := dr_acrossGo env header (nextColumn env st) ((isRow, ls) :: rest) s h
        exact R.via b (dk_nextColumn env st)
termination_by (gs.length, rank st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.right; assumption)

theorem dr_acrossTail (env : Env) (header lastRow caption : List Line) (placed s0 s : St)
    (h : acrossTail env header lastRow caption placed s0 = .ok s) : R env s0 s (notesOf lastRow ++ notesOf caption) := by
  unfold acrossTail at h
  split at h
  · cases h
  · rename_i rowPlaced e
    have r : R env s0 rowPlaced (notesOf lastRow) := by
      split at e
      · split at e
        · cases e
        · rename_i wh e1
          have b := dr_acrossGo env header wh _ rowPlaced e
          exact R.via (R.congr (by simp) b) (dk_putRepeated env _ wh header e1)
      · have b := dr_acrossGo env header s0 _ rowPlaced e
        split at b
        · exact R.congr (by simp) b
        · rename_i ne
          have : lastRow = [] := Decidable.of_not_not ne
          subst this; exact R.congr (by simp) b
    have c := dr_putReserved env 0 _ s caption h
    refine R.tr r (R.via c ?_) rfl
    split
    · exact id
    · exact dk_nextColumn env _

theorem dr_placeTableAcross (env : Env) (u : PartUnit) (st : St) (ident : Nat) (before : Int) (header : List Line)
    (rows : List (List Line)) (caption : List Line) (below : Bool) (s : St)
    (h : placeTableAcross env u st ident before header rows caption below = .ok s) :
    R env st s (tableNotes header rows caption below) := by
  unfold placeTableAcross at h
  dsimp only at h
  split at h
  · cases h
  · split at h
    · cases h
    · split at h
      · cases h
      · have st0 : K env st (if empty st = true then st else if before + st.pending ≤ room env st then
            { st with used := st.used + st.pending + before, pending := 0, blankActive := false, blankSpans := 0 }
            else nextColumn env st) := by
          split
          · exact id
          · split
            · exact id
            · exact dk_nextColumn env st
        split at h
        · cases h
        · rename_i placed e
          have a := R.via (dr_acrossGo env header _ _ placed e) st0
          split at h
          · rename_i low
            have b := dr_retain env u true _ placed _ _
              (fun a s e => dr_acrossTail env header _ caption placed a s e) s h
            refine R.congr ?_ (a.trans b)
            rw [← across_notes header rows caption below]
            simp only [if_pos low, List.nil_append, List.append_nil]
          · rename_i low
            injection h with h; subst h
            refine R.congr ?_ a
            rw [← across_notes header rows caption below]
            simp only [if_neg low, List.nil_append, List.append_nil]

/-! ## One flow, and the flows -/

theorem dr_placeFlow (inner : Inner) (hi : InvOk inner) (env : Env) (st : St) (f : Flow) (s : St)
    (h : placeFlow inner env st f = .ok s) : R env st s (flowNotes f) := by
  cases f with
  | paragraph k ls => exact R.congr (by simp [flowNotes]) (dr_placeLines env k true st ls s h)
  | continued k ls => exact R.congr (by simp [flowNotes]) (dr_placeLines env k false st ls s h)
  | ruled r => exact R.congr (by simp [flowNotes]) (dr_placeRuled inner env st r [] s h)
  | space n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; exact R.congr (by simp [flowNotes]) (R.same id)
  | blank n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; exact R.congr (by simp [flowNotes]) (R.same id)
  | brk k =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact R.congr (by simp [flowNotes]) (R.same (dk_breakAt env k st))
  | start k =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact R.congr (by simp [flowNotes]) (R.same (dk_sectionStart env k st))
  | switchColumns c =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact R.congr (by simp [flowNotes]) (R.same (dk_switchColumns env c st))
  | restoreColumns =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact R.congr (by simp [flowNotes]) (R.same (dk_restoreColumns env st))
  | defTerm ls => exact R.congr (by simp [flowNotes]) (dr_placeLines env _ true st ls s h)
  | stanza k vs => exact R.congr (by simp [flowNotes]) (dr_placeStanza env k true st vs s h)
  | code c f k sp rows =>
    exact R.congr (by simp [flowNotes]) (R.same (dk_placeCode env c f k sp true st rows s h))
  | wrapped i e ls => exact R.congr (by simp [flowNotes]) (dr_placeWrapped env st i e ls s h)
  | table i b header rows caption below =>
    simp only [placeFlow] at h
    split at h
    · exact R.congr (by simp [flowNotes]) (dr_placeTableAcross env _ st i b header rows caption below s h)
    · exact R.congr (by simp [flowNotes]) (dr_placeTable env st i b header rows caption below s h)
  | bookPart u ids body =>
    exact R.congr (by simp [flowNotes])
      (dr_retain env u false ids st _ _ (fun a s e => R.ofEnv (by split <;> rfl) (by split <;> rfl) (by split <;> rfl) (hi.2 _ a body s e)) s h)
  | boxed i b a body => exact R.congr (by simp [flowNotes]) (dr_placeBox inner hi env st i b a body s h)
  | heading recto extent ls =>
    simp only [placeFlow] at h
    have a : K env st (if recto = true then parityStart env (fun p => p % 2 == 1) st else st) := by
      split
      · exact dk_parityStart env _ st
      · exact id
    exact R.congr (by simp [flowNotes]) (R.via (dr_placeHeading env _ _ extent ls s h) a)
  | adjustLines n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact R.congr (by simp [flowNotes]) (R.same ((dk_drainCarried env _).trans id))
  | noBreak =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact R.congr (by simp [flowNotes]) (R.same (dk_waitForPrior _ _ st))
  | keepNext n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact R.congr (by simp [flowNotes]) (R.same (dk_waitForPrior _ _ st))
  | noBreakLines n =>
    simp only [placeFlow] at h
    split at h
    · injection h with h; subst h; exact R.congr (by simp [flowNotes]) (R.refl st)
    · injection h with h; subst h
      exact R.congr (by simp [flowNotes]) (R.same (dk_waitForPrior _ _ st))
  | needLines n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    have : K env st (if env.capacity < (n : Int) * env.pagePitch then addUnmet (.needLines n) st else st) := by
      split <;> exact id
    exact R.congr (by simp [flowNotes]) (R.same ((dk_judgeNeed env _ _).trans this))
  | pageFigure i =>
    simp only [placeFlow] at h
    split at h
    · injection h with h; subst h
      exact R.congr (by simp [flowNotes])
        (R.same ((dk_nextPage env _).trans (fun i => i : K env st (putSlot st env.capacity (.pageFigure i)))))
    · injection h with h; subst h
      exact R.congr (by simp [flowNotes]) (R.same (dk_send (.turned i) trivial st _ rfl rfl))
  | figure i e =>
    simp only [placeFlow] at h
    split at h
    · cases h
    · rename_i hc
      have ok : Waiting.fits env.capacity (.figure i e) := by show e ≤ env.capacity; omega
      split at h
      · injection h with h; subst h
        exact R.congr (by simp [flowNotes]) (R.same (dk_send _ ok st _ rfl rfl))
      · split at h
        · injection h with h; subst h
          exact R.congr (by simp [flowNotes]) (R.same (dk_send _ ok st _ rfl rfl))
        · injection h with h; subst h
          exact R.congr (by simp [flowNotes]) (R.same ((dk_fit env st e : K env st (fit env st e))))

theorem dk_beforeOf (env : Env) (st : St) (flow : Flow) (rest : List Flow) :
    K env st (beforeOf env st flow rest) := by
  have a : K env st (if st.blankActive ∧ occupies flow ∧ empty st = false ∧
      room env st < min env.capacity (st.pending + env.firstNeed (decide (0 < st.notesUsed)) 1 (flow :: rest))
      then nextColumn env st else st) := by
    split
    · exact dk_nextColumn env st
    · exact id
  unfold beforeOf
  dsimp only
  split
  · exact a
  · exact fun i => a i

theorem dr_placeBody (inner : Inner) (hi : InvOk inner) (env : Env) (b : St) (flow : Flow) (rest : List Flow)
    (s : St) (h : placeBody inner env b flow rest = .ok s) : R env b s (flowNotes flow) := by
  unfold placeBody at h
  cases flow with
  | paragraph k ls =>
    cases e : keepAhead rest with
    | none => simp only [e] at h; exact dr_placeFlow inner hi env b _ s h
    | some p =>
      obtain ⟨l, f, later⟩ := p
      simp only [e] at h
      exact R.congr (by simp [flowNotes]) (dr_placeWithNext inner env k true b ls l f later s h)
  | continued k ls =>
    cases e : keepAhead rest with
    | none => simp only [e] at h; exact dr_placeFlow inner hi env b _ s h
    | some p =>
      obtain ⟨l, f, later⟩ := p
      simp only [e] at h
      exact R.congr (by simp [flowNotes]) (dr_placeWithNext inner env k false b ls l f later s h)
  | noBreak =>
    simp only [Except.ok.injEq] at h; subst h
    exact R.congr (by simp [flowNotes]) (R.same (dk_waitForPrior _ _ b))
  | keepNext n =>
    simp only [Except.ok.injEq] at h; subst h
    exact R.congr (by simp [flowNotes]) (R.same (dk_waitForPrior _ _ b))
  | noBreakLines n =>
    simp only at h
    split at h
    · injection h with h; subst h
      exact R.congr (by simp [flowNotes]) (R.same (dk_waitForPrior _ _ b))
    · exact dr_placeFlow inner hi env b _ s h
  | ruled r => exact R.congr (by simp [flowNotes]) (dr_placeRuledKeeping inner env b r rest s h)
  | figure i e => exact dr_placeFlow inner hi env b _ s h
  | pageFigure i => exact dr_placeFlow inner hi env b _ s h
  | space n => exact dr_placeFlow inner hi env b _ s h
  | blank n => exact dr_placeFlow inner hi env b _ s h
  | brk k => exact dr_placeFlow inner hi env b _ s h
  | needLines n => exact dr_placeFlow inner hi env b _ s h
  | adjustLines n => exact dr_placeFlow inner hi env b _ s h
  | start k => exact dr_placeFlow inner hi env b _ s h
  | switchColumns c => exact dr_placeFlow inner hi env b _ s h
  | restoreColumns => exact dr_placeFlow inner hi env b _ s h
  | code c f k sp rows => exact dr_placeFlow inner hi env b _ s h
  | wrapped i e ls => exact dr_placeFlow inner hi env b _ s h
  | table i bf header rows caption below => exact dr_placeFlow inner hi env b _ s h
  | boxed i bf a body => exact dr_placeFlow inner hi env b _ s h
  | stanza k vs =>
    cases e : keepAhead rest with
    | none => simp only [e] at h; exact dr_placeFlow inner hi env b _ s h
    | some p =>
      obtain ⟨l, f, later⟩ := p
      simp only [e] at h
      exact R.congr (by simp [flowNotes]) (dr_placeStanzaWithNext inner env k b vs l f later s h)
  | defTerm ls =>
    simp only at h
    split at h
    · exact R.congr (by simp [flowNotes]) (dr_placeLines env _ true _ ls s h)
    · exact R.congr (by simp [flowNotes])
        (R.via (dr_placeLines env _ true _ ls s h) (dk_keepFollowing inner env false b _ ls rest))
  | bookPart u ids body => exact dr_placeFlow inner hi env b _ s h
  | heading recto extent ls =>
    have a : K env b (if recto = true then parityStart env (fun p => p % 2 == 1) b
        else keepFollowing inner env true b extent ls rest) := by
      split
      · exact dk_parityStart env _ b
      · exact dk_keepFollowing inner env true b extent ls rest
    exact R.congr (by simp [flowNotes]) (R.via (dr_placeHeading env _ _ extent ls s h) a)

theorem dr_placeNext (inner : Inner) (hi : InvOk inner) (env : Env) (st : St) (flow : Flow) (rest : List Flow)
    (s : St) (h : placeNext inner env st flow rest = .ok s) : R env st s (flowNotes flow) := by
  unfold placeNext at h
  split at h
  · cases h
  · rename_i p e
    injection h with h; subst h
    have a := R.via (dr_placeBody inner hi env _ flow rest p e) (dk_beforeOf env st flow rest)
    refine R.post a ?_
    split
    · exact dk_checkWaits p
    · exact id

theorem dr_placeAll (inner : Inner) (hi : InvOk inner) (env : Env) (st : St) (flows : List Flow) (s : St)
    (h : placeAll inner env st flows = .ok s) : R env st s (sourceNotes flows) := by
  induction flows generalizing st with
  | nil =>
    simp only [placeAll, Except.ok.injEq] at h; subst h
    exact R.congr (by simp [sourceNotes]) (R.refl _)
  | cons f fs ih =>
    simp only [placeAll] at h
    split at h
    · cases h
    · rename_i p e
      exact R.tr (dr_placeNext inner hi env st f fs p e) (ih p h) (sourceNotes_cons f fs).symm

/-- `placeFlow` at every level keeps `Inv`, reading the notes of the flows. -/
theorem inv_level_ok : ∀ n, InvOk (level n)
  | 0 => ⟨fun _ _ _ _ h => by simp [level] at h, fun _ _ _ _ h => by simp [level] at h⟩
  | n + 1 => ⟨fun env st f s h => dr_placeFlow (level n) (inv_level_ok n) env st f s h,
      fun env st fs s h => dr_placeAll (level n) (inv_level_ok n) env st fs s h⟩

/-! ## `drainOk` at the last `drainCarry` of `paginate` -/

theorem inv_drainOk (env : Env) (st : St) (h : Inv env st) : drainOk env st = true := by
  obtain ⟨d, c⟩ := h
  simp only [drainOk, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq]
  refine ⟨?_, ?_⟩
  · rcases c with c | c
    · left; rw [c]; rfl
    · right; exact c
  · unfold figureOk
    split
    · rename_i i e r m
      have := d (.figure i e) (by rw [m]; exact List.Mem.head _)
      simpa [Waiting.fits] using this
    · rfl

set_option linter.unusedVariables false in
/-- From a state holding `Inv`, `drainCarry` places every figure waiting
    and every note carried on. -/
theorem inv_drainCarry (env : Env) (st : St) (h : Inv env st) :
    (drainCarry env st).deferred = [] ∧ (drainCarry env st).carry = [] := by
  rw [drainCarry]
  split
  · rename_i c
    have dec := I4_drain_rank env st ⟨Or.inl c.1, c.2⟩
    exact inv_drainCarry env (nextColumn env st) (dk_nextColumn env st h)
  · rename_i c
    have b : (st.carry.isEmpty && st.deferred.isEmpty) = true := by
      cases e : (st.carry.isEmpty && st.deferred.isEmpty)
      · exact absurd ⟨e, inv_drainOk env st h⟩ c
      · rfl
    simp only [Bool.and_eq_true] at b
    refine ⟨?_, ?_⟩
    · cases e : st.deferred with
      | nil => rfl
      | cons _ _ => rw [e] at b; cases b.2
    · cases e : st.carry with
      | nil => rfl
      | cons _ _ => rw [e] at b; cases b.1
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem inv_initial (env : Env) : Inv env (initial env) :=
  ⟨fun _ m => absurd m (List.not_mem_nil _), Or.inl rfl⟩

/-- Root ADR 0352 invariant 4 for the free placement: when the manuscript
    has no notes or a line of a note fits below the separator in an empty
    column, the last `drainCarry` of `paginate` leaves no figure waiting and
    no note carried on, so `paginate` never fails there with `noProgress`. -/
theorem I4_paginate_drained (env : Env) (flows : List Flow) (final : St)
    (h : placeAll (level (flowsDepth flows)) env (initial env) flows = .ok final)
    (hn : sourceNotes flows = [] ∨ CF env) :
    (drainCarry env final).deferred = [] ∧ (drainCarry env final).carry = [] :=
  inv_drainCarry env final (dr_placeAll _ (inv_level_ok _) env _ flows final h hn (inv_initial env))

mutual
/-- The flow holds no book part, also in the bodies of its boxes. -/
def partFree : Flow → Bool
  | .bookPart _ _ _ => false
  | .boxed _ _ _ body => partsFree body
  | _ => true
def partsFree : List Flow → Bool
  | [] => true
  | f :: fs => partFree f && partsFree fs
end

theorem append_nil_iff {α : Type} {a b : List α} (h : a ++ b = []) : a = [] ∧ b = [] := by
  cases a with
  | nil => exact ⟨rfl, h⟩
  | cons _ _ => cases h

mutual
theorem flowNotes_nil : ∀ (f : Flow), partFree f = true → notesOf (flowLines f) = [] → flowNotes f = []
  | .bookPart _ _ _, p, _ => by simp [partFree] at p
  | .boxed _ _ _ body, p, n => by
    simp only [partFree, flowLines] at p n; simp only [flowNotes]; exact sourceNotes_nil body p n
  | .table _ _ header rows caption below, _, n => by
    simp only [flowLines, notesOf_append] at n
    obtain ⟨n12, n3⟩ := append_nil_iff n
    obtain ⟨n1, n2⟩ := append_nil_iff n12
    simp only [flowNotes, tableNotes, n1, n2, n3]; split <;> rfl
  | .paragraph _ _, _, n | .continued _ _, _, n | .ruled _, _, n | .heading _ _ _, _, n
  | .defTerm _, _, n | .stanza _ _, _, n | .wrapped _ _ _, _, n => by simpa [flowLines, flowNotes] using n
  | .code _ _ _ _ _, _, _ | .figure _ _, _, _ | .pageFigure _, _, _ | .space _, _, _ | .blank _, _, _
  | .brk _, _, _ | .needLines _, _, _ | .adjustLines _, _, _ | .noBreak, _, _ | .noBreakLines _, _, _
  | .keepNext _ _, _, _ | .start _, _, _ | .switchColumns _, _, _ | .restoreColumns, _, _ => by simp [flowNotes]
theorem sourceNotes_nil : ∀ (fs : List Flow), partsFree fs = true → notesOf (bodyLines fs) = [] → sourceNotes fs = []
  | [], _, _ => rfl
  | f :: fs, p, n => by
    simp only [partsFree, Bool.and_eq_true] at p
    simp only [bodyLines, notesOf_append] at n
    obtain ⟨n1, n2⟩ := append_nil_iff n
    rw [sourceNotes_cons, flowNotes_nil f p.1 n1, sourceNotes_nil fs p.2 n2]; rfl
end

/-- A manuscript without book parts that passes `checkNotes`, with a
    positive line pitch, never fails at the last `drainCarry` of
    `paginate`: `Inv`, and with it the premise `drainOk`, holds there and
    at every column `drainCarry` goes on to. -/
theorem I4_paginate_checked (env : Env) (flows : List Flow) (final : St) (hp : 0 < env.pagePitch)
    (hf : partsFree flows = true) (hc : checkNotes env flows = none)
    (h : placeAll (level (flowsDepth flows)) env (initial env) flows = .ok final) :
    ∃ pages, paginate env flows = .ok pages := by
  have hn : sourceNotes flows = [] ∨ CF env := by
    unfold checkNotes at hc
    split at hc
    · split at hc
      · cases hc
      · rename_i le; exact Or.inr ⟨hp, by omega⟩
    · rename_i e
      exact Or.inl (sourceNotes_nil flows hf e)
  obtain ⟨d, c⟩ := I4_paginate_drained env flows final h hn
  unfold paginate
  rw [hc]
  dsimp only
  rw [h]
  dsimp only
  rw [if_pos ⟨by rw [d]; rfl, by rw [c]; rfl⟩]
  split
  · exact ⟨_, rfl⟩
  · exact ⟨_, rfl⟩

end Drain
end PhysicalPagination
