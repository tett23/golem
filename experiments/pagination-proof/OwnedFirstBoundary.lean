import OwnedFirst
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideClassifiedPrefix BesideOwnedFirst

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
private def no (_ : Nat) : Bool := false
private def slots : List CountSlot := [.wrapped, .ordinary 0, .wrapped, .ordinary 0]
example : ownedFirstId body kinds 4 0 1 0 id no slots = some 1 := by decide

example : ownedFirstId body kinds 4 2 3 0 id no slots = some 4 := by decide
example : ownedFirstId (adjustBeside (fun _ => 9) 3 body) kinds 4 2 3 0 id no slots = some 4 := by decide
example : ownedFirstId (adjustBeside (fun _ => 0) 1 body) kinds 4 0 1 0 id no slots = some 1 := by decide
example : ownedFirstId body kinds 4 0 3 0 id no slots = none := by decide
example : ownedFirstId body kinds 4 2 1 0 id no slots = none := by decide
example : ownedFirstId (adjustBeside (fun _ => 9) 1 body) kinds 4 2 1 0 id no slots = none := by decide
example : ownedFirstId body kinds 4 0 0 0 id no slots = none := by decide
example : ownedFirstId body kinds 4 2 9 0 id no slots = none := by decide
example : unitContributions body kinds 4 id (classifiedParts body no 0 (slots.take 2)) = [3, 0] := by decide
example : unitContributions (adjustBeside (fun _ => 9) 1 body) kinds 4 id (classifiedParts (adjustBeside (fun _ => 9) 1 body) no 0 (slots.take 2)) = [10, 0] := by decide
private noncomputable def sourceRound : PayloadRound Unit Nat :=
  ⟨⟨kinds, 4, false, (fun _ => false), true, (fun _ => false), (fun _ _ => true), (fun _ state => state), (fun _ state => state), [⟨0, 3, ()⟩, ⟨2, 1, ()⟩]⟩,
    fun key _ => (body key).getD 0⟩
private noncomputable def cache : PayloadCache Nat := nextPayloadCache none sourceRound
private def place : Nat → Option Nat
  | 0 => some 100
  | 2 => some 200
  | _ => none
private def initializeJob (key value : Nat) : Nat := key + value
private def job : ReuseJob Nat := ⟨2, 1, 202⟩
example : ownedFirstId (adjustBeside (fun _ => 9) 3 (fromPairs cache.pairs)) cache.kindAt 4 job.owner 3 0 id no slots =
    ownedFirstId (fromPairs cache.pairs) cache.kindAt 4 job.owner 3 0 id no slots := by
  exact root_adr0352_i5_reached_owned_first_unchanged [sourceRound] cache rfl place (fun _ => true) initializeJob job
    (by exact List.mem_cons_of_mem _ (List.mem_cons_self _ _)) 3 0 id (fun _ => 9) no slots
