/- Root ADR 0352: follow every probe input, even if its attempted trial
   fails, rather than assuming the probing call succeeds. -/
import CausalCalls

namespace PhysicalPagination

set_option linter.unusedVariables false in
mutual
def probeEntriesSafe (env : Env) (region : Region) (b : Beside) (p : Probe) (index : Nat) (later : List Nat) (cursor : St)
    (wanted : Nat) : Prop :=
  WrapReady region cursor ∧
  (match later with
  | [] => WrapReady region (endWrap region cursor)
  | nextIndex :: more =>
    match p.prefixAt index nextIndex cursor with
    | .error _ => True
    | .ok ready =>
      WrapReady region ready ∧
      (let same := fun (a c : St) => a.page = c.page ∧ a.column = c.column
      if b.isStanza nextIndex then
        let verses := (verseSpan b nextIndex more).1
        let afterVerses := (verseSpan b nextIndex more).2
        let wantedVerses := max (firstPart (b.keepOf nextIndex) true verses.length) (min wanted verses.length)
        verseEntriesSafe env region b ready verses ∧
        (match tryVerses env region b ready verses with
        | .error _ => True
        | .ok trials =>
          let required := p.verseRequired ready verses trials wantedVerses
          let prefixFits := decide (same cursor ready) && decide (wantedVerses ≤ trials.length)
          let chain : Prop :=
            if prefixFits && decide (wantedVerses = verses.length) then
              match trials.getLast? with
              | some placed => probeChainEntriesSafe env region b p (verses.getLast?.getD nextIndex) afterVerses placed
              | none => True
            else True
          chain)
      else
        let rows := b.compose ready nextIndex
        let keep := b.keepOf nextIndex
        let required := p.required wanted keep rows
        match trialWrap env region none { keep with first := max keep.first required } true ready rows with
        | .error _ => True
        | .ok (.moved _ _) => True
        | .ok (.placed count placed _) =>
          WrapReady region placed ∧
          (let prefixFits := decide (same cursor ready) && decide (same ready placed) && decide (required ≤ count)
          let chain : Prop :=
            if prefixFits && decide (count = rows.length) then probeChainEntriesSafe env region b p nextIndex more placed
            else True
          chain)))
termination_by (later.length, 0)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.left; exact Nat.lt_succ_of_le (verseSpan_after b _ _)
  · apply Prod.Lex.left; omega

def probeChainEntriesSafe (env : Env) (region : Region) (b : Beside) (p : Probe) (index : Nat) (later : List Nat) (cursor : St) :
    Prop :=
  WrapReady region cursor ∧
  (if 0 < (b.binding index).2 ∨ 0 < (b.binding index).1 then
    probeEntriesSafe env region b p index later cursor (b.binding index).2
  else True)
termination_by (later.length, 1)
decreasing_by
  all_goals simp_wf
  apply Prod.Lex.right; omega
end

theorem PreservesWrapCursor.end_wrap (region : Region) (cursor : St) :
    PreservesWrapCursor cursor (endWrap region cursor) :=
  ⟨PLe.refl _, fun _ => rfl, Nat.le_refl _⟩

private theorem last_mem {α : Type} : ∀ (xs : List α) (x : α), xs.getLast? = some x → x ∈ xs
  | [], _, h => by cases h
  | a :: rest, x, h => by
    cases rest with
    | nil => simp only [List.getLast?] at h; injection h with h; subst h; exact List.mem_cons_self _ _
    | cons b bs => exact List.mem_cons_of_mem a (last_mem (b :: bs) x h)

