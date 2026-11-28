import OwnedUnion
open BesideOwnedUnion BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideClassifiedPrefix
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
private noncomputable def owned (table : Nat → Option Nat) : Nat → Option Nat :=
  ownedTable table kinds 4 0 id skip slots place (fun _ => true) (fun _ value => value)
private def oldBase (_ : Nat) : Option Nat := some 999
private def newBase (_ : Nat) : Option Nat := some 888
example : leftUnion (owned body) oldBase 1 = some 1 := by decide
example : leftUnion (owned body) newBase 3 = some 4 := by decide
example : leftUnion (owned (adjustBeside (fun _ => 0) 3 body)) newBase 3 = some 4 := by decide
example : leftUnion (owned body) oldBase 0 = some 999 := by decide
example : leftUnion (owned body) newBase 0 = some 888 := by decide
example : leftUnion (owned body) oldBase 0 ≠ leftUnion (owned body) newBase 0 := by decide
example : leftUnion (fun _ => none) (fun _ => none) 7 = none := by decide
example : leftUnion (fun _ => some 0) oldBase 7 = some 0 := by decide
private noncomputable def sourceRound : PayloadRound Unit Nat :=
  ⟨⟨kinds, 4, false, (fun _ => false), true, (fun _ => false), (fun _ _ => true), (fun _ state => state), (fun _ state => state), [⟨0, 3, ()⟩, ⟨2, 1, ()⟩]⟩,
    fun key _ => (body key).getD 0⟩
private noncomputable def cache : PayloadCache Nat := nextPayloadCache none sourceRound
private def job : ReuseJob Nat := ⟨2, 1, 200⟩
example : ∃ ident,
    leftUnion (ownedTable (fromPairs cache.pairs) cache.kindAt cache.count 0 id skip slots place (fun _ => true) (fun _ value => value)) oldBase 3 = some ident ∧
    leftUnion (ownedTable (adjustBeside (fun _ => 0) 3 (fromPairs cache.pairs)) cache.kindAt cache.count 0 id skip slots place (fun _ => true) (fun _ value => value)) newBase 3 = some ident := by
  exact root_adr0352_i5_selected_union_first_exists_unchanged [sourceRound] cache rfl place (fun _ => true) (fun _ value => value) job 3 0 id (fun _ => 0) skip slots oldBase newBase
    (by exact List.mem_cons_of_mem _ (List.mem_cons_self _ _)) (by decide)
