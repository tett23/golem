import PegModelTest

open PegModelTest
set_option maxHeartbeats 1000000

namespace ThrowingPrefixTotal

theorem false_then_literal_label (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (value written name : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 4)
      (.label (.choice [[.semanticPred true " False ", .lit value written]]) name) input =
      .error ("label: " ++ name) := by
  have miss : PegModel.recognizeEnv grammar env (fuel + 3)
      (.choice [[.semanticPred true " False ", .lit value written]]) input = .ok none := by
    rfl
  simpa using PegModel.label_of_miss grammar env (fuel + 3)
    (.choice [[.semanticPred true " False ", .lit value written]]) input name miss

theorem literal_lookahead_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (value written : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 2)
      (.andPred (.lit value written)) input =
      .ok (if value.toList.isPrefixOf input then some input else none) := by
  have literal := PegModelTest.literal_total grammar env fuel value written input
  change (match PegModel.recognizeEnv grammar env (fuel + 1) (.lit value written) input with
    | Except.error reason => if PegModel.isLabelFailure reason then Except.ok none else Except.error reason
    | Except.ok none => Except.ok none
    | Except.ok (some _) => Except.ok (some input)) = _
  rw [literal]
  cases h : value.toList.isPrefixOf input <;> simp [h]

theorem throwing_prefix_choice (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (value written name : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 6)
      (.choice [[.andPred (.lit value written),
        .label (.choice [[.semanticPred true " False ", .lit value written]]) name]]) input =
      (if value.toList.isPrefixOf input then .error ("label: " ++ name) else .ok none) := by
  have look := literal_lookahead_total grammar env (fuel + 3) value written input
  have lookFuel : fuel + 3 + 2 = fuel + 5 := by omega
  rw [lookFuel] at look
  have outerFuel : fuel + 6 = (fuel + 5) + 1 := by omega
  rw [outerFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 5) item rest)
      _ env items input)
    [[.andPred (.lit value written),
      .label (.choice [[.semanticPred true " False ", .lit value written]]) name]] = _
  cases hit : value.toList.isPrefixOf input with
  | false =>
      simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, look, hit]
      rfl
  | true =>
      have labelAt : PegModel.recognizeEnv grammar env (fuel + 5)
          (.label (.choice [[.semanticPred true " False ", .lit value written]]) name) input =
          .error ("label: " ++ name) := by
        simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
          false_then_literal_label grammar env (fuel + 1) value written name input
      simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
        look, hit, labelAt]
      rfl

theorem generated_too_deep (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 7)
      (.ref "TooDeep" []) input =
      (if ("#".toList).isPrefixOf input then .error "label: heading_level" else .ok none) := by
  have refFuel : fuel + 7 = (fuel + 6) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 6)
    (.choice [[.andPred (.lit "#" "'#'"),
      .label (.choice [[.semanticPred true " False ", .lit "#" "'#'"]]) "heading_level"]]) input = _
  simpa using throwing_prefix_choice Generated.pegGrammar [] fuel "#" "'#'" "heading_level" input

theorem generated_reserved_bracket (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 7)
      (.ref "ReservedBracket" []) input =
      (if ("[!".toList).isPrefixOf input then .error "label: reserved" else .ok none) := by
  have refFuel : fuel + 7 = (fuel + 6) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 6)
    (.choice [[.andPred (.lit "[!" "'[!'"),
      .label (.choice [[.semanticPred true " False ", .lit "[!" "'[!'"]]) "reserved"]]) input = _
  simpa using throwing_prefix_choice Generated.pegGrammar [] fuel "[!" "'[!'" "reserved" input

example : PegModel.recognizeEnv Generated.pegGrammar [] 7
    (.ref "TooDeep" []) "# title".toList = .error "label: heading_level" := by
  simpa using generated_too_deep "# title".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 7
    (.ref "TooDeep" []) "title".toList = .ok none := by
  simpa using generated_too_deep "title".toList 0

theorem literal_then_false_label (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (value written name : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 5)
      (.choice [[.lit value written,
        .label (.choice [[.semanticPred true " False "]]) name]]) input =
      (if value.toList.isPrefixOf input then .error ("label: " ++ name) else .ok none) := by
  have literal := PegModelTest.literal_total grammar env (fuel + 3) value written input
  have literalFuel : fuel + 3 + 1 = fuel + 4 := by omega
  rw [literalFuel] at literal
  have outerFuel : fuel + 5 = (fuel + 4) + 1 := by omega
  rw [outerFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 4) item rest)
      _ env items input)
    [[.lit value written,
      .label (.choice [[.semanticPred true " False "]]) name]] = _
  cases hit : value.toList.isPrefixOf input with
  | false =>
      simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, literal, hit]
      rfl
  | true =>
      have thrown : PegModel.recognizeEnv grammar env (fuel + 4)
          (.label (.choice [[.semanticPred true " False "]]) name)
          (input.drop value.toList.length) = .error ("label: " ++ name) := by
        rfl
      simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
        literal, hit, thrown]
      rfl

