import ClassifiedPrefix
open BesideOwnership BesideProducer BesideReuse BesideStore BesideClassifiedPrefix

private def body : Nat → Option Nat
  | 3 => some 1
  | 7 => some 3
  | 8 => some 2
  | _ => none
private def skip (key : Nat) : Bool := decide (key = 4)
private def kinds : Nat → Option Kind
  | 0 => some .paragraph
  | 2 => some .figure
  | 3 => some .paragraph
  | 4 => some .control
  | 6 => some .figure
  | 7 => some .paragraph
  | 8 => some .paragraph
  | _ => some .other
private def slots : List CountSlot := [.ordinary 2, .table 3, .wrapped, .ordinary 0, .ordinary 0, .ordinary 2, .wrapped, .ordinary 0, .ordinary 0]
example : classifiedParts body skip 0 (slots.take 6) = [(2, none), (3, none), (1, some 2), (0, none), (0, none), (2, none)] := by decide

private def changed : Nat → Option Nat := adjustBeside (fun _ => 9) 7 body
example : classifiedParts changed skip 0 (slots.take 6) = classifiedParts body skip 0 (slots.take 6) := by decide
example : unitContributions body kinds 9 id (classifiedParts body skip 0 (slots.take 6)) = [2, 3, 2, 0, 0, 2] := by decide
example : unitContributions changed kinds 9 id (classifiedParts changed skip 0 (slots.take 6)) = [2, 3, 2, 0, 0, 2] := by decide
example : classifiedParts body skip 0 (slots.take 0) = [] := by decide
example : classifiedParts body skip 0 [] = [] := by decide
private def tableBody (_ : Nat) : Option Nat := some 999
private def allSkip (_ : Nat) : Bool := true
example : classifiedParts tableBody allSkip 0 [.table 3] = [(3, none)] := by decide
example : classifiedParts tableBody allSkip 0 [.ordinary 3] = [(0, none)] := by decide
example : classifiedParts tableBody allSkip 0 [.wrapped] = [(0, none)] := by decide
example : classifiedParts body skip 10 [.ordinary 2, .wrapped] = [(2, none), (1, some 11)] := by decide
example : unitContributions (adjustBeside (fun _ => 0) 7 body) kinds 9 id (classifiedParts body skip 0 (slots.take 6)) = [2, 3, 2, 0, 0, 2] := by decide
