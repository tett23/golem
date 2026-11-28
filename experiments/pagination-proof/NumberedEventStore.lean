import NumberedStoreFresh
namespace NumberedEventStore
open NumberedStore NumberedStoreFresh NumberedPayload BesideStore BesideWrappedRowFold

inductive RowEvent (α : Type) where
  | reserve : Nat → RowEvent α
  | rows : List α → RowEvent α

noncomputable def stepEvent (state : RowState α) : RowEvent α → RowState α
  | .reserve count => ⟨state.next + count, state.rows⟩
  | .rows rows => addChunk state rows
noncomputable def runEvents (state : RowState α) (events : List (RowEvent α)) : RowState α :=
  events.foldl stepEvent state

def Fresh (state : RowState α) : Prop :=
  ∀ key value, fromPairs state.rows key = some value → key < state.next

theorem root_adr0352_i5_event_step_fresh (state : RowState α) (event : RowEvent α)
    (prior : Fresh state) : Fresh (stepEvent state event) := by
  cases event with
  | reserve count =>
    intro key value found
    have before := prior key value found
    change key < state.next + count
    omega
  | rows rows =>
    intro key value found
    have bound := root_adr0352_i5_fold_fresh_ids [rows] state prior key value
    simpa [runChunks, List.foldl, addChunk] using bound found

theorem root_adr0352_i5_event_fold_fresh (state : RowState α) (events : List (RowEvent α))
    (prior : Fresh state) : Fresh (runEvents state events) := by
  induction events generalizing state with
  | nil => exact prior
  | cons event _rest ih =>
    apply ih
    exact root_adr0352_i5_event_step_fresh state event prior

theorem root_adr0352_i5_initial_events_left_union (events : List (RowEvent α))
    (after : List (List α)) (seed key : Nat) :
    let state := runEvents (⟨seed, []⟩ : RowState α) events
    fromPairs (runChunks state after).rows key =
      match fromPairs state.rows key with
      | some value => some value
      | none => fromPairs (numberRows state.next (flatten after)) key := by
  dsimp only
  apply root_adr0352_i5_stored_fold_left_union
  exact root_adr0352_i5_event_fold_fresh ⟨seed, []⟩ events (by intro key value h; cases h)


def eventCount : List (RowEvent α) → Nat
  | [] => 0
  | .reserve count :: later => count + eventCount later
  | .rows rows :: later => rows.length + eventCount later

def eventPayload : List (RowEvent α) → List α
  | [] => []
  | .reserve _ :: later => eventPayload later
  | .rows rows :: later => rows ++ eventPayload later

theorem root_adr0352_i5_event_counter (events : List (RowEvent α)) (state : RowState α) :
    (runEvents state events).next = state.next + eventCount events := by
  induction events generalizing state with
  | nil => simp [runEvents, eventCount]
  | cons event later ih =>
    cases event with
    | reserve count => simpa [runEvents, stepEvent, eventCount, Nat.add_assoc] using ih (stepEvent state (.reserve count))
    | rows rows => simpa [runEvents, stepEvent, addChunk, eventCount, Nat.add_assoc] using ih (stepEvent state (.rows rows))

theorem root_adr0352_i5_event_payload_order (events : List (RowEvent α)) (state : RowState α) :
    (runEvents state events).rows.map Prod.snd = state.rows.map Prod.snd ++ eventPayload events := by
  induction events generalizing state with
  | nil => simp [runEvents, eventPayload]
  | cons event later ih =>
    cases event with
    | reserve count => simpa [runEvents, stepEvent, eventPayload] using ih (stepEvent state (.reserve count))
    | rows rows => simpa [runEvents, stepEvent, addChunk, eventPayload, List.map_append,
        root_adr0352_i5_numbered_row_payload, List.append_assoc] using ih (stepEvent state (.rows rows))

end NumberedEventStore
