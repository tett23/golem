import NumberedStore
namespace NumberedStoreFresh
open NumberedStore NumberedPayload BesideStore BesideWrappedRowFold

private theorem numbered_found_below (rows : List α) (next key : Nat) (value : α)
    (found : fromPairs (numberRows next rows) key = some value) :
    key < next + rows.length := by
  by_cases earlier : key < next
  · have missing : fromPairs (numberRows next rows) key = none := by
      clear found
      induction rows generalizing next with
      | nil => rfl
      | cons row rest ih =>
        have tail := ih (next + 1) (by omega)
        have different : key ≠ next := by omega
        simp [numberRows, fromPairs, tail, different]
    rw [missing] at found
    cases found
  · have same : next + (key - next) = key := by omega
    have slot := root_adr0352_i5_stored_numbered_row rows (key - next) next
    rw [same] at slot
    have present : rows.get? (key - next) = some value := slot.symm.trans found
    obtain ⟨bound, _⟩ := List.get?_eq_some.mp present
    omega

theorem root_adr0352_i5_fold_fresh_ids (chunks : List (List α)) (state : RowState α)
    (old : ∀ key value, fromPairs state.rows key = some value → key < state.next)
    (key : Nat) (value : α) (found : fromPairs (runChunks state chunks).rows key = some value) :
    key < (runChunks state chunks).next := by
  rw [root_adr0352_i5_wrapped_row_fold] at found ⊢
  simp only at found ⊢
  by_cases prior : key < state.next
  · omega
  · have missing : fromPairs state.rows key = none := by
      cases result : fromPairs state.rows key with
      | none => rfl
      | some payload => exact False.elim (prior (old key payload result))
    have append_missing_left (before after : List (Nat × α))
        (absent : fromPairs before key = none) :
        fromPairs (before ++ after) key = fromPairs after key := by
      induction before with
      | nil => rfl
      | cons pair later ih =>
        rcases pair with ⟨other, payload⟩
        simp only [fromPairs] at absent ⊢
        cases tail : fromPairs later key with
        | some last => simp [tail] at absent
        | none =>
          have diff : ¬key = other := by
            intro equal
            subst other
            simp [tail] at absent
          have step := ih tail
          cases afterValue : fromPairs after key <;> simp [step, afterValue, diff]
    rw [append_missing_left state.rows (numberRows state.next (flatten chunks)) missing] at found
    exact numbered_found_below (flatten chunks) state.next key value found

theorem root_adr0352_i5_initial_fold_left_union (before after : List (List α)) (seed key : Nat) :
    let state := runChunks (⟨seed, []⟩ : RowState α) before
    fromPairs (runChunks state after).rows key =
      match fromPairs state.rows key with
      | some value => some value
      | none => fromPairs (numberRows state.next (flatten after)) key := by
  dsimp only
  apply root_adr0352_i5_stored_fold_left_union
  intro wanted value found
  exact root_adr0352_i5_fold_fresh_ids before ⟨seed, []⟩ (by intro key payload h; cases h) wanted value found

end NumberedStoreFresh
