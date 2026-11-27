/- Root ADR 0352: follow the entries of paragraphs, including branches
   ending in failure, rather than assuming the entire call succeeds. -/
import CausalParagraphs
import WrapVerses

namespace PhysicalPagination

/-- Every paragraphs cursor, its preliminary composition cursor, its
    tryVerses entries, and its actual placement cursor are wrap-ready.
    An error stops the trace only after the attempted entry is checked. -/
def causalParagraphEntriesSafe (env : Env) (region : Region) (b : Beside)
    (a : StanzaArgs) (p : Paras) (prior : Nat) (cursor : St) (indices : List Nat) : Prop :=
  WrapReady region cursor ∧
  (match indices with
  | [] => True
  | index :: later =>
    match p.preliminary prior index cursor with
    | .error _ => True
    | .ok pre =>
      WrapReady region pre ∧
      (if b.isStanza index then
        verseEntriesSafe env region b pre (verseSpan b index later).1 ∧
        (match tryVerses env region b pre (verseSpan b index later).1 with
        | .error _ => True
        | .ok trials =>
          match p.ready prior index cursor (verseRows b p (pre :: trials).dropLast (verseSpan b index later).1) with
          | .error _ => True
          | .ok ready =>
            WrapReady region ready ∧
            (match stanza env region b a (verseSpan b index later).2 (b.keepOf index) true ready
                (verseSpan b index later).1 with
            | .error _ => True
            | .ok next =>
              causalParagraphEntriesSafe env region b a p (((verseSpan b index later).1.getLast?).getD index) next
                (verseSpan b index later).2))
      else
        match p.ready prior index cursor [b.compose pre index] with
        | .error _ => True
        | .ok ready =>
          WrapReady region ready ∧
          (match p.paragraph index later ready with
          | .error _ => True
          | .ok next => causalParagraphEntriesSafe env region b a p index next later)))
termination_by indices.length
decreasing_by
  all_goals simp_wf
  all_goals (have := verseSpan_after b index later; omega)

/-- The concrete no-break preprocessing and placement functions establish
    all trace conditions, for any model manuscript and outcome. -/
theorem root_adr0352_i3_causal_paragraph_entries_safe (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (prior : Nat) (cursor : St) (indices : List Nat)
    (ready : WrapReady region cursor) :
    causalParagraphEntriesSafe env region (CausalBoundary.beside m region origin)
      (CausalBoundary.stanzaArgs env m job region origin) (CausalBoundary.paras env m job region origin)
      prior cursor indices := by
  match indices with
  | [] => exact ⟨ready, trivial⟩
  | index :: later =>
    rw [causalParagraphEntriesSafe]
    refine ⟨ready, ?_⟩
    dsimp only
    split
    · trivial
    · rename_i pre ep
      have preReady := ready.preserved (root_adr0352_i3_causal_preliminary_cursor env m job region origin prior index cursor pre ep)
      refine ⟨preReady, ?_⟩
      split
      · refine ⟨root_adr0352_i3_verse_entries_safe env region _ _ pre preReady, ?_⟩
        split
        · trivial
        · split
          · trivial
          · rename_i placed er
            have placedReady := ready.preserved (root_adr0352_i3_causal_ready_cursor env m job region origin prior index cursor placed _ er)
            refine ⟨placedReady, ?_⟩
            split
            · trivial
            · rename_i next es
              exact root_adr0352_i3_causal_paragraph_entries_safe env m job region origin _ next _
                (root_adr0352_i3_causal_stanza_ready env m job region origin _ _ _ placed _ next placedReady es)
      · split
        · trivial
        · rename_i placed er
          have placedReady := ready.preserved (root_adr0352_i3_causal_ready_cursor env m job region origin prior index cursor placed _ er)
          refine ⟨placedReady, ?_⟩
          split
          · trivial
          · rename_i next ep
            simp only [CausalBoundary.paras] at ep
            exact root_adr0352_i3_causal_paragraph_entries_safe env m job region origin index next later
              (placedReady.preserved (root_adr0352_i4_causal_paragraph_cursor env m job region origin index later defaultKeep _ _ placed next ep))
termination_by indices.length
decreasing_by
  all_goals simp_wf
  all_goals (have := verseSpan_after (CausalBoundary.beside m region origin) index later; omega)

theorem root_adr0352_i3_initial_causal_paragraph_entries_safe (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (st cursor : St) (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env st ident extent = .ok (cursor, region))
    (origin : Int) (prior : Nat) (indices : List Nat) :
    causalParagraphEntriesSafe env region (CausalBoundary.beside m region origin)
      (CausalBoundary.stanzaArgs env m job region origin) (CausalBoundary.paras env m job region origin)
      prior cursor indices :=
  root_adr0352_i3_causal_paragraph_entries_safe env m job region origin prior cursor indices
    (root_adr0352_i3_begin_wrap_ready env st cursor ident extent region begun)

end PhysicalPagination
