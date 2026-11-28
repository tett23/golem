import CacheBreaker
open BesideCacheBreaker PhysicalPagination BesideCacheNumberedRows NumberedPayload BesideLaterEdits BesideOwnership BesideProducer BesideReuse BesideOwnedFirst BesideOwnedUnion BesideClassifiedPrefix BesideBodyEdits BesidePayloadRounds BesideStore
private def kinds (key : Nat) : Option Kind :=
  if key = 0 ∨ key = 3 then some .figure else if key = 1 ∨ key = 2 ∨ key = 4 then some .paragraph else none
private def body (key : Nat) : Option Nat := if key = 1 then some 2 else if key = 2 then some 3 else if key = 4 then some 4 else none
private def slots : List CountSlot := [.wrapped, .ordinary 0, .ordinary 0, .wrapped, .ordinary 0]
private def skip (_ : Nat) : Bool := false
private def place (key : Nat) : Option Nat := if key = 0 then some 100 else if key = 3 then some 200 else none
private noncomputable def sourceRound : PayloadRound Unit Nat :=
  ⟨⟨kinds, 5, false, (fun _ => false), true, (fun _ => false), (fun _ _ => true), (fun _ state => state), (fun _ state => state), [⟨0, 4, ()⟩, ⟨3, 1, ()⟩]⟩,
    fun key _ => (body key).getD 0⟩
private noncomputable def cache : PayloadCache Nat := nextPayloadCache none sourceRound
private def prior : List (BodyEdit Nat) := [⟨1, fun _ => 9⟩]
private def job : ReuseJob Nat := ⟨0, 4, 100⟩
private noncomputable def current := applyEdits (fromPairs cache.pairs) prior
private def env : Env :=
  {pagePitch := 1, fontSize := 1, capacity := 2, maxCapacity := 2, separator := 1,
   columns := 1, firstLine := 0, pitchOf := fun _ => 1, faceOf := fun _ => 1,
   headingBounds := fun _ => none, wrappedBefore := fun _ => 0, boxPadding := fun _ => none,
   firstNeed := fun _ _ _ => 0, retention := none, held := fun _ => false}
private def raw (_ : St) (_ start : Nat) : List (Line × Nat) :=
  ([((⟨999, [], 0⟩ : Line), 1), (⟨998, [], 0⟩, 2), (⟨997, [], 0⟩, 3)] : List (Line × Nat)).drop start
private def change (st : St) (before start : Nat) (_ : Nat) := before + (raw st before start).length
private noncomputable def tables := recomputedTables current kinds 5 0 id skip slots place (fun _ => true) (fun _ value => value) 2 change (fun _ _ _ _ => some 888)
private noncomputable def breaker := cachedBreaker tables 2 raw
example : tables (initial env) 0 0 2 = some 10 := by decide
example : tables (initial env) 2 2 2 = some 10 := by decide
example : lineIds ((breaker (initial env) 0 0).map Prod.fst) = [10, 11, 12] := by decide
example : lineIds ((breaker (initial env) 2 2).map Prod.fst) = [12] := by decide
example : breaker (initial env) 3 3 = [] := by decide
example : (breaker (initial env) 0 0).map Prod.snd = [1, 2, 3] := by decide
example : cachedBreaker (fun _ _ _ _ => none) 2 raw (initial env) 0 0 = [] := by decide
example : physicalRows [(10, ((⟨999, [⟨50, 2⟩], -3⟩ : Line), 7)), (11, (⟨998, [], 2⟩, 9))] =
    [(⟨10, [⟨50, 2⟩], -3⟩, 7), (⟨11, [], 2⟩, 9)] := by decide
example : (match parts env none breaker 3 0 (fun _ => true) id none ⟨1, 1, false⟩ true 0 0 (initial env) with
    | .ok finished => text finished == [10, 11, 12]
    | .error _ => false) = true := by decide
example : lineIds ((breaker (initial env) 0 2).map Prod.fst) ≠ [12] := by decide
example : (match parts {env with columns := 2} none breaker 3 0 (fun _ => true) id none ⟨1, 1, false⟩ true 0 0 (initial {env with columns := 2}) with
    | .ok finished => text finished == [10, 11, 12]
    | .error _ => false) = true := by decide
example : (match parts env none (cachedBreaker tables 2 (fun _ _ _ => [])) 0 0 (fun _ => true) id none ⟨1, 1, false⟩ true 0 0 (initial env) with
    | .ok finished => text finished == []
    | .error _ => false) = true := by decide
example : let oldTable := leftUnion (ownedTable current cache.kindAt cache.count 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 999)
    ∃ ident, oldTable 2 = some ident ∧
      (∀ at' before start,
        lineIds ((breaker at' before start).map Prod.fst) = ids (ident + before) (breaker at' before start).length ∧
        (breaker at' before start).map (fun row => (row.1.notes, row.1.overhang, row.2)) =
          (raw at' before start).map (fun row => (row.1.notes, row.1.overhang, row.2))) ∧
      ∀ limit keep isStart start before at' final,
      parts env none breaker 3 0 (fun _ => true) id limit keep isStart start before at' = .ok final →
      ∃ consumed, Step at' final (ids (ident + before) consumed) [] := by
  exact root_adr0352_i5_cache_backed_parts_lines [sourceRound] cache rfl prior place (fun _ => true) (fun _ value => value) job 2 0 id skip slots (fun _ => some 999) (fun _ _ _ _ => some 888) change env none raw 3 0 (fun _ => true) id (fun st => Step.refl st) (by exact List.mem_cons_self _ _) (by decide)
