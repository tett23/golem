/- Root ADR 0483: the old root ADR 0352 h6 counterexample, retained as a
   caller-consumption regression. The public trial still forces three
   rows even when its positive prefix limit is one or two. -/
import CausalBoundary
open PhysicalPagination

namespace ForcedPrefix

noncomputable def rows (_cursor : St) (before start : Nat) : List (Line × Nat) :=
  (List.range (5 - start)).map fun offset =>
    (⟨before + offset, [], 0⟩, start + offset + 1)

noncomputable def publicCount (limit : Option Nat) : Option Nat :=
  let e := CausalBoundary.env 4
  match trialWrap e none limit ⟨2, 4, false⟩ true (initial e) ((rows (initial e) 0 0).map (·.1)) with
  | .ok (.placed count _ _) => some count
  | _ => none

noncomputable def placedText (limit : Option Nat) : Option (List Nat) :=
  let e := CausalBoundary.env 4
  match parts e none rows 5 0 (fun _ => true) id limit ⟨2, 4, false⟩ true 0 0 (initial e) with
  | .ok s => some (text s)
  | _ => none

set_option maxRecDepth 10000 in
set_option maxHeartbeats 1000000 in
theorem public_contract : [publicCount none, publicCount (some 2), publicCount (some 1)] =
    [some 3, some 3, some 3] := by decide

set_option maxRecDepth 10000 in
set_option maxHeartbeats 1000000 in
theorem caller_consumes : [placedText none, placedText (some 2), placedText (some 1)] =
    [some [0, 1, 2, 3, 4], some [0, 1, 2, 3, 4], some [0, 1, 2, 3, 4]] := by decide

#print axioms ForcedPrefix.public_contract
#print axioms ForcedPrefix.caller_consumes
end ForcedPrefix
