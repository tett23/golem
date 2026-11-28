import WrappedRowFold
import RoundPayloadStore
namespace NumberedStore
open NumberedPayload BesideStore BesideWrappedRowFold

private theorem missing_before (rows : List α) (next key : Nat) (bound : key < next) :
    fromPairs (numberRows next rows) key = none := by
  induction rows generalizing next with
  | nil => rfl
  | cons row rest ih =>
    have tail := ih (next + 1) (by omega)
    have different : key ≠ next := by omega
    simp [numberRows, fromPairs, tail, different]

-- Storage retains the row at every ID; uniqueness is derived by numbering.
theorem root_adr0352_i5_stored_numbered_row (rows : List α) (index next : Nat) :
    fromPairs (numberRows next rows) (next + index) = rows.get? index := by
  induction rows generalizing index next with
  | nil => simp [numberRows, fromPairs]
  | cons row rest ih =>
    cases index with
    | zero =>
      have tail := missing_before rest (next + 1) next (by omega)
      simp [numberRows, fromPairs, tail]
    | succ index =>
      have tail := ih index (next + 1)
      have different : next + (index + 1) ≠ next := by omega
      simp only [numberRows, fromPairs, if_neg different, List.get?_cons_succ]
      rw [show next + Nat.succ index = (next + 1) + index by omega, tail]
      cases rest.get? index <;> rfl

private theorem append_found (before after : List (Nat × α)) (key : Nat) (value : α)
    (found : fromPairs after key = some value) : fromPairs (before ++ after) key = some value := by
  induction before with
  | nil => exact found
  | cons pair later ih =>
    rcases pair with ⟨other, payload⟩
    simp [fromPairs, ih]

-- Earlier rows may even contain the same ID: the new row is the last value.
theorem root_adr0352_i5_stored_fold_row (chunks : List (List α)) (state : RowState α)
    (index : Nat) (row : α) (present : (flatten chunks).get? index = some row) :
    fromPairs (runChunks state chunks).rows (state.next + index) = some row := by
  rw [root_adr0352_i5_wrapped_row_fold]
  apply append_found
  rw [root_adr0352_i5_stored_numbered_row, present]

private theorem append_missing (before after : List (Nat × α)) (key : Nat)
    (missing : fromPairs after key = none) : fromPairs (before ++ after) key = fromPairs before key := by
  induction before with
  | nil => exact missing
  | cons pair later ih =>
    rcases pair with ⟨other, payload⟩
    simpa [fromPairs] using congrArg (fun result : Option α => match result with
      | some value => some value
      | none => if key = other then some payload else none) ih

-- Every old lookup below the next free ID is preserved by the row fold.
theorem root_adr0352_i5_stored_fold_prior (chunks : List (List α)) (state : RowState α)
    (key : Nat) (earlier : key < state.next) :
    fromPairs (runChunks state chunks).rows key = fromPairs state.rows key := by
  rw [root_adr0352_i5_wrapped_row_fold]
  exact append_missing state.rows (numberRows state.next (flatten chunks)) key
    (missing_before (flatten chunks) state.next key earlier)


private theorem append_lookup (before after : List (Nat × α)) (key : Nat) :
    fromPairs (before ++ after) key =
      match fromPairs after key with
      | some value => some value
      | none => fromPairs before key := by
  induction before with
  | nil => cases found : fromPairs after key <;> simp [fromPairs, found]
  | cons pair later ih =>
    rcases pair with ⟨other, payload⟩
    cases found : fromPairs after key <;> simp [fromPairs, ih, found]

-- Valid old row IDs are below the fresh counter, so the append lookup agrees
-- with the implementation's old-table-first union instead of assuming equality.
theorem root_adr0352_i5_stored_fold_left_union (chunks : List (List α)) (state : RowState α)
    (priorBefore : ∀ key value, fromPairs state.rows key = some value → key < state.next)
    (key : Nat) :
    fromPairs (runChunks state chunks).rows key =
      match fromPairs state.rows key with
      | some value => some value
      | none => fromPairs (numberRows state.next (flatten chunks)) key := by
  rw [root_adr0352_i5_wrapped_row_fold, append_lookup]
  cases old : fromPairs state.rows key with
  | none => cases found : fromPairs (numberRows state.next (flatten chunks)) key <;> simp [old, found]
  | some value =>
    have missing := missing_before (flatten chunks) state.next key (priorBefore key value old)
    simp [missing, old]

end NumberedStore
