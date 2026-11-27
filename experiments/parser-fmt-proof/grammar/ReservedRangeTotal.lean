import ThrowingPrefixTotal

open PegModelTest ThrowingPrefixTotal
set_option maxHeartbeats 1000000

namespace ReservedRangeTotal

theorem guarded_throwing_prefix (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (excluded excludedWritten value written name : String)
    (tail : List PegModel.Expr) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 6)
      (.choice [[.notPred (.lit excluded excludedWritten), .andPred (.lit value written),
        .label (.choice [[.semanticPred true " False ", .lit value written]]) name] ++ tail]) input =
      (if excluded.toList.isPrefixOf input then .ok none else
        if value.toList.isPrefixOf input then .error ("label: " ++ name) else .ok none) := by
  have neg := not_literal_total grammar env (fuel + 3) excluded excludedWritten input
  have look := literal_lookahead_total grammar env (fuel + 3) value written input
  have labelAt := false_then_literal_label grammar env (fuel + 1) value written name input
  have outerFuel : fuel + 6 = (fuel + 5) + 1 := by omega
  rw [outerFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 5) item rest)
      _ env items input)
    [[.notPred (.lit excluded excludedWritten), .andPred (.lit value written),
      .label (.choice [[.semanticPred true " False ", .lit value written]]) name] ++ tail] = _
  cases hn : excluded.toList.isPrefixOf input <;>
    cases hv : value.toList.isPrefixOf input <;>
    simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
      List.foldlM, neg, look, labelAt, hn, hv]

  all_goals
    induction tail with
    | nil => rfl
    | cons item rest ih => simpa [List.foldlM] using ih

-- Keep the suffix from the actual exported grammar, including recursion.
private def generatedTail : List PegModel.Expr :=
  ((((Generated.pegGrammar.rules.find? (fun rule => rule.name == "ReservedRange")).bind
    (fun rule => rule.alts.head?)).map (fun alt => alt.items)).getD []).drop 3

theorem generated_reserved_range (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 7)
      (.ref "ReservedRange" []) input =
      (if ("...".toList).isPrefixOf input then .ok none else
        if ("..".toList).isPrefixOf input then .error "label: reserved" else .ok none) := by
  have refFuel : fuel + 7 = (fuel + 6) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 6)
    (.choice [[.notPred (.lit "..." "'...'"), .andPred (.lit ".." "'..'"),
      .label (.choice [[.semanticPred true " False ", .lit ".." "'..'"]]) "reserved"] ++
      generatedTail]) input = _
  exact guarded_throwing_prefix Generated.pegGrammar [] fuel "..." "'...'"
    ".." "'..'" "reserved" generatedTail input

example : PegModel.recognizeEnv Generated.pegGrammar [] 7
    (.ref "ReservedRange" []) "".toList = .ok none := by
  simpa using generated_reserved_range "".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 7
    (.ref "ReservedRange" []) ".".toList = .ok none := by
  simpa using generated_reserved_range ".".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 7
    (.ref "ReservedRange" []) "..".toList = .error "label: reserved" := by
  simpa using generated_reserved_range "..".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 7
    (.ref "ReservedRange" []) "...2".toList = .ok none := by
  simpa using generated_reserved_range "...2".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 7
    (.ref "ReservedRange" []) "..1...2".toList = .error "label: reserved" := by
  simpa using generated_reserved_range "..1...2".toList 0

#print axioms guarded_throwing_prefix
#print axioms generated_reserved_range

end ReservedRangeTotal
