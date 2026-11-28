import OwnedRows
open BesideOwnedRows BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues
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
private def jobs : List (ReuseJob Nat) := [⟨0, 3, 100⟩, ⟨2, 1, 200⟩]
private def first (owner : Nat) : Nat := if owner = 0 then 1 else 4
example : allKeys body kinds 4 jobs = [1, 3] := by decide
example : allPairs body kinds 4 id first jobs = [(1, 1), (3, 4)] := by decide
example : fromPairs (allPairs body kinds 4 id first jobs) 1 = some 1 := by decide
example : fromPairs (allPairs body kinds 4 id first jobs) 3 = some 4 := by decide
example : fromPairs (allPairs body kinds 4 id first jobs) 2 = none := by decide
example : allPairs body kinds 4 id first ([] : List (ReuseJob Nat)) = [] := by decide
example : allKeys body kinds 4 jobs.reverse = [3, 1] := by decide
example : allKeys body kinds 4 [⟨0, 3, 100⟩, ⟨0, 3, 200⟩] = [1, 1] := by decide
example : allPairs body kinds 4 id (fun _ => 1) jobs = [(1, 1), (3, 1)] := by decide
private def malformed (key : Nat) : Option Nat := if key = 2 then some 5 else body key
example : allKeys malformed kinds 4 jobs = [1, 2, 3, 3] := by decide
private noncomputable def sourceRound : PayloadRound Unit Nat :=
  ⟨⟨kinds, 4, false, (fun _ => false), true, (fun _ => false), (fun _ _ => true), (fun _ state => state), (fun _ state => state), [⟨0, 3, ()⟩, ⟨2, 1, ()⟩]⟩,
    fun key _ => (body key).getD 0⟩
private noncomputable def cache : PayloadCache Nat := nextPayloadCache none sourceRound
private def place (key : Nat) : Option Nat := if key = 0 then some 100 else if key = 2 then some 200 else none
private def job : ReuseJob Nat := ⟨2, 1, 200⟩
example : fromPairs (allPairs (fromPairs cache.pairs) cache.kindAt cache.count id first
    (valueJobs (fun _ => true) (fun _ value => value) cache.count (figurePairs cache.kindAt place 0 cache.count))) 3 = some 4 := by
  exact root_adr0352_i5_reached_owned_pair_retained [sourceRound] cache rfl place (fun _ => true) (fun _ value => value) id first job 3 4
    (by exact List.mem_cons_of_mem _ (List.mem_cons_self _ _)) (by decide)
