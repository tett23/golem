import OwnedGlobal
open BesideOwnedGlobal BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideClassifiedPrefix BesideOwnedRows
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
private def slots : List CountSlot := [.wrapped, .ordinary 0, .wrapped, .ordinary 0]
private def skip (_ : Nat) : Bool := false
private noncomputable def query (table : Nat → Option Nat) (target : Nat) : Option Nat :=
  fromPairs (allPairs table kinds 4 id (derivedStart table kinds 4 0 id skip slots) jobs) target
example : query body 1 = some 1 := by decide
example : query body 3 = some 4 := by decide
example : query (adjustBeside (fun _ => 9) 1 body) 1 = some 1 := by decide
example : query (adjustBeside (fun _ => 9) 1 body) 3 = some 11 := by decide
example : query (adjustBeside (fun _ => 0) 3 body) 3 = some 4 := by decide
example : query body 2 = none := by decide
example : query body 0 = none := by decide
example : query body 9 = none := by decide
private noncomputable def sourceRound : PayloadRound Unit Nat :=
  ⟨⟨kinds, 4, false, (fun _ => false), true, (fun _ => false), (fun _ _ => true), (fun _ state => state), (fun _ state => state), [⟨0, 3, ()⟩, ⟨2, 1, ()⟩]⟩,
    fun key _ => (body key).getD 0⟩
private noncomputable def cache : PayloadCache Nat := nextPayloadCache none sourceRound
private def place (key : Nat) : Option Nat := if key = 0 then some 100 else if key = 2 then some 200 else none
example (target : Nat) :
    fromPairs (allPairs (adjustBeside (fun _ => 9) target (fromPairs cache.pairs)) cache.kindAt cache.count id
      (derivedStart (adjustBeside (fun _ => 9) target (fromPairs cache.pairs)) cache.kindAt cache.count 0 id skip slots)
      (valueJobs (fun _ => true) (fun _ value => value) cache.count (figurePairs cache.kindAt place 0 cache.count))) target =
    fromPairs (allPairs (fromPairs cache.pairs) cache.kindAt cache.count id
      (derivedStart (fromPairs cache.pairs) cache.kindAt cache.count 0 id skip slots)
      (valueJobs (fun _ => true) (fun _ value => value) cache.count (figurePairs cache.kindAt place 0 cache.count))) target := by
  exact root_adr0352_i5_reached_global_first_unchanged [sourceRound] cache rfl place (fun _ => true) (fun _ value => value) target 0 id (fun _ => 9) skip slots