theorem generated_bad_break (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 6)
      (.ref "BadBreak" []) input =
      (if ("\\".toList).isPrefixOf input then .error "label: hard_break" else .ok none) := by
  have refFuel : fuel + 6 = (fuel + 5) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 5)
    (.choice [[.lit "\\" "'\\\\'",
      .label (.choice [[.semanticPred true " False "]]) "hard_break"]]) input = _
  simpa using literal_then_false_label Generated.pegGrammar [] fuel "\\" "'\\\\'" "hard_break" input

example : PegModel.recognizeEnv Generated.pegGrammar [] 6
    (.ref "BadBreak" []) "\\x".toList = .error "label: hard_break" := by
  simpa using generated_bad_break "\\x".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 6
    (.ref "BadBreak" []) "x".toList = .ok none := by
  simpa using generated_bad_break "x".toList 0

theorem generated_lbr_total (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 4)
      (.ref "LBr" []) input =
      .ok (if ("[".toList).isPrefixOf input then some (input.drop 1) else none) := by
  calc
    _ = PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
      (.choice [[.lit "[" "'['"]]) input := by rfl
    _ = PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 2)
      (.lit "[" "'['") input :=
        PegModelTest.single_literal_choice Generated.pegGrammar [] (fuel + 1) "[" "'['" input
    _ = _ := by
      simpa using PegModelTest.literal_total Generated.pegGrammar [] (fuel + 1) "[" "'['" input

theorem false_then_child_label (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (child : PegModel.Expr) (name : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 4)
      (.label (.choice [[.semanticPred true " False ", child]]) name) input =
      .error ("label: " ++ name) := by
  have miss : PegModel.recognizeEnv grammar env (fuel + 3)
      (.choice [[.semanticPred true " False ", child]]) input = .ok none := by rfl
  simpa using PegModel.label_of_miss grammar env (fuel + 3)
    (.choice [[.semanticPred true " False ", child]]) input name miss

theorem generated_bad_bracket (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 7)
      (.ref "BadBracket" []) input =
      (if ("[".toList).isPrefixOf input then .error "label: bracket" else .ok none) := by
  have refFuel : fuel + 7 = (fuel + 6) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 6)
    (.choice [[.andPred (.ref "LBr" []),
      .label (.choice [[.semanticPred true " False ", .ref "LBr" []]]) "bracket"]]) input = _
  have choiceFuel : fuel + 6 = (fuel + 5) + 1 := by omega
  rw [choiceFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 5) item rest)
      _ [] items input)
    [[.andPred (.ref "LBr" []),
      .label (.choice [[.semanticPred true " False ", .ref "LBr" []]]) "bracket"]] = _
  have child := generated_lbr_total input (fuel + 1)
  have childFuel : fuel + 1 + 4 = fuel + 5 := by omega
  rw [childFuel] at child
  have look : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 5)
      (.andPred (.ref "LBr" [])) input =
      .ok (if ("[".toList).isPrefixOf input then some input else none) := by
    have innerFuel : fuel + 5 = (fuel + 4) + 1 := by omega
    rw [innerFuel]
    change (match PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 4)
      (.ref "LBr" []) input with
      | Except.error reason => if PegModel.isLabelFailure reason then Except.ok none else Except.error reason
      | Except.ok none => Except.ok none
      | Except.ok (some _) => Except.ok (some input)) = _
    have childAt := generated_lbr_total input fuel
    rw [childAt]
    cases h : ("[".toList).isPrefixOf input <;> simp [h]
  cases hit : ("[".toList).isPrefixOf input with
  | false =>
      simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, look, hit]
      rfl
  | true =>
      have labelAt : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 5)
          (.label (.choice [[.semanticPred true " False ", .ref "LBr" []]]) "bracket") input =
          .error "label: bracket" := by
        simpa using false_then_child_label Generated.pegGrammar [] (fuel + 1)
          (.ref "LBr" []) "bracket" input
      simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
        look, hit, labelAt]
      rfl

example : PegModel.recognizeEnv Generated.pegGrammar [] 7
    (.ref "BadBracket" []) "[x".toList = .error "label: bracket" := by
  simpa using generated_bad_bracket "[x".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 7
    (.ref "BadBracket" []) "x".toList = .ok none := by
  simpa using generated_bad_bracket "x".toList 0

private def rangeOpening : List PegModel.Expr :=
  ((Generated.pegGrammar.rules.find? (fun r => r.name == "RangeExpr")).bind
    (fun rule => rule.alts.head?)).map (·.items) |>.getD []

theorem generated_range_opening (env : PegModel.Params) (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar env (fuel + 6) (.choice [rangeOpening]) input =
      (if "...".toList.isPrefixOf input then .error "label: range_end" else .ok none) := by
  exact throwing_prefix_choice Generated.pegGrammar env fuel "..." "'...'" "range_end" input

end ThrowingPrefixTotal
