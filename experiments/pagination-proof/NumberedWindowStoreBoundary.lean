import NumberedWindowStore
open NumberedWindowStore NumberedEventStore NumberedPayload BesideStore BesideWrappedRowFold
private def table : Nat → Option Nat := fromPairs [(0, 5), (2, 7), (2, 8), (3, 0), (5, 9), (6, 11), (7, 10)]
private noncomputable def selected : RowState Nat := runEvents ⟨1, []⟩ (windowEvents table 1 5)
example : eventCount (windowEvents table 1 5) = 5 := by decide
example : windowRows table 1 5 = [(2, 8), (3, 0), (5, 9)] := by decide
example : selected.next = 6 := by decide
example : selected.rows = [(2, 8), (3, 0), (5, 9)] := by decide
example : fromPairs selected.rows 0 = none := by decide
example : fromPairs selected.rows 1 = none := by decide
example : fromPairs selected.rows 2 = some 8 := by decide
example : fromPairs selected.rows 3 = some 0 := by decide
example : fromPairs selected.rows 5 = some 9 := by decide
example : fromPairs selected.rows 6 = none := by decide
example : fromPairs selected.rows 7 = none := by decide
example : windowRows table 1 0 = [] := by decide
example : fromPairs (runEvents (⟨1, []⟩ : RowState Nat) (windowEvents table 1 0)).rows 1 = none := by decide
example : fromPairs (runEvents (⟨0, []⟩ : RowState Nat) (windowEvents table 0 1)).rows 0 = some 5 := by decide
example : fromPairs (runEvents (⟨2, []⟩ : RowState Nat) (windowEvents table 2 1)).rows 2 = some 8 := by decide
example := root_adr0352_i5_window_counter (α := Nat)
example := root_adr0352_i5_window_rows (α := Nat)
example := root_adr0352_i5_window_store (α := Nat)
example := root_adr0352_i5_window_rebuild_fresh (α := Nat)
example := root_adr0352_i5_window_rebuild_after_events (α := Nat)
