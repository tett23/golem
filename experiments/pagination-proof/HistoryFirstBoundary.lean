import HistoryFirst
open BesideHistoryFirst BesideBodyEdits BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideClassifiedPrefix BesideOwnedUnion
private def kinds : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | 2 => some .figure
  | 3 => some .paragraph
  | _ => none
private def body : Nat → Option Nat
  | 1 => some 2
  | 3 => some 4
  | _ => none
private def slots : List CountSlot := [.wrapped, .ordinary 0, .wrapped, .ordinary 0]
private def skip (_ : Nat) : Bool := false
private def place (key : Nat) : Option Nat := if key = 0 then some 100 else if key = 2 then some 200 else none
private def edits : List (BodyEdit Nat) := [⟨1, fun _ => 9⟩, ⟨3, fun _ => 0⟩]
private noncomputable def current : Nat → Option Nat := applyEdits body edits
private noncomputable def query (table : Nat → Option Nat) (key : Nat) : Option Nat :=
  leftUnion (ownedTable table kinds 4 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 999) key
example : query body 3 = some 4 := by decide
example : query current 3 = some 11 := by decide
example : query (adjustBeside (fun _ => 7) 3 current) 3 = some 11 := by decide
example : query (applyEdits body [⟨3, fun _ => 0⟩]) 3 = some 4 := by decide
example : query current 1 = some 1 := by decide
example : query current 0 = some 999 := by decide
example : query (applyEdits body []) 3 = some 4 := by decide
example : candidateKeys current kinds 0 4 = [1] := by decide
example : candidateKeys current kinds 2 4 = [3] := by decide
private noncomputable def sourceRound : PayloadRound Unit Nat :=
  ⟨⟨kinds, 4, false, (fun _ => false), true, (fun _ => false), (fun _ _ => true), (fun _ state => state), (fun _ state => state), [⟨0, 3, ()⟩, ⟨2, 1, ()⟩]⟩,
    fun key _ => (body key).getD 0⟩
private noncomputable def cache : PayloadCache Nat := nextPayloadCache none sourceRound
private def job : ReuseJob Nat := ⟨2, 1, 200⟩
example : ∃ ident,
    leftUnion (ownedTable (applyEdits (fromPairs cache.pairs) edits) cache.kindAt cache.count 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 999) 3 = some ident ∧
    leftUnion (ownedTable (adjustBeside (fun _ => 7) 3 (applyEdits (fromPairs cache.pairs) edits)) cache.kindAt cache.count 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 888) 3 = some ident := by
  exact root_adr0352_i5_history_selected_union_exists_stable [sourceRound] cache rfl edits place (fun _ => true) (fun _ value => value) job 3 0 id (fun _ => 7) skip slots (fun _ => some 999) (fun _ => some 888)
    (by exact List.mem_cons_of_mem _ (List.mem_cons_self _ _)) (by decide)
private def malformed (key : Nat) : Option Nat := if key = 2 then some 0 else body key
example : query malformed 3 = some 8 := by decide
example : query (adjustBeside (fun _ => 9) 3 malformed) 3 = some 13 := by decide
example : query (adjustBeside (fun _ => 9) 3 malformed) 3 ≠ query malformed 3 := by decide
