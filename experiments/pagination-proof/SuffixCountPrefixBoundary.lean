import SuffixCountPrefix
open BesideSuffixCountPrefix BesideOwnership BesideProducer BesideReuse BesideOwnedUnion BesideClassifiedPrefix
private def kinds (key : Nat) : Option Kind :=
  if key = 0 ∨ key = 2 then some .figure else if key = 1 ∨ key = 3 then some .paragraph else none
private def body (key : Nat) : Option Nat := if key = 1 then some 2 else if key = 3 then some 4 else none
private def slots : List CountSlot := [.wrapped, .ordinary 0, .wrapped, .ordinary 0]
private def skip (_ : Nat) : Bool := false
private def place (key : Nat) : Option Nat := if key = 0 then some 100 else if key = 2 then some 200 else none
private noncomputable def query (table : Nat → Option Nat) (key : Nat) : Option Nat :=
  leftUnion (ownedTable table kinds 4 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 999) key
example : query body 1 = some 1 := by decide
example : query (adjustBeside (fun _ => 0) 3 body) 1 = some 1 := by decide
example : query (adjustBeside (fun _ => 7) 3 body) 1 = some 1 := by decide
example : query body 3 = some 4 := by decide
example : query (adjustBeside (fun _ => 7) 3 body) 3 = some 4 := by decide
example : query (adjustBeside (fun _ => 9) 1 body) 3 = some 11 := by decide
example : query (adjustBeside (fun _ => 9) 1 body) 3 ≠ query body 3 := by decide
example : query (adjustBeside (fun _ => 9) 999 body) 1 = some 1 := by decide
example : rowCount id (adjustBeside (fun _ => 7) 3 body) 3 = 7 := by decide
example : countsFor [1] (rowCount id (adjustBeside (fun _ => 7) 3 body)) = [2] := by decide
private def typed : ∀ key, (body key).isSome = true → kinds key = some .paragraph := by
  intro key present
  by_cases first : key = 1
  · subst key; rfl
  · by_cases last : key = 3
    · subst key; rfl
    · simp [body, first, last] at present
private def job : ReuseJob Nat := ⟨0, 3, 100⟩
example : ∃ ident,
    leftUnion (ownedTable body kinds 4 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 999) 1 = some ident ∧
    leftUnion (ownedTable (adjustBeside (fun _ => 7) 3 body) kinds 4 0 id skip slots place (fun _ => true) (fun _ value => value)) (fun _ => some 888) 1 = some ident := by
  exact root_adr0352_i5_later_update_preserves_existing_union_first body kinds 4 0 typed place (fun _ => true) (fun _ value => value) job 1 3 id (fun _ => 7) skip slots (fun _ => some 999) (fun _ => some 888) (by exact List.mem_cons_self _ _) (by decide) (by decide)
