/- Root ADR 0352: connect the besideFirsts scan to its row fold.
   The table is a list here; general Built/Map correspondence remains open. -/
import WrappedRowFold
namespace BesideScanRows
open BesideWrappedRowFold NumberedPayload

/-- `mapAccumL` used by besideFirsts, retaining each unit's key. -/
noncomputable def scan (next : Nat) : List (Nat × List α) → Nat × List (Nat × Nat)
  | [] => (next, [])
  | (key, rows) :: later =>
    let rest := scan (next + rows.length) later
    (rest.1, (key, next) :: rest.2)

/-- The scan entry of a unit is the counter reached by the actual row fold
    over its preceding chunks; the old placed prefix may be arbitrary. -/
theorem root_adr0352_i5_beside_entry_fold (before after : List (Nat × List α))
    (key : Nat) (rows : List α) (state : RowState α) :
    (scan state.next (before ++ (key, rows) :: after)).2.get? before.length =
      some (key, (runChunks state (before.map Prod.snd)).next) := by
  induction before generalizing state with
  | nil => simp [scan, runChunks]
  | cons chunk earlier ih =>
    rcases chunk with ⟨other, body⟩
    simpa [scan, runChunks, addChunk] using ih (addChunk state body)

private theorem drop_before (before after : List α) :
    (before ++ after).drop before.length = after := by
  induction before with
  | nil => rfl
  | cons _ earlier ih => simpa [List.drop] using ih

/-- The ID of the first rendered row of that unit agrees with its table
    entry. Empty earlier chunks and duplicate payloads are allowed. -/
theorem root_adr0352_i5_beside_entry_first_row (before after : List (Nat × List α))
    (key : Nat) (row : α) (later : List α) (state : RowState α) :
    let cursor := runChunks state (before.map Prod.snd)
    (scan state.next (before ++ (key, row :: later) :: after)).2.get? before.length =
      some (key, cursor.next) ∧
    ((runChunks state (before.map Prod.snd ++ [row :: later])).rows.drop cursor.rows.length).head? =
      some (cursor.next, row) := by
  constructor
  · exact root_adr0352_i5_beside_entry_fold before after key (row :: later) state
  · simp [runChunks, List.foldl_append, addChunk, numberRows, drop_before]

#print axioms root_adr0352_i5_beside_entry_fold
#print axioms root_adr0352_i5_beside_entry_first_row
end BesideScanRows
