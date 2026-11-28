import NumberedPayload
import SelectedCountPrefix
namespace BesideWrappedRowFold
open NumberedPayload BesideOwnership CausalFirstIds
structure RowState (α : Type) where
  next : Nat
  rows : List (Nat × α)
noncomputable def addChunk (state : RowState α) (chunk : List α) : RowState α :=
  ⟨state.next + chunk.length, state.rows ++ numberRows state.next chunk⟩
noncomputable def runChunks (state : RowState α) (chunks : List (List α)) : RowState α :=
  chunks.foldl addChunk state
noncomputable def flatten : List (List α) → List α
  | [] => []
  | chunk :: later => chunk ++ flatten later

theorem root_adr0352_i5_wrapped_row_fold (chunks : List (List α)) (state : RowState α) :
    runChunks state chunks = ⟨state.next + (flatten chunks).length,
      state.rows ++ numberRows state.next (flatten chunks)⟩ := by
  induction chunks generalizing state with
  | nil => cases state; simp [runChunks, flatten, numberRows]
  | cons chunk later ih =>
    change runChunks (addChunk state chunk) later = _
    rw [ih]
    cases state with
    | mk first earlier =>
      simp [addChunk, flatten, List.length_append, Nat.add_assoc, root_adr0352_i5_numbered_row_append, List.append_assoc]

noncomputable def chunksFor (keys : List Nat) (body : Nat → Option (List α)) : List (List α) :=
  keys.map (fun key => (body key).getD [])
private theorem flattened_rows_count (keys : List Nat) (body : Nat → Option (List α)) :
    (flatten (chunksFor keys body)).length = ownedRows (countsFor keys (rowCount List.length body)) := by
  induction keys with
  | nil => rfl
  | cons key later ih =>
    cases value : body key with
    | none => simpa [chunksFor, flatten, countsFor, rowCount, value, ownedRows] using ih
    | some rows => simpa [chunksFor, flatten, countsFor, rowCount, value, ownedRows, List.length_append] using congrArg (Nat.add rows.length) ih

noncomputable def wrappedRows (first : Nat) (keys : List Nat) (body : Nat → Option (List α)) : RowState α :=
  runChunks ⟨first + 1, []⟩ (chunksFor keys body)

theorem root_adr0352_i5_wrapped_derived_contribution (keys : List Nat) (body : Nat → Option (List α)) (first : Nat) :
    wrappedRows first keys body =
      ⟨first + (1 + ownedRows (countsFor keys (rowCount List.length body))),
        numberRows (first + 1) (flatten (chunksFor keys body))⟩ := by
  unfold wrappedRows
  rw [root_adr0352_i5_wrapped_row_fold, flattened_rows_count]
  simp [Nat.add_assoc]
end BesideWrappedRowFold
