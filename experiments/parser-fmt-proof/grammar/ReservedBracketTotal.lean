import ArgumentsRoundTrip
open PegModelTest
set_option maxHeartbeats 1000000

namespace ReservedBracketTotal

theorem reserved_prefix_miss (input : List Char) (fuel : Nat)
    (miss : ("[!".toList).isPrefixOf input = false) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 4)
      (.andPred (.lit "[!" "'[!'")) input = .ok none := by
  have outerFuel : fuel + 4 = (fuel + 3) + 1 := by omega
  rw [outerFuel]
  change (match PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
      (.lit "[!" "'[!'") input with
    | Except.error reason => if PegModel.isLabelFailure reason then Except.ok none else Except.error reason
    | Except.ok none => Except.ok none
    | Except.ok (some _) => Except.ok (some input)) = _
  have literal := literal_total Generated.pegGrammar [] (fuel + 2) "[!" "'[!'" input
  have fuelEq : fuel + 2 + 1 = fuel + 3 := by omega
  rw [fuelEq] at literal
  rw [literal, miss]
  rfl

theorem generated_reserved_nonprefix (input : List Char) (fuel : Nat)
    (miss : ("[!".toList).isPrefixOf input = false) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 6)
      (.ref "ReservedBracket" []) input = .ok none := by
  have refFuel : fuel + 6 = (fuel + 5) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 5)
    (.choice [[.andPred (.lit "[!" "'[!'"),
      .label (.choice [[.semanticPred true " False ", .lit "[!" "'[!'"]]) "reserved"]]) input = _
  have choiceFuel : fuel + 5 = (fuel + 4) + 1 := by omega
  rw [choiceFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 4) item rest)
      _ [] items input)
    [[.andPred (.lit "[!" "'[!'"),
      .label (.choice [[.semanticPred true " False ", .lit "[!" "'[!'"]]) "reserved"]] = _
  have first := reserved_prefix_miss input fuel miss
  simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, first]
  rfl

theorem generated_reserved_prefix (extra : Nat) (suffix : List Char) :
    PegModel.recognizeEnv Generated.pegGrammar [] (extra + 20)
      (.ref "ReservedBracket" []) ('[' :: '!' :: suffix) = .error "label: reserved" := by
  simpa [PegModel.recognize] using ArgumentsRoundTrip.strict_reserved_prefix extra suffix

theorem generated_reserved_total (extra : Nat) (input : List Char) :
    PegModel.recognizeEnv Generated.pegGrammar [] (extra + 20)
      (.ref "ReservedBracket" []) input =
      (if ("[!".toList).isPrefixOf input then .error "label: reserved" else .ok none) := by
  have onMiss (xs : List Char) (hmiss : ("[!".toList).isPrefixOf xs = false) :
      PegModel.recognizeEnv Generated.pegGrammar [] (extra + 20)
        (.ref "ReservedBracket" []) xs = .ok none := by
    have h := generated_reserved_nonprefix xs (extra + 14) hmiss
    have fuelEq : extra + 14 + 6 = extra + 20 := by omega
    rw [fuelEq] at h
    exact h
  cases input with
  | nil =>
      have miss : ("[!".toList).isPrefixOf [] = false := by decide
      simpa [miss] using onMiss [] miss
  | cons c rest =>
      cases rest with
      | nil =>
          have miss : ("[!".toList).isPrefixOf [c] = false := by
            change (('[' == c) && false) = false
            cases ('[' == c) <;> rfl
          simpa [miss] using onMiss [c] miss
      | cons d tail =>
          by_cases hc : c = '['
          · subst c
            by_cases hd : d = '!'
            · subst d
              have hp : ("[!".toList).isPrefixOf ('[' :: '!' :: tail) = true := by simp [List.isPrefixOf]
              simpa [hp] using generated_reserved_prefix extra tail
            · have be : ('!' == d) = false := by
                cases h : ('!' == d) with
                | false => rfl
                | true => exact False.elim (hd ((beq_iff_eq _ _).mp h).symm)
              have miss : ("[!".toList).isPrefixOf ('[' :: d :: tail) = false := by
                simp [List.isPrefixOf, be]
              simpa [miss] using onMiss ('[' :: d :: tail) miss
          · have be : ('[' == c) = false := by
              cases h : ('[' == c) with
              | false => rfl
              | true => exact False.elim (hc ((beq_iff_eq _ _).mp h).symm)
            have miss : ("[!".toList).isPrefixOf (c :: d :: tail) = false := by
              simp [List.isPrefixOf, be]
            simpa [miss] using onMiss (c :: d :: tail) miss

example : PegModel.recognizeEnv Generated.pegGrammar [] 20
    (.ref "ReservedBracket" []) "[!x".toList = .error "label: reserved" := by
  simpa using generated_reserved_total 0 "[!x".toList

example : PegModel.recognizeEnv Generated.pegGrammar [] 20
    (.ref "ReservedBracket" []) "[x".toList = .ok none := by
  simpa using generated_reserved_total 0 "[x".toList

example : PegModel.recognizeEnv Generated.pegGrammar [] 20
    (.ref "ReservedBracket" []) [] = .ok none := by
  simpa using generated_reserved_total 0 []

end ReservedBracketTotal
