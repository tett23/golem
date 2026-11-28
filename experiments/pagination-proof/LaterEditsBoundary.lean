import LaterEdits
open BesideLaterEdits BesideOwnership BesideProducer BesideReuse BesideOwnedFirst BesideOwnedUnion BesideClassifiedPrefix BesideBodyEdits BesidePayloadRounds BesideStore
private def kinds (key : Nat) : Option Kind :=
  if key = 0 ∨ key = 3 then some .figure else if key = 1 ∨ key = 2 ∨ key = 4 then some .paragraph else none
private def body (key : Nat) : Option Nat := if key = 1 then some 2 else if key = 2 then some 3 else if key = 4 then some 4 else none
private def slots : List CountSlot := [.wrapped, .ordinary 0, .ordinary 0, .wrapped, .ordinary 0]
private def skip (_ : Nat) : Bool := false
private def place (key : Nat) : Option Nat := if key = 0 then some 100 else if key = 3 then some 200 else none
private noncomputable def edits (target attempts : Nat) := suffixPrefixEdits (candidateKeys body kinds 0 5) target attempts (fun _ _ => 7)
private noncomputable def query (table : Nat → Option Nat) (key : Nat) : Option Nat :=
  leftUnion (ownedTable table kinds 5 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 999) key
example : (edits 1 0).map BodyEdit.target = [] := by decide
example : (edits 1 1).map BodyEdit.target = [1] := by decide
example : (edits 1 2).map BodyEdit.target = [1, 2] := by decide
example : (edits 1 9).map BodyEdit.target = [1, 2] := by decide
example : applyEdits body (edits 1 2) 1 = some 7 := by decide
example : applyEdits body (edits 1 2) 2 = some 7 := by decide
example : applyEdits body (edits 1 2) 4 = some 4 := by decide
example : query body 1 = some 1 := by decide
example : query (applyEdits body (edits 1 2)) 1 = some 1 := by decide
example : query body 2 = some 3 := by decide
example : query (applyEdits body (edits 1 2)) 2 = some 8 := by decide
example : query (applyEdits body (edits 2 9)) 2 = some 3 := by decide
private noncomputable def sourceRound : PayloadRound Unit Nat :=
  ⟨⟨kinds, 5, false, (fun _ => false), true, (fun _ => false), (fun _ _ => true), (fun _ state => state), (fun _ state => state), [⟨0, 4, ()⟩, ⟨3, 1, ()⟩]⟩,
    fun key _ => (body key).getD 0⟩
private noncomputable def cache : PayloadCache Nat := nextPayloadCache none sourceRound
private def prior : List (BodyEdit Nat) := [⟨1, fun _ => 9⟩]
private def job : ReuseJob Nat := ⟨0, 4, 100⟩
example : query (applyEdits (fromPairs cache.pairs) prior) 2 = some 10 := by decide
example : let current := applyEdits (fromPairs cache.pairs) prior
    ∃ ident,
      leftUnion (ownedTable current cache.kindAt cache.count 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 999) 2 = some ident ∧
      leftUnion (ownedTable (applyEdits current (suffixPrefixEdits (candidateKeys current cache.kindAt job.owner cache.count) 2 9 (fun _ _ => 7))) cache.kindAt cache.count 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 888) 2 = some ident := by
  exact root_adr0352_i5_history_suffix_prefix_exists_same [sourceRound] cache rfl prior place (fun _ => true) (fun _ value => value) job 2 0 9 (fun _ _ => 7) id skip slots (fun _ => some 999) (fun _ => some 888) (by exact List.mem_cons_self _ _) (by decide)
