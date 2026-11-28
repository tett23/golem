import ListCompositionTotal
import PlusComposition

namespace DefinitionCompositionTotal
open PegModel

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

def listStep : Expr :=
  .choice [[.opt (.ref "BlankLines" []),
    .andPred (.choice [[.ref "Ind" ["ind"], .lit "=" "'='",
      .charClass [(32, 32), (9, 9)] "[ \\t]"]]), .ref "DefGroup" ["ind"]]]

def groupStep : Expr :=
  .choice [[.opt (.ref "BlankLines" []), .ref "DefNew" ["ind"], .ref "DefBody" ["ind"]]]

def bodyGuard : Expr :=
  .andPred (.choice [[.ref "Ind" ["col ind + 2"],
    .notPred (.charClass [(32, 32), (9, 9)] "[ \\t]"),
    .notPred (.ref "BlankLine" []), .any]])

def bodyStep : Expr :=
  .choice [[.opt (.ref "BlankLines" []), bodyGuard, .ref "Block" ["col ind + 2"]]]

/-- The actual definition-list wrapper preserves every child result for
    arbitrary input, indentation and fuel, without a child-success premise. -/
theorem generated_list (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3)
      (.ref "DefList" ["ind"]) input =
      next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
        (.ref "DefGroup" ["ind"]) input) (fun rest =>
        RuleRepetition.scan
          (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n listStep)
          (fuel + 1) rest) := by
  change recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2)
    (.choice [[.ref "DefGroup" ["ind"], .star listStep]]) input = _
  exact ListCompositionTotal.first_then_repeated _ _ _ _ _ _ _

/-- The actual group requires one or more terms before the first body,
    then scans subsequent bodies; recursive child semantics stay explicit. -/
theorem generated_group (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3)
      (.ref "DefGroup" ["ind"]) input =
      next (PlusComposition.scanPlus
        (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n (.ref "DefTerm" ["ind"]))
        fuel input) (fun rest0 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
          (.ref "DefBody" ["ind"]) rest0) (fun rest1 =>
          RuleRepetition.scan
            (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n groupStep)
            (fuel + 1) rest1)) := by
  change recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2)
    (.choice [[.plus (.ref "DefTerm" ["ind"]), .ref "DefBody" ["ind"], .star groupStep]]) input = _
  change runChoices (fun xs => runSequence
    (fun scope item rest => recognizeEnv Generated.pegGrammar scope (fuel + 1) item rest)
    _ [("ind", ind)] xs input)
    [[.plus (.ref "DefTerm" ["ind"]), .ref "DefBody" ["ind"], .star groupStep]] = _
  have first := PlusComposition.plus Generated.pegGrammar [("ind", ind)] (.ref "DefTerm" ["ind"]) fuel
  have repeated := RuleRepetition.star Generated.pegGrammar [("ind", ind)] groupStep (fuel + 1)
  cases read0 : PlusComposition.scanPlus (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n (.ref "DefTerm" ["ind"])) fuel input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, first, repeated, read0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, first, repeated, read0]; rfl
    | some rest0 =>
      cases read1 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "DefBody" ["ind"]) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, first, repeated, read0, read1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, first, repeated, read0, read1]; rfl
        | some rest1 =>
          cases read2 : RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n groupStep) (fuel + 1) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, first, repeated, read0, read1, read2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, first, repeated, read0, read1, read2]; rfl
            | some rest2 =>
              simp [runChoices, foldChoice, runSequence, next, first, repeated, read0, read1, read2]; rfl

/-- The first and each repeated body use the canonical indentation guard.
    Misses, labelled errors, exhaustion and zero-width failures are preserved. -/
theorem generated_body (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3)
      (.ref "DefBody" ["ind"]) input =
      next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) bodyGuard input) (fun rest0 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
          (.ref "Block" ["col ind + 2"]) rest0) (fun rest1 =>
          RuleRepetition.scan
            (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n bodyStep)
            (fuel + 1) rest1)) := by
  change recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2)
    (.choice [[bodyGuard, .ref "Block" ["col ind + 2"], .star bodyStep]]) input = _
  change runChoices (fun xs => runSequence
    (fun scope item rest => recognizeEnv Generated.pegGrammar scope (fuel + 1) item rest)
    _ [("ind", ind)] xs input)
    [[bodyGuard, .ref "Block" ["col ind + 2"], .star bodyStep]] = _
  have repeated := RuleRepetition.star Generated.pegGrammar [("ind", ind)] bodyStep (fuel + 1)
  unfold bodyGuard
  cases read0 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
      (.andPred (.choice [[.ref "Ind" ["col ind + 2"],
        .notPred (.charClass [(32, 32), (9, 9)] "[ \\t]"),
        .notPred (.ref "BlankLine" []), .any]])) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, bodyGuard, repeated, read0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, bodyGuard, repeated, read0]; rfl
    | some rest0 =>
      cases read1 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Block" ["col ind + 2"]) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, bodyGuard, repeated, read0, read1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, bodyGuard, repeated, read0, read1]; rfl
        | some rest1 =>
          cases read2 : RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n bodyStep) (fuel + 1) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, bodyGuard, repeated, read0, read1, read2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, bodyGuard, repeated, read0, read1, read2]; rfl
            | some rest2 =>
              simp [runChoices, foldChoice, runSequence, next, bodyGuard, repeated, read0, read1, read2]; rfl

#print axioms generated_list
#print axioms generated_group
#print axioms generated_body

end DefinitionCompositionTotal
