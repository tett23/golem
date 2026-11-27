/- Root ADR 0352: every recursive stanza and accept entry, including
   failed trials, selected snapshots, holds, probes and fallback calls. -/
import CausalCalls

namespace PhysicalPagination

set_option linter.unusedVariables false in
mutual
def stanzaEntriesSafe (env : Env) (region : Region) (b : Beside) (a : StanzaArgs) (later : List Nat) (keep : Keep)
    (isStart : Bool) (cursor : St) (indices : List Nat) : Prop :=
  WrapReady region cursor ∧
  (match indices with
  | [] => True
  | firstIndex :: rest =>
    verseEntriesSafe env region b cursor (firstIndex :: rest) ∧
    (match tryVerses env region b cursor (firstIndex :: rest) with
    | .error _ => True
    | .ok trials =>
      let whole := trials.length
      let total := rest.length + 1
      let selected := splitAtBreak keep isStart total whole
      if keep.all ∧ isStart ∧ whole < total then
        if empty cursor then
          stanzaEntriesSafe env region b a later { keep with all := false } isStart
            (addUnmet (.splitKept (b.ident cursor firstIndex)) cursor) (firstIndex :: rest)
        else if h : empty cursor = false then
          stanzaEntriesSafe env region b a later keep isStart (moveCursor env region cursor) (firstIndex :: rest)
        else True
      else if 0 < selected then
        acceptEntriesSafe env region b a later keep isStart cursor (firstIndex :: rest) trials selected []
      else if h : empty cursor = false then
        stanzaEntriesSafe env region b a later keep isStart (moveCursor env region cursor) (firstIndex :: rest)
      else if 0 < whole then
        acceptEntriesSafe env region b a later keep isStart cursor (firstIndex :: rest) trials whole
          ((if isStart ∧ whole < keep.first then [Unmet.shortPart true (b.ident cursor firstIndex) keep.first whole] else []) ++
            (if total - whole < keep.last then [Unmet.shortPart false (b.ident cursor firstIndex) keep.last (total - whole)] else []))
      else
        match a.fallback firstIndex (rest ++ later) cursor with
        | .error _ => True
        | .ok next => stanzaEntriesSafe env region b a later keep false next rest
))
termination_by (indices.length, keepRank keep, rank cursor, 1, 0)
decreasing_by
  all_goals simp_wf
  · rename_i c _; apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, c.1]
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
    exact I4_moveCursor_rank env region cursor (Or.inl h)
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left; omega
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
    exact I4_moveCursor_rank env region cursor (Or.inl h)
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left; omega
  · apply Prod.Lex.left; omega

def acceptEntriesSafe (env : Env) (region : Region) (b : Beside) (a : StanzaArgs) (later : List Nat) (keep : Keep)
    (isStart : Bool) (cursor : St) (indices : List Nat) (trials : List St) (count : Nat) (problems : List Unmet) :
    Prop :=
  WrapReady region cursor ∧ (∀ snapshot ∈ trials, WrapReady region snapshot) ∧
  (if h0 : count = 0 then True
  else
    match trials[count - 1]? with
    | none => True
    | some placed =>
      let warned := { placed with unmet := placed.unmet ++ problems }
      if hr : (indices.drop count).isEmpty then
        let settled := checkWaits warned
        let lastIndex := indices.getLast?.getD 0
        let lastWanted := (b.binding lastIndex).1
        let wanted := (b.binding lastIndex).2
        let probed : Except Failure (Nat × Bool × Bool) :=
          if 0 < wanted ∨ 0 < lastWanted then a.follows lastIndex later settled wanted else .ok (0, true, true)
        WrapReady region settled ∧
        (match probed with
        | .error _ => True
        | .ok (required, linesOnly, fits) =>
          let held := if b.holds lastIndex then b.hold lastIndex required linesOnly settled else settled
          let front := count - max lastWanted (max 1 keep.last)
          WrapReady region held ∧
          (if fits then True
          else if (if isStart then max 1 keep.first else 1) ≤ front ∧ keep.all = false then
            acceptEntriesSafe env region b a later keep isStart cursor indices trials front []
          else if h : empty cursor = false then
            stanzaEntriesSafe env region b a later keep isStart (moveCursor env region cursor) indices
          else True))
      else
        stanzaEntriesSafe env region b a later keep false (moveCursor env region warned) (indices.drop count)
)
termination_by (indices.length, keepRank keep, rank cursor, 0, count)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; omega
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
    exact I4_moveCursor_rank env region cursor (Or.inl h)
  · apply Prod.Lex.left
    have : indices.length ≠ 0 := by
      intro e; rw [List.length_eq_zero.mp e] at hr; simp [List.isEmpty] at hr
    omega
