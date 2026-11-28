import NumberedEventStore
namespace NumberedWindowStore
open NumberedEventStore NumberedPayload BesideStore BesideWrappedRowFold

def eventAt (table : Nat → Option α) (key : Nat) : RowEvent α :=
  match table key with
  | none => .reserve 1
  | some value => .rows [value]

def windowEvents (table : Nat → Option α) : Nat → Nat → List (RowEvent α)
  | _, 0 => []
  | start, count + 1 => eventAt table start :: windowEvents table (start + 1) count

def windowRows (table : Nat → Option α) : Nat → Nat → List (Nat × α)
  | _, 0 => []
  | start, count + 1 =>
    match table start with
    | none => windowRows table (start + 1) count
    | some value => (start, value) :: windowRows table (start + 1) count

theorem root_adr0352_i5_window_counter (table : Nat → Option α) (start count : Nat) :
    eventCount (windowEvents table start count) = count := by
  induction count generalizing start with
  | zero => rfl
  | succ count ih =>
    cases value : table start <;> simp [windowEvents, eventAt, eventCount, value, ih, Nat.add_comm]

theorem root_adr0352_i5_window_rows (table : Nat → Option α) (count : Nat) (state : RowState α) :
    (runEvents state (windowEvents table state.next count)).rows =
      state.rows ++ windowRows table state.next count := by
  induction count generalizing state with
  | zero => simp [windowEvents, runEvents, windowRows]
  | succ count ih =>
    cases state with
    | mk next prior =>
      cases value : table next with
      | none =>
        simpa [windowEvents, eventAt, value, runEvents, stepEvent, windowRows] using ih ⟨next + 1, prior⟩
      | some row =>
        simpa [windowEvents, eventAt, value, runEvents, stepEvent, addChunk, numberRows,
          windowRows, List.append_assoc] using ih ⟨next + 1, prior ++ [(next, row)]⟩

private theorem window_lookup (table : Nat → Option α) (start count key : Nat) :
    fromPairs (windowRows table start count) key =
      if start ≤ key ∧ key < start + count then table key else none := by
  induction count generalizing start with
  | zero => simp [windowRows, fromPairs, show ¬(start ≤ key ∧ key < start) by omega]
  | succ count ih =>
    by_cases same : key = start
    · subst key
      have tailNone : fromPairs (windowRows table (start + 1) count) start = none := by
        rw [ih]
        simp [show ¬(start + 1 ≤ start ∧ start < start + 1 + count) by omega]
      cases value : table start <;>
        simp [windowRows, value, fromPairs, tailNone, show start < start + (count + 1) by omega]
    · have ranges : (start + 1 ≤ key ∧ key < start + 1 + count) =
          (start ≤ key ∧ key < start + (count + 1)) := propext (by omega)
      by_cases inside : start ≤ key ∧ key < start + (count + 1)
      <;> cases value : table start
      <;> cases result : table key
      <;> simp [windowRows, value, fromPairs, ih, ranges, same, inside, result]

theorem root_adr0352_i5_window_store (table : Nat → Option α) (start count key : Nat) :
    fromPairs (runEvents (⟨start, []⟩ : RowState α) (windowEvents table start count)).rows key =
      if start ≤ key ∧ key < start + count then table key else none := by
  rw [root_adr0352_i5_window_rows]
  simpa using window_lookup table start count key


theorem root_adr0352_i5_window_rebuild_fresh (state : RowState α)
    (fresh : Fresh state) (key : Nat) :
    fromPairs (runEvents (⟨0, []⟩ : RowState α)
      (windowEvents (fromPairs state.rows) 0 state.next)).rows key = fromPairs state.rows key := by
  rw [root_adr0352_i5_window_store]
  by_cases inside : key < state.next
  · simp [inside]
  · have missing : fromPairs state.rows key = none := by
      cases found : fromPairs state.rows key with
      | none => rfl
      | some value => exact False.elim (inside (fresh key value found))
    simp [inside, missing]

theorem root_adr0352_i5_window_rebuild_after_events (events : List (RowEvent α))
    (seed key : Nat) :
    let state := runEvents (⟨seed, []⟩ : RowState α) events
    fromPairs (runEvents (⟨0, []⟩ : RowState α)
      (windowEvents (fromPairs state.rows) 0 state.next)).rows key = fromPairs state.rows key := by
  dsimp only
  apply root_adr0352_i5_window_rebuild_fresh
  exact root_adr0352_i5_event_fold_fresh ⟨seed, []⟩ events (by intro key value h; cases h)

end NumberedWindowStore
