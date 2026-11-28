import WrappedRowFold
open BesideWrappedRowFold NumberedPayload BesideOwnership CausalFirstIds
private def body (key : Nat) : Option (List Nat) := if key = 1 then some [7, 7] else if key = 3 then some [9] else none
example : (runChunks (⟨10, [(4, 100)]⟩ : RowState Nat) []).next = 10 := by decide
example : (runChunks (⟨10, [(4, 100)]⟩ : RowState Nat) [[], []]).rows = [(4, 100)] := by decide
example : (runChunks (⟨10, [(4, 100)]⟩ : RowState Nat) [[7, 7], [], [9]]).next = 13 := by decide
example : (runChunks (⟨10, [(4, 100)]⟩ : RowState Nat) [[7, 7], [], [9]]).rows = [(4, 100), (10, 7), (11, 7), (12, 9)] := by decide
example : (wrappedRows 0 [1, 3] body).next = 4 := by decide
example : (wrappedRows 0 [1, 3] body).rows = [(1, 7), (2, 7), (3, 9)] := by decide
example : (wrappedRows 17 [1, 3] body).rows = [(18, 7), (19, 7), (20, 9)] := by decide
example : (wrappedRows 0 [1, 1, 3] body).next = 6 := by decide
example : (wrappedRows 0 [1, 1, 3] body).rows.map Prod.snd = [7, 7, 7, 7, 9] := by decide
example : (wrappedRows 0 [1, 4, 3] body).rows = [(1, 7), (2, 7), (3, 9)] := by decide
example : (wrappedRows 0 [3, 1] body).next = (wrappedRows 0 [1, 3] body).next := by decide
example : (wrappedRows 0 [3, 1] body).rows ≠ (wrappedRows 0 [1, 3] body).rows := by decide
example : wrappedRows 17 [1, 3] body =
    ⟨17 + (1 + ownedRows (countsFor [1, 3] (rowCount List.length body))), numberRows (17 + 1) (flatten (chunksFor [1, 3] body))⟩ :=
  root_adr0352_i5_wrapped_derived_contribution [1, 3] body 17