end

theorem PreservesWrapCursor.replace_unmet (cursor : St) (problems : List Unmet) :
    PreservesWrapCursor cursor { cursor with unmet := problems } :=
  ⟨PLe.refl _, fun _ => rfl, by simp [text]⟩

private theorem causal_stanza_entries (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) : ∀ measure,
    (∀ later keep isStart cursor indices, (indices.length, keepRank keep, rank cursor, 1, 0) = measure →
      WrapReady region cursor →
      stanzaEntriesSafe env region (CausalBoundary.beside m region origin)
        (CausalBoundary.stanzaArgs env m job region origin) later keep isStart cursor indices) ∧
    (∀ later keep isStart cursor indices trials count problems,
      (indices.length, keepRank keep, rank cursor, 0, count) = measure →
      WrapReady region cursor → (∀ snapshot ∈ trials, WrapReady region snapshot) →
      acceptEntriesSafe env region (CausalBoundary.beside m region origin)
        (CausalBoundary.stanzaArgs env m job region origin) later keep isStart cursor indices trials count problems) := by
  intro measure
  induction measure using lex5_wf.induction with
  | _ measure ih =>
  constructor
  · intro later keep isStart cursor indices eq ready
    subst eq
    cases indices with
    | nil => rw [stanzaEntriesSafe]; exact ⟨ready, trivial⟩
    | cons firstIndex rest =>
      rw [stanzaEntriesSafe]
      refine ⟨ready, root_adr0352_i3_verse_entries_safe env region _ _ cursor ready, ?_⟩
      split
      · trivial
      · rename_i trials tried
        have snapshots := root_adr0352_i3_verse_snapshots_ready env region _ _ cursor trials ready tried
        have again : ∀ keep' cursor', WrapReady region cursor' →
            lex5lt ((firstIndex :: rest).length, keepRank keep', rank cursor', 1, 0)
              ((firstIndex :: rest).length, keepRank keep, rank cursor, 1, 0) →
            stanzaEntriesSafe env region (CausalBoundary.beside m region origin)
              (CausalBoundary.stanzaArgs env m job region origin) later keep' isStart cursor' (firstIndex :: rest) := by
          intro keep' cursor' safe dec
          exact (ih _ dec).1 later keep' isStart cursor' _ rfl safe
        have moved : empty cursor = false →
            stanzaEntriesSafe env region (CausalBoundary.beside m region origin)
              (CausalBoundary.stanzaArgs env m job region origin) later keep isStart
              (moveCursor env region cursor) (firstIndex :: rest) := by
          intro emptyFalse
          exact again keep _ (ready.move_cursor env) (by
            apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
            exact I4_moveCursor_rank env region cursor (Or.inl emptyFalse))
        have accepted : ∀ count problems,
            acceptEntriesSafe env region (CausalBoundary.beside m region origin)
              (CausalBoundary.stanzaArgs env m job region origin) later keep isStart
              cursor (firstIndex :: rest) trials count problems := by
          intro count problems
          exact (ih _ (by
            apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left; omega)).2
            later keep isStart cursor _ trials count problems rfl ready snapshots
        dsimp only
        split
        · rename_i kept
          split
          · exact again _ _ (ready.preserved (by
              simpa [addUnmet] using PreservesWrapCursor.replace_unmet cursor (cursor.unmet ++ [.splitKept ((CausalBoundary.beside m region origin).ident cursor firstIndex)]))) (by
              apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, kept.1])
          · split
            · rename_i emptyFalse; exact moved emptyFalse
            · trivial
        · split
          · exact accepted _ _
          · split
            · rename_i emptyFalse; exact moved emptyFalse
            · split
              · exact accepted _ _
              · split
                · trivial
                · rename_i next fallback
                  exact (ih _ (by apply Prod.Lex.left; simp)).1 later keep false next rest rfl
                    (ready.preserved (root_adr0352_i4_causal_paragraph_cursor env m job region origin firstIndex
                      (rest ++ later) defaultKeep 0 0 cursor next fallback))
  · intro later keep isStart cursor indices trials count problems eq ready snapshots
    subst eq
    rw [acceptEntriesSafe]
    refine ⟨ready, snapshots, ?_⟩
    split
    · trivial
    · rename_i nonzero
      split
      · trivial
      · rename_i placed member
        have placedReady := snapshots placed (get?_mem trials _ placed (by rw [← getElem?_get?]; exact member))
        have warnedReady := placedReady.preserved (PreservesWrapCursor.replace_unmet placed (placed.unmet ++ problems))
        dsimp only
        split
        · have settledReady := warnedReady.preserved (PreservesWrapCursor.check_waits _)
          refine ⟨settledReady, ?_⟩
          split
          · trivial
          · rename_i required linesOnly fits _
            have heldReady : WrapReady region
                (if (CausalBoundary.beside m region origin).holds (indices.getLast?.getD 0) then
                  (CausalBoundary.beside m region origin).hold (indices.getLast?.getD 0) required linesOnly
                    (checkWaits { placed with unmet := placed.unmet ++ problems })
                 else checkWaits { placed with unmet := placed.unmet ++ problems }) := by
              split
              · exact settledReady.preserved (PreservesWrapCursor.wait_for_prior _ _ _)
              · exact settledReady
            refine ⟨heldReady, ?_⟩
            split
            · trivial
            · generalize (if isStart = true then max 1 keep.first else 1) = lowest
              split
              · exact (ih _ (by
                  apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; omega)).2
                  later keep isStart cursor indices trials _ [] rfl ready snapshots
              · split
                · rename_i emptyFalse
                  exact (ih _ (by
                    apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
                    exact I4_moveCursor_rank env region cursor (Or.inl emptyFalse))).1
                    later keep isStart _ indices rfl (ready.move_cursor env)
                · trivial
        · rename_i remaining
          exact (ih _ (by
            apply Prod.Lex.left
            have : indices.length ≠ 0 := by
              intro nil; rw [List.length_eq_zero.mp nil] at remaining; simp [List.isEmpty] at remaining
            simp only [List.length_drop]
            omega)).1 later keep false _ (indices.drop count) rfl (warnedReady.move_cursor env)

