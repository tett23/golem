import OwnedFirstScan
open BesideOwnedScan BesideStore BesideOwnership
example : numberPairs [2, 4, 7] (fun key => if key = 4 then 3 else 0) 9 = [(2, 9), (4, 9), (7, 12)] := by decide
example : fromPairs (numberPairs [2, 4, 7] (fun key => if key = 4 then 3 else 0) 9) 4 = some 9 := by decide
example : fromPairs (numberPairs [1, 1] (fun _ => 2) 0) 1 = some 2 := by decide
example : (countsFor (BesideOwnedFirst.beforeTarget 1 [1, 1]) (fun _ => 2)).foldl Nat.add 0 = 0 := by decide
example : fromPairs (numberPairs [] (fun _ => 2) 0) 1 = none := by decide
example : fromPairs (numberPairs [1] (fun _ => 0) 0) 1 = some 0 := by decide
example : fromPairs (numberPairs [1, 2] (fun _ => 0) 0) 3 = none := by decide

private def current : Nat → Option BesideProducer.Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | 2 => some .control
  | 3 => some .paragraph
  | _ => none
private def body : Nat → Option Nat
  | 1 => some 0
  | 3 => some 4
  | _ => none
private def skip (_ : Nat) : Bool := false
private def slots : List BesideClassifiedPrefix.CountSlot := [.wrapped, .ordinary 0, .ordinary 0, .ordinary 0]
example : storedOwnedFirst body current 4 0 1 0 id skip slots = some 1 := by decide
example : storedOwnedFirst body current 4 0 3 0 id skip slots = some 1 := by decide
example : storedOwnedFirst body current 4 0 2 0 id skip slots = none := by decide
example : storedOwnedFirst body current 4 0 0 0 id skip slots = none := by decide
example : storedOwnedFirst body current 4 0 9 0 id skip slots = none := by decide
example : storedOwnedFirst body current 4 0 3 7 id skip slots = BesideOwnedFirst.ownedFirstId body current 4 0 3 7 id skip slots :=
  root_adr0352_i5_owned_first_scan body current 4 0 3 7 id skip slots
