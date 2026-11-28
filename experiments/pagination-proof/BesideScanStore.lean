import BesideScanRows
import OwnedFirstScan
namespace BesideScanStore
open BesideScanRows BesideOwnedScan BesideOwnedFirst BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideClassifiedPrefix CausalFirstIds

private theorem scan_pairs (keys : List Nat) (rowsOf : Nat → List α) (next : Nat) :
    (BesideScanRows.scan next (keys.map fun key => (key, rowsOf key))).2 =
      numberPairs keys (fun key => (rowsOf key).length) next := by
  induction keys generalizing next with
  | nil => rfl
  | cons key later ih => simp [BesideScanRows.scan, numberPairs, ih]

private theorem scan_keys (chunks : List (Nat × List α)) (next : Nat) :
    pairKeys (BesideScanRows.scan next chunks).2 = pairKeys chunks := by
  induction chunks generalizing next with
  | nil => rfl
  | cons chunk later ih =>
    rcases chunk with ⟨key, rows⟩
    simp [BesideScanRows.scan, pairKeys, ih]

-- Unique keys connect the right-biased store with the actual rendered row.
theorem root_adr0352_i5_stored_scan_first_row
    (before after : List (Nat × List α)) (key : Nat) (row : α) (later : List α)
    (state : BesideWrappedRowFold.RowState α)
    (unique : NoRepeat (pairKeys (before ++ (key, row :: later) :: after))) :
    let cursor := BesideWrappedRowFold.runChunks state (before.map Prod.snd)
    fromPairs (BesideScanRows.scan state.next (before ++ (key, row :: later) :: after)).2 key =
      some cursor.next ∧
    ((BesideWrappedRowFold.runChunks state (before.map Prod.snd ++ [row :: later])).rows.drop
      cursor.rows.length).head? = some (cursor.next, row) := by
  dsimp only
  have entries := root_adr0352_i5_beside_entry_first_row before after key row later state
  constructor
  · apply root_adr0352_i5_unique_payload_retained _ key _
    · rw [scan_keys]
      exact unique
    · obtain ⟨bound, value⟩ := List.get?_eq_some.mp entries.1
      rw [← value]
      exact List.get_mem _ _ bound
  · exact entries.2

-- The stored values are derived from the row scan, not assumed equal.
theorem root_adr0352_i5_scan_stores_owned_first
    (body : Nat → Option (List α)) (current : Nat → Option Kind)
    (count owner target next : Nat) (skip : Nat → Bool) (slots : List CountSlot) :
    let seed := (unitContributions body current count List.length
      (classifiedParts body skip 0 (slots.take owner))).foldl Nat.add next + 1
    fromPairs (BesideScanRows.scan seed ((candidateKeys body current owner count).map
      fun key => (key, (body key).getD []))).2 target =
      ownedFirstId body current count owner target next List.length skip slots := by
  dsimp only
  rw [scan_pairs]
  have counts : (fun key => ((body key).getD []).length) = rowCount List.length body := by
    funext key
    cases eq : body key <;> simp [rowCount, eq]
  rw [counts]
  exact root_adr0352_i5_owned_first_scan body current count owner target next List.length skip slots

#print axioms root_adr0352_i5_stored_scan_first_row
#print axioms root_adr0352_i5_scan_stores_owned_first
end BesideScanStore
