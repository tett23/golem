import PegModelTest

namespace ListMarkTotal

open PegModel PegModelTest

private def alts : List (List Expr) :=
  [[.semanticPred true " ordered == 0 ", .ref "BulletMark" []],
   [.semanticPred true " ordered == 1 ", .ref "OrderedMark" []]]

private def literalResult (mark : String) (input : List Char) : Option (List Char) :=
  if mark.toList.isPrefixOf input then some (input.drop mark.toList.length) else none

private theorem marker (name mark written : String) (env : Params) (input : List Char) (fuel : Nat)
    (kind : (name = "BulletMark" ∧ mark = "-" ∧ written = "'-'") ∨
      (name = "OrderedMark" ∧ mark = "+" ∧ written = "'+'")) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref name []) input =
      .ok (literalResult mark input) := by
  rw [show fuel + 3 = fuel + 1 + 1 + 1 by omega]
  have resolve : recognizeEnv Generated.pegGrammar env (fuel + 1 + 1 + 1) (.ref name []) input =
      recognizeEnv Generated.pegGrammar [] (fuel + 1 + 1) (.choice [[.lit mark written]]) input := by
    rcases kind with ⟨rfl, rfl, rfl⟩ | ⟨rfl, rfl, rfl⟩ <;> rfl
  rw [resolve]
  change runChoices (fun xs => runSequence
    (fun sc item rest => recognizeEnv Generated.pegGrammar sc (fuel + 1) item rest)
    (fun _ _ _ => .ok none) [] xs input) [[.lit mark written]] = _
  simp only [runChoices, foldChoice, List.foldlM]
  rw [sequence_literal_total Generated.pegGrammar [] _ fuel mark written input]
  rfl

theorem generated_list_mark (env : Params) (arg : String) (n fuel : Nat) (input : List Char)
    (value : integer env arg = some n) :
    recognizeEnv Generated.pegGrammar env (fuel + 5) (.ref "ListMark" [arg]) input =
      .ok (if n = 0 then literalResult "-" input else if n = 1 then literalResult "+" input else none) := by
  have args : [arg].mapM (integer env) = some [n] := by simp [List.mapM, List.mapM.loop, value]
  rw [show fuel + 5 = fuel + 3 + 1 + 1 by omega]
  change (match [arg].mapM (integer env) with
    | none => Except.error "opaque argument for ListMark"
    | some vs => recognizeEnv Generated.pegGrammar (List.zip ["ordered"] vs) (fuel + 3 + 1)
        (.choice alts) input) = _
  rw [args]
  let bound := [("ordered", n)]
  change runChoices (fun xs => runSequence
    (fun sc item rest => recognizeEnv Generated.pegGrammar sc (fuel + 3) item rest)
    (fun _ _ _ => .ok none) bound xs input) alts = _
  have zero : recognizeEnv Generated.pegGrammar bound (fuel + 3) (.semanticPred true " ordered == 0 ") input =
      .ok (if n = 0 then some input else none) := by
    change Except.ok (if (n == 0) == true then some input else none) = _
    simp
  have one : recognizeEnv Generated.pegGrammar bound (fuel + 3) (.semanticPred true " ordered == 1 ") input =
      .ok (if n = 1 then some input else none) := by
    change Except.ok (if (n == 1) == true then some input else none) = _
    simp
  have bullet := marker "BulletMark" "-" "'-'" bound input fuel (Or.inl ⟨rfl,rfl,rfl⟩)
  have ordered := marker "OrderedMark" "+" "'+'" bound input fuel (Or.inr ⟨rfl,rfl,rfl⟩)
  by_cases z : n = 0
  · have o : n ≠ 1 := by omega
    cases b : literalResult "-" input <;>
      simp [alts, zero, one, bullet, ordered, z, o, b, runChoices, foldChoice, runSequence, List.foldlM,
        Bind.bind, Except.bind, pure, Except.pure, Except.map]
  · by_cases o : n = 1 <;> cases b : literalResult "+" input <;>
      simp [alts, zero, one, bullet, ordered, z, o, b, runChoices, foldChoice, runSequence, List.foldlM,
        Bind.bind, Except.bind, pure, Except.pure, Except.map]

end ListMarkTotal
