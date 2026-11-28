import NumberedStore
open NumberedStore NumberedPayload BesideStore BesideWrappedRowFold

example : fromPairs (numberRows 5 ([7, 7, 9] : List Nat)) 5 = some 7 := by decide
example : fromPairs (numberRows 5 ([7, 7, 9] : List Nat)) 6 = some 7 := by decide
example : fromPairs (numberRows 5 ([7, 7, 9] : List Nat)) 7 = some 9 := by decide
example : fromPairs (numberRows 5 ([7, 7, 9] : List Nat)) 8 = none := by decide
example : fromPairs (numberRows 5 ([7, 7, 9] : List Nat)) 4 = none := by decide
example : fromPairs (numberRows 0 ([] : List Nat)) 0 = none := by decide

private def start : RowState Nat := ⟨5, [(0, 10), (0, 11), (5, 999)]⟩
private def chunks : List (List Nat) := [[1, 2], [], [3]]
example : fromPairs (runChunks start chunks).rows 5 = some 1 := by decide
example : fromPairs (runChunks start chunks).rows 6 = some 2 := by decide
example : fromPairs (runChunks start chunks).rows 7 = some 3 := by decide
example : fromPairs (runChunks start chunks).rows 0 = some 11 := by decide
example : fromPairs (runChunks start chunks).rows 8 = none := by decide
example : (runChunks start chunks).rows = [(0, 10), (0, 11), (5, 999), (5, 1), (6, 2), (7, 3)] := by decide
example : fromPairs (runChunks start []).rows 5 = some 999 := by decide
example : fromPairs (runChunks (⟨0, []⟩ : RowState Nat) [[8], [], [8, 9]]).rows 1 = some 8 := by decide

example := root_adr0352_i5_stored_numbered_row (α := Nat)
example := root_adr0352_i5_stored_fold_row (α := Nat)
example := root_adr0352_i5_stored_fold_prior (α := Nat)

-- A colliding old row violates the freshness premise: left union keeps 999.
example : ¬ (fromPairs (runChunks start chunks).rows 5 =
    match fromPairs start.rows 5 with
    | some value => some value
    | none => fromPairs (numberRows start.next (flatten chunks)) 5) := by decide
example := root_adr0352_i5_stored_fold_left_union (α := Nat)