private theorem causal_probe_entries (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) : ∀ measure : Nat × Nat,
    (∀ index later cursor wanted, (later.length, 0) = measure → WrapReady region cursor →
      probeEntriesSafe env region (CausalBoundary.beside m region origin)
        (CausalBoundary.probe env m job region origin) index later cursor wanted) ∧
    (∀ index later cursor, (later.length, 1) = measure → WrapReady region cursor →
      probeChainEntriesSafe env region (CausalBoundary.beside m region origin)
        (CausalBoundary.probe env m job region origin) index later cursor) := by
  intro measure
  induction measure using (Prod.lex Nat.lt_wfRel Nat.lt_wfRel).wf.induction with
  | _ measure ih =>
  constructor
  · intro index later cursor wanted eq ready
    subst eq
    cases later with
    | nil =>
      rw [probeEntriesSafe]
      exact ⟨ready, ready.preserved (PreservesWrapCursor.end_wrap region cursor)⟩
    | cons nextIndex more =>
      rw [probeEntriesSafe]
      refine ⟨ready, ?_⟩
      split
      · trivial
      · rename_i pre hp
        have prefixReady := ready.preserved
          (root_adr0352_i3_causal_preliminary_cursor env m job region origin index nextIndex cursor pre hp)
        refine ⟨prefixReady, ?_⟩
        dsimp only
        split
        · refine ⟨root_adr0352_i3_verse_entries_safe env region _ _ pre prefixReady, ?_⟩
          split
          · trivial
          · rename_i trials tried
            have snapshots := root_adr0352_i3_verse_snapshots_ready env region _ _ pre trials prefixReady tried
            try dsimp only
            split
            · split
              · rename_i placed last
                exact (ih _ (by
                  apply Prod.Lex.left
                  change (verseSpan (CausalBoundary.beside m region origin) nextIndex more).2.length < (nextIndex :: more).length
                  exact Nat.lt_succ_of_le (verseSpan_after (CausalBoundary.beside m region origin) nextIndex more))).2 _ _ placed rfl (snapshots placed (last_mem trials placed last))
              · trivial
            · trivial
        · split
          · trivial
          · trivial
          · rename_i count placed relaxed trial
            have placedReady := prefixReady.trial env none _ true _ (.placed count placed relaxed) trial
            refine ⟨placedReady, ?_⟩
            try dsimp only
            split
            · exact (ih _ (by apply Prod.Lex.left; change more.length < (nextIndex :: more).length; simp)).2 nextIndex more placed rfl placedReady
            · trivial
  · intro index later cursor eq ready
    subst eq
    rw [probeChainEntriesSafe]
    refine ⟨ready, ?_⟩
    split
    · exact (ih _ (by apply Prod.Lex.right; change (0 : Nat) < 1; decide)).1 index later cursor _ rfl ready
    · trivial

theorem root_adr0352_i3_causal_probe_entries_safe (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (index : Nat) (later : List Nat) (cursor : St) (wanted : Nat)
    (ready : WrapReady region cursor) :
    probeEntriesSafe env region (CausalBoundary.beside m region origin)
      (CausalBoundary.probe env m job region origin) index later cursor wanted :=
  (causal_probe_entries env m job region origin _).1 index later cursor wanted rfl ready

theorem root_adr0352_i3_causal_probe_chain_entries_safe (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (index : Nat) (later : List Nat) (cursor : St)
    (ready : WrapReady region cursor) :
    probeChainEntriesSafe env region (CausalBoundary.beside m region origin)
      (CausalBoundary.probe env m job region origin) index later cursor :=
  (causal_probe_entries env m job region origin _).2 index later cursor rfl ready

theorem root_adr0352_i3_initial_causal_probe_entries_safe (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (st cursor : St) (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env st ident extent = .ok (cursor, region))
    (origin : Int) (index : Nat) (later : List Nat) (wanted : Nat) :
    probeEntriesSafe env region (CausalBoundary.beside m region origin)
      (CausalBoundary.probe env m job region origin) index later cursor wanted :=
  root_adr0352_i3_causal_probe_entries_safe env m job region origin index later cursor wanted
    (root_adr0352_i3_begin_wrap_ready env st cursor ident extent region begun)

end PhysicalPagination
