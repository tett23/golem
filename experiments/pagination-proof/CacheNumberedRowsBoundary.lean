import CacheNumberedRows
open BesideCacheNumberedRows NumberedPayload BesideLaterEdits BesideOwnership BesideProducer BesideReuse BesideOwnedFirst BesideOwnedUnion BesideClassifiedPrefix BesideBodyEdits BesidePayloadRounds BesideStore
private def kinds (key : Nat) : Option Kind :=
  if key = 0 ∨ key = 3 then some .figure else if key = 1 ∨ key = 2 ∨ key = 4 then some .paragraph else none
private def body (key : Nat) : Option Nat := if key = 1 then some 2 else if key = 2 then some 3 else if key = 4 then some 4 else none
private def slots : List CountSlot := [.wrapped, .ordinary 0, .ordinary 0, .wrapped, .ordinary 0]
private def skip (_ : Nat) : Bool := false
private def place (key : Nat) : Option Nat := if key = 0 then some 100 else if key = 3 then some 200 else none
example : numberedFrom (fun _ => none) 1 0 ([7, 7, 9] : List Nat) = none := by decide
example : numberedFrom (fun _ => none) 1 0 ([] : List Nat) = none := by decide
example : numberedFrom (fun _ => some 10) 1 2 ([] : List Nat) = some [] := by decide
example : numberedFrom (fun _ => some 10) 1 2 ([7, 7, 9] : List Nat) = some [(12, 7), (13, 7), (14, 9)] := by decide
example : (numberedFrom (fun _ => some 10) 1 2 ([7, 7, 9] : List Nat)).map (fun rows => rows.map Prod.fst) = some [12, 13, 14] := by decide
example : (numberedFrom (fun _ => some 10) 1 2 ([7, 7, 9] : List Nat)).map (fun rows => rows.map Prod.snd) = some [7, 7, 9] := by decide
example : numberRows 10 ([100, 101] ++ [7, 7, 9] : List Nat) = [(10, 100), (11, 101), (12, 7), (13, 7), (14, 9)] := by decide
example : numberRows 12 ([7, 7, 9] : List Nat) ≠ numberRows 12 [7, 9, 7] := by decide
private noncomputable def sourceRound : PayloadRound Unit Nat :=
  ⟨⟨kinds, 5, false, (fun _ => false), true, (fun _ => false), (fun _ _ => true), (fun _ state => state), (fun _ state => state), [⟨0, 4, ()⟩, ⟨3, 1, ()⟩]⟩,
    fun key _ => (body key).getD 0⟩
private noncomputable def cache : PayloadCache Nat := nextPayloadCache none sourceRound
private def prior : List (BodyEdit Nat) := [⟨1, fun _ => 9⟩]
private def job : ReuseJob Nat := ⟨0, 4, 100⟩
private noncomputable def current := applyEdits (fromPairs cache.pairs) prior
private noncomputable def updated := applyEdits current (suffixPrefixEdits (candidateKeys current cache.kindAt job.owner cache.count) 2 1 (fun _ _ => 5))
private noncomputable def afterTable := leftUnion (ownedTable updated kinds 5 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 888)
example : afterTable 2 = some 10 := by decide
example : updated 2 = some 5 := by decide
example : numberedFrom afterTable 2 2 ([7, 7, 9] : List Nat) = some [(12, 7), (13, 7), (14, 9)] := by decide
example : let oldTable := leftUnion (ownedTable current cache.kindAt cache.count 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 999)
    ∃ ident tagged, oldTable 2 = some ident ∧ afterTable 2 = some ident ∧
      numberedFrom afterTable 2 2 ([7, 7, 9] : List Nat) = some tagged ∧
      numberRows ident ([100, 101] ++ [7, 7, 9] : List Nat) = numberRows ident [100, 101] ++ tagged ∧
      tagged.map Prod.fst = PhysicalPagination.ids (ident + 2) 3 ∧ tagged.map Prod.snd = [7, 7, 9] ∧
      (∀ index, tagged.get? index = ([7, 7, 9].get? index).map (fun row => (ident + 2 + index, row))) := by
  exact root_adr0352_i5_history_cache_numbered_rows [sourceRound] cache rfl prior place (fun _ => true) (fun _ value => value) job 2 0 1 (fun _ _ => 5) id skip slots (fun _ => some 999) (fun _ => some 888) [100, 101] [7, 7, 9] (by exact List.mem_cons_self _ _) (by decide)
