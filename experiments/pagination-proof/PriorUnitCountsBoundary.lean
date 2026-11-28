import PriorUnitCounts

open BesideOwnership BesideProducer BesideReuse CausalFirstIds

private def kinds : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | 2 => some .figure
  | 3 => some .paragraph
  | 4 => some .figure
  | 5 => some .paragraph
  | 6 => some .paragraph
  | _ => none
private def body : Nat → Option Nat
  | 1 => some 2
  | 3 => some 3
  | 5 => some 4
  | 6 => some 3
  | _ => none
private def priorParts : List (Nat × Option Nat) := [(7, none), (1, some 0), (0, none), (1, some 2), (0, none)]
private def replace (n _ : Nat) : Nat := n
private def contribution (values : Nat → Option Nat) : List Nat := unitContributions values kinds 7 id priorParts
private def first (values : Nat → Option Nat) (target : Nat) (before after : List Nat) : Option Nat :=
  besideFromTwoPass (contribution values) [999] (countsFor before (rowCount id values))
    (countsFor after (rowCount id values)) (rowCount id values target) 10

example : contribution body = [7, 3, 0, 4, 0] := by decide
example : contribution (adjustBeside (replace 0) 5 body) = contribution body := by decide
example : contribution (adjustBeside (replace 1) 5 body) = contribution body := by decide
example : contribution (adjustBeside (replace 9) 5 body) = contribution body := by decide
example : contribution (adjustBeside (replace 0) 6 body) = contribution body := by decide
example : first body 5 [] [6] = some 25 := by decide
example : first (adjustBeside (replace 0) 5 body) 5 [] [6] = some 25 := by decide
example : first (adjustBeside (replace 7) 6 body) 6 [5] [] = some 29 := by decide
-- A different prior paragraph must change this first ID.
example : first (adjustBeside (replace 0) 1 body) 5 [] [6] = some 23 := by decide
example : unitContributions body kinds 7 id [] = [] := by rfl
