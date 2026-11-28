import BodyEdits
open BesideBodyEdits BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds
private def kinds : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | 2 => some .control
  | 3 => some .paragraph
  | 4 => some .figure
  | 5 => some .paragraph
  | _ => none
private def body : Nat → Option Nat
  | 1 => some 2
  | 3 => some 4
  | 5 => some 1
  | _ => none
private def edits : List (BodyEdit Nat) := [⟨1, fun _ => 0⟩, ⟨3, fun n => n + 1⟩, ⟨1, fun _ => 9⟩, ⟨5, fun n => n * 2⟩, ⟨999, fun _ => 7⟩, ⟨2, fun _ => 5⟩]
example : applyEdits body edits 1 = some 9 := by decide
example : applyEdits body edits 3 = some 5 := by decide
example : applyEdits body edits 5 = some 2 := by decide
example : applyEdits body edits 999 = none := by decide
example : applyEdits body edits 2 = none := by decide
example : applyEdits body ([] : List (BodyEdit Nat)) = body := rfl
example : candidateKeys body kinds 0 6 = [1, 3] := by decide
example : candidateKeys (applyEdits body edits) kinds 0 6 = [1, 3] := by decide
example : candidateKeys (applyEdits body edits) kinds 4 6 = [5] := by decide
example : applyEdits body [⟨1, fun _ => 3⟩, ⟨1, fun n => n + 1⟩] 1 = some 4 := by decide
example : applyEdits body [⟨1, fun n => n + 1⟩, ⟨1, fun _ => 3⟩] 1 = some 3 := by decide
example : classes (applyEdits body edits) (controlAt kinds) 0 6 = classes body (controlAt kinds) 0 6 :=
  root_adr0352_i5_body_edits_classes edits body (controlAt kinds) 0 6
private noncomputable def sourceRound : PayloadRound Unit Nat :=
  ⟨⟨kinds, 6, false, (fun _ => false), true, (fun _ => false), (fun _ _ => true), (fun _ state => state), (fun _ state => state), [⟨0, 5, ()⟩, ⟨4, 1, ()⟩]⟩,
    fun key _ => (body key).getD 0⟩
private noncomputable def cache : PayloadCache Nat := nextPayloadCache none sourceRound
example (key : Nat) (present : (applyEdits (fromPairs cache.pairs) edits key).isSome = true) : cache.kindAt key = some .paragraph :=
  root_adr0352_i5_reached_body_edits_typed [sourceRound] cache rfl edits key present
