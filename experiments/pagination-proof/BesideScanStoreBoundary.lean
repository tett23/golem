import BesideScanStore
open BesideScanRows BesideScanStore BesideStore BesideOwnership BesideProducer BesideReuse BesideOwnedScan BesideOwnedFirst BesideClassifiedPrefix BesideWrappedRowFold

-- Right-biased storage is deliberately different when the keys repeat.
example : fromPairs (BesideScanRows.scan 0 [(1, [8]), (1, [9])]).2 1 = some 1 := by decide
example : fromPairs (BesideScanRows.scan 0 [(1, [8]), (1, [9])]).2 1 ≠ some 0 := by decide
example : ¬ NoRepeat (pairKeys ([(1, [8]), (1, [9])] : List (Nat × List Nat))) := by simp [NoRepeat, pairKeys]
example : fromPairs (BesideScanRows.scan 0 ([] : List (Nat × List Nat))).2 1 = none := by decide
example : fromPairs (BesideScanRows.scan 7 [(2, []), (4, [9, 9]), (6, [8])]).2 4 = some 7 := by decide
example : fromPairs (BesideScanRows.scan 7 [(2, []), (4, [9, 9]), (6, [8])]).2 6 = some 9 := by decide

example : fromPairs (BesideScanRows.scan 13 [(5, []), (9, [4, 4]), (7, [8, 9]), (99, [7])]).2 7 = some 15 ∧
    ((runChunks (⟨13, [(2, 100)]⟩ : RowState Nat) [[], [4, 4], [8, 9]]).rows.drop 3).head? = some (15, 8) :=
  root_adr0352_i5_stored_scan_first_row [(5, []), (9, [4, 4])] [(99, [7])] 7 8 [9] ⟨13, [(2, 100)]⟩ (by simp [NoRepeat, pairKeys])

private def current : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | 2 => some .control
  | 3 => some .paragraph
  | _ => none
private def body : Nat → Option (List Nat)
  | 1 => some []
  | 3 => some [9, 9, 4, 1]
  | _ => none
private def slots : List CountSlot := [.wrapped, .ordinary 0, .ordinary 0, .ordinary 0]
private noncomputable def pairs (next : Nat) :=
  (BesideScanRows.scan (next + 1) ((candidateKeys body current 0 4).map fun key => (key, (body key).getD []))).2
example : pairs 0 = [(1, 1), (3, 1)] := by decide
example : fromPairs (pairs 0) 1 = some 1 := by decide
example : fromPairs (pairs 0) 3 = some 1 := by decide
example : fromPairs (pairs 7) 3 = some 8 := by decide
example : fromPairs (pairs 0) 2 = none := by decide
example : fromPairs (pairs 0) 9 = none := by decide
example : fromPairs (pairs 7) 3 = ownedFirstId body current 4 0 3 7 List.length (fun _ => false) slots :=
  root_adr0352_i5_scan_stores_owned_first body current 4 0 3 7 (fun _ => false) slots
