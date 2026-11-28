import NumberedEventStore
open NumberedEventStore NumberedPayload BesideStore BesideWrappedRowFold
private def events : List (RowEvent Nat) := [.reserve 1, .rows [7, 8], .reserve 2, .rows [9]]
private noncomputable def result : RowState Nat := runEvents ⟨5, []⟩ events
example : result.next = 11 := by decide
example : result.rows = [(6, 7), (7, 8), (10, 9)] := by decide
example : fromPairs result.rows 5 = none := by decide
example : fromPairs result.rows 6 = some 7 := by decide
example : fromPairs result.rows 7 = some 8 := by decide
example : fromPairs result.rows 8 = none := by decide
example : fromPairs result.rows 9 = none := by decide
example : fromPairs result.rows 10 = some 9 := by decide
example : fromPairs result.rows 11 = none := by decide
example : (runEvents (⟨0, []⟩ : RowState Nat) [.reserve 0, .rows [], .reserve 3]).next = 3 := by decide
example : Fresh result :=
  root_adr0352_i5_event_fold_fresh ⟨5, []⟩ events (by intro key value h; cases h)
example (key : Nat) := root_adr0352_i5_initial_events_left_union events [[3], [], [4]] 5 key
example : eventCount events = 6 := by decide
example : eventPayload events = [7, 8, 9] := by decide
example (input : List (RowEvent Nat)) (initial : RowState Nat) := root_adr0352_i5_event_counter input initial
example (input : List (RowEvent Nat)) (initial : RowState Nat) := root_adr0352_i5_event_payload_order input initial