theorem root_adr0352_i3_causal_stanza_entries_safe (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (later : List Nat) (keep : Keep) (isStart : Bool)
    (cursor : St) (indices : List Nat) (ready : WrapReady region cursor) :
    stanzaEntriesSafe env region (CausalBoundary.beside m region origin)
      (CausalBoundary.stanzaArgs env m job region origin) later keep isStart cursor indices :=
  ((causal_stanza_entries env m job region origin _).1 later keep isStart cursor indices rfl ready)

theorem root_adr0352_i3_causal_accept_entries_safe (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (region : Region) (origin : Int) (later : List Nat) (keep : Keep) (isStart : Bool)
    (cursor : St) (indices : List Nat) (trials : List St) (count : Nat) (problems : List Unmet)
    (ready : WrapReady region cursor)
    (tried : tryVerses env region (CausalBoundary.beside m region origin) cursor indices = .ok trials) :
    acceptEntriesSafe env region (CausalBoundary.beside m region origin)
      (CausalBoundary.stanzaArgs env m job region origin) later keep isStart cursor indices trials count problems :=
  ((causal_stanza_entries env m job region origin _).2 later keep isStart cursor indices trials count problems rfl ready
    (root_adr0352_i3_verse_snapshots_ready env region _ indices cursor trials ready tried))

theorem root_adr0352_i3_initial_causal_stanza_entries_safe (env : Env) (m : CausalBoundary.Ms) (job : Nat)
    (st cursor : St) (ident : Nat) (extent : Int) (region : Region)
    (begun : beginWrap env st ident extent = .ok (cursor, region))
    (origin : Int) (later : List Nat) (keep : Keep) (isStart : Bool) (indices : List Nat) :
    stanzaEntriesSafe env region (CausalBoundary.beside m region origin)
      (CausalBoundary.stanzaArgs env m job region origin) later keep isStart cursor indices :=
  root_adr0352_i3_causal_stanza_entries_safe env m job region origin later keep isStart cursor indices
    (root_adr0352_i3_begin_wrap_ready env st cursor ident extent region begun)

end PhysicalPagination
