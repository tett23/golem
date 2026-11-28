import Physical

namespace NumberedPayload

/-- Number already composed rows; no reshaping occurs here. -/
def numberRows {α : Type} : Nat → List α → List (Nat × α)
  | _, [] => []
  | next, row :: rest => (next, row) :: numberRows (next + 1) rest

/-- Numbering preserves every composed row in order, including duplicates. -/
theorem root_adr0352_i5_numbered_row_payload {α : Type} (rows : List α) (next : Nat) :
    (numberRows next rows).map Prod.snd = rows := by
  induction rows generalizing next with
  | nil => rfl
  | cons row rest ih => simp only [numberRows, List.map_cons, ih]

/-- Numbering a committed prefix and its remainder separately yields exactly
    the same tagged rows as numbering their concatenation. -/
theorem root_adr0352_i5_numbered_row_append {α : Type} (before after : List α) (next : Nat) :
    numberRows next (before ++ after) =
      numberRows next before ++ numberRows (next + before.length) after := by
  induction before generalizing next with
  | nil => simp [numberRows]
  | cons row rest ih =>
    simpa [numberRows, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
      congrArg (List.cons (next, row)) (ih (next + 1))

/-- The row at a valid index keeps its source payload and receives the
    initial ID plus that index. -/
theorem root_adr0352_i5_numbered_row_at {α : Type} (rows : List α) (index next : Nat) :
    (numberRows next rows).get? index =
      (rows.get? index).map (fun row => (next + index, row)) := by
  induction rows generalizing index next with
  | nil => simp [numberRows]
  | cons row rest ih =>
    cases index with
    | zero => simp [numberRows]
    | succ index => simpa [numberRows, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using ih index (next + 1)

/-- Erasing row payloads yields exactly the existing Physical ID model. -/
theorem root_adr0352_i5_numbered_row_ids {α : Type} (rows : List α) (next : Nat) :
    (numberRows next rows).map Prod.fst = PhysicalPagination.ids next rows.length := by
  induction rows generalizing next with
  | nil => rfl
  | cons row rest ih =>
    simpa [numberRows, PhysicalPagination.ids] using congrArg (List.cons next) (ih (next + 1))

/-- Taking committed rows before numbering preserves the same tagged prefix. -/
theorem root_adr0352_i5_numbered_row_take {α : Type} (rows : List α) (count next : Nat) :
    (numberRows next rows).take count = numberRows next (rows.take count) := by
  induction rows generalizing count next with
  | nil => simp [numberRows]
  | cons row rest ih =>
    cases count with
    | zero => simp [numberRows]
    | succ count => simpa [numberRows] using congrArg (List.cons (next,row)) (ih count (next+1))

/-- Empty, single, duplicate, split, oversized-prefix and absent-index cases. -/
theorem root_adr0352_i5_numbered_row_boundaries :
    numberRows 0 ([] : List Nat) = [] ∧
    numberRows 7 [3] = [(7,3)] ∧
    numberRows 7 [3,3] = [(7,3),(8,3)] ∧
    numberRows 7 ([2,5] ++ [9]) = [(7,2),(8,5),(9,9)] ∧
    (numberRows 7 [2,5]).take 0 = [] ∧
    (numberRows 7 [2,5]).take 3 = [(7,2),(8,5)] ∧
    (numberRows 7 [2,5]).get? 2 = none := by decide

end NumberedPayload
