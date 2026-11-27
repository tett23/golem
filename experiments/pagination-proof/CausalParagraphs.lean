/- Root ADR 0352: connect no-break preprocessing and every paragraph/stanza
   result to the wrapped cursor invariant of the causal correspondence model. -/
import CausalStanza

namespace PhysicalPagination

theorem root_adr0352_i3_causal_controls_cursor (required : Nat × Bool) (count : Nat) (cursor : St) :
    PreservesWrapCursor cursor (CausalBoundary.nbIter required count cursor) := by
  obtain ⟨page, column, slots, done, _, _, _, _⟩ := CausalBoundary.nbIter_keeps required count cursor
  refine ⟨?_, ?_, ?_⟩
  · simp only [pos, page, column]; exact PLe.refl _
  · intro _; rw [done]
  · simp only [text, done, slots]; exact Nat.le_refl _

theorem root_adr0352_i3_causal_preliminary_cursor (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (prior index : Nat) (cursor out : St)
    (result : (CausalBoundary.paras env m job region origin).preliminary prior index cursor = .ok out) :
    PreservesWrapCursor cursor out := by
  simp only [CausalBoundary.paras] at result
  rw [CausalBoundary.placeAll_noBreaks env _ cursor (CausalBoundary.controls_noBreaks m prior index)] at result
  injection result with same
  subst same
  exact root_adr0352_i3_causal_controls_cursor _ _ _

theorem root_adr0352_i3_causal_ready_cursor (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (prior index : Nat) (cursor out : St) (rows : List (List Line))
    (result : (CausalBoundary.paras env m job region origin).ready prior index cursor rows = .ok out) :
    PreservesWrapCursor cursor out := by
  simp only [CausalBoundary.paras] at result
  rw [CausalBoundary.stepPrefix_noBreaks env _ _ cursor (CausalBoundary.controls_noBreaks m prior index)] at result
  injection result with same
  subst same
  exact root_adr0352_i3_causal_controls_cursor _ _ _

theorem root_adr0352_i4_causal_paragraph_cursor (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (index : Nat) (later : List Nat) (keep : Keep)
    (lastWanted wanted : Nat) (cursor out : St)
    (result : CausalBoundary.paragraphAt env m job region origin index later keep lastWanted wanted cursor = .ok out) :
    PreservesWrapCursor cursor out := by
  let probed := fun st =>
    if 0 < wanted ∨ 0 < lastWanted then
      match probeNext env region (CausalBoundary.beside m region origin) (CausalBoundary.probe env m job region origin) index later st wanted with
      | .ok r => r
      | .error _ => (0, true, false)
    else (0, true, true)
  apply root_adr0352_i4_kept_parts_cursor env region
    (fun at' _ start => CausalBoundary.breakLines m.w (CausalBoundary.measure m index) region origin at' start (CausalBoundary.chars m index))
    (CausalBoundary.chars m index) lastWanted (fun st => (probed st).2.2)
    (fun _ => decide (0 < CausalBoundary.wantOf m index)) 0
    (fun st => (max 1 (probed st).1, (probed st).2.1)) none keep true 0 0 cursor out
  simpa [CausalBoundary.paragraphAt, CausalBoundary.holdNext, probed] using result

theorem root_adr0352_i4_causal_paragraphs_cursor (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (prior : Nat) (cursor : St) (indices : List Nat) (out : St)
    (result : paragraphs env region (CausalBoundary.beside m region origin)
      (CausalBoundary.stanzaArgs env m job region origin) (CausalBoundary.paras env m job region origin)
      prior cursor indices = .ok out) : PreservesWrapCursor cursor out := by
  match indices with
  | [] =>
    simp only [paragraphs, Except.ok.injEq] at result
    subst result
    exact ⟨PLe.refl _, fun _ => rfl, Nat.le_refl _⟩
  | index :: later =>
    rw [paragraphs] at result
    split at result
    · cases result
    · split at result
      · split at result
        · cases result
        · split at result
          · cases result
          · rename_i ready er
            split at result
            · cases result
            · rename_i next es
              exact (root_adr0352_i3_causal_ready_cursor env m job region origin _ _ cursor ready _ er).trans
                ((root_adr0352_i4_causal_stanza_cursor env m job region origin _ _ _ ready _ next es).trans
                  (root_adr0352_i4_causal_paragraphs_cursor env m job region origin _ next _ out result))
      · split at result
        · cases result
        · rename_i ready er
          split at result
          · cases result
          · rename_i next en
            simp only [CausalBoundary.paras] at en
            exact (root_adr0352_i3_causal_ready_cursor env m job region origin _ _ cursor ready _ er).trans
              ((root_adr0352_i4_causal_paragraph_cursor env m job region origin index later defaultKeep _ _ ready next en).trans
                (root_adr0352_i4_causal_paragraphs_cursor env m job region origin index next later out result))
termination_by indices.length
decreasing_by
  all_goals simp_wf
  all_goals (have := verseSpan_after (CausalBoundary.beside m region origin) index later; omega)

theorem root_adr0352_i3_causal_paragraphs_ready (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (prior : Nat) (cursor : St) (indices : List Nat) (out : St)
    (ready : WrapReady region cursor)
    (result : paragraphs env region (CausalBoundary.beside m region origin)
      (CausalBoundary.stanzaArgs env m job region origin) (CausalBoundary.paras env m job region origin)
      prior cursor indices = .ok out) : WrapReady region out :=
  ready.preserved (root_adr0352_i4_causal_paragraphs_cursor env m job region origin prior cursor indices out result)

theorem root_adr0352_i3_initial_causal_paragraphs_ready (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (st cursor : St) (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env st ident extent = .ok (cursor, region))
    (origin : Int) (prior : Nat) (indices : List Nat) (out : St)
    (result : paragraphs env region (CausalBoundary.beside m region origin)
      (CausalBoundary.stanzaArgs env m job region origin) (CausalBoundary.paras env m job region origin)
      prior cursor indices = .ok out) : WrapReady region out :=
  root_adr0352_i3_causal_paragraphs_ready env m job region origin prior cursor indices out
    (root_adr0352_i3_begin_wrap_ready env st cursor ident extent region begun) result

end PhysicalPagination
