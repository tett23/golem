import BesideScanRows
open BesideScanRows BesideWrappedRowFold NumberedPayload

example : scan 7 ([] : List (Nat × List Nat)) = (7, []) := by decide
example : scan 7 [(4, ([] : List Nat))] = (7, [(4, 7)]) := by decide
example : scan 7 [(4, [8, 8])] = (9, [(4, 7)]) := by decide
example : scan 7 [(4, []), (8, [2, 3]), (11, [])] = (9, [(4, 7), (8, 7), (11, 9)]) := by decide
example : scan 10 [(2, [8, 8]), (2, []), (7, [1])] = (13, [(2, 10), (2, 12), (7, 12)]) := by decide
example : scan 0 [(5, [1, 2]), (8, [4])] = (3, [(5, 0), (8, 2)]) := by decide
example : scan 0 [(8, [4]), (5, [1, 2])] = (3, [(8, 0), (5, 1)]) := by decide
example : (scan 0 [(5, [1, 2]), (8, [4])]).1 = (scan 0 [(8, [4]), (5, [1, 2])]).1 := by decide
example : (scan 0 [(5, [1, 2]), (8, [4])]).2 ≠ (scan 0 [(8, [4]), (5, [1, 2])]).2 := by decide
example : (scan 17 [(5, [1, 1]), (8, [2, 2, 2])]).2.get? 2 = none := by decide

example : (scan 13 [(5, []), (9, [4, 4]), (7, [8, 9]), (99, [7])]).2.get? 2 =
    some (7, (runChunks (⟨13, [(2, 100)]⟩ : RowState Nat) [[], [4, 4]]).next) :=
  root_adr0352_i5_beside_entry_fold [(5, []), (9, [4, 4])] [(99, [7])] 7 [8, 9] ⟨13, [(2, 100)]⟩

example : (scan 13 [(5, []), (9, [4, 4]), (7, [8, 9]), (99, [7])]).2.get? 2 = some (7, 15) ∧
    ((runChunks (⟨13, [(2, 100)]⟩ : RowState Nat) [[], [4, 4], [8, 9]]).rows.drop 3).head? = some (15, 8) :=
  root_adr0352_i5_beside_entry_first_row [(5, []), (9, [4, 4])] [(99, [7])] 7 8 [9] ⟨13, [(2, 100)]⟩

example : (runChunks (⟨13, [(2, 100)]⟩ : RowState Nat) [[], [4, 4], [8, 9]]).rows =
    [(2, 100), (13, 4), (14, 4), (15, 8), (16, 9)] := by decide
example : (scan 13 [(5, []), (9, [4, 4]), (7, [8, 9])]).1 =
    (runChunks (⟨13, [(2, 100)]⟩ : RowState Nat) [[], [4, 4], [8, 9]]).next := by decide
