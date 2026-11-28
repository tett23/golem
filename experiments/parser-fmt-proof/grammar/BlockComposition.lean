import PlusComposition
import UnboundSequenceTotal

namespace BlockComposition
open PegModel PegModelTest

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

private theorem follow_next (read : Expr → List Char → ParseResult) (item : Expr)
    (items : List Expr) (input : List Char) :
    UnboundSequenceTotal.follow read (item::items) input =
      next (read item input) (fun rest => UnboundSequenceTotal.follow read items rest) := by
  cases result : read item input with
  | error reason => simp [UnboundSequenceTotal.follow,next,result]
  | ok value => cases value <;> simp [UnboundSequenceTotal.follow,next,result]

private theorem follow_end (read : Expr → List Char → ParseResult) (input : List Char) :
    UnboundSequenceTotal.follow read [] input = .ok (some input) := by rfl

private theorem next_end (result : ParseResult) :
    next result (fun rest => .ok (some rest)) = result := by
  cases result with
  | error reason => rfl
  | ok value => cases value <;> rfl

/-- Exact canonical recognition composition for arbitrary suffix, indentation
    and fuel. Repetition preserves progress/errors; AST/actions and recovery
    diagnostics are separate obligations. -/
theorem I1_I2_generated_paragraph (ind fuel : Nat) (input : List Char) :
  recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3) (.ref "Paragraph" ["ind"]) input =
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ind" ["ind"]) input) (fun rest0 =>
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.notPred (.charClass [(32,32),(9,9)] "[ \\t]")) rest0) (fun rest1 =>
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.notPred (.ref "BlockStart" [])) rest1) (fun rest2 =>
    next (PlusComposition.scanPlus (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n ((.ref "Inline" ["ind"]))) fuel rest2) (fun rest3 =>
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.choice [[.ref "Nl" []], [.notPred .any]]) rest3)))) := by
  change recognizeEnv _ [("ind", ind)] (fuel + 2) (.choice [[.ref "Ind" ["ind"], .notPred (.charClass [(32,32),(9,9)] "[ \\t]"), .notPred (.ref "BlockStart" []), .plus (.ref "Inline" ["ind"]), .choice [[.ref "Nl" []], [.notPred .any]]]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc (fuel + 1) item rest) _ [("ind", ind)] xs input) [[.ref "Ind" ["ind"], .notPred (.charClass [(32,32),(9,9)] "[ \\t]"), .notPred (.ref "BlockStart" []), .plus (.ref "Inline" ["ind"]), .choice [[.ref "Nl" []], [.notPred .any]]]] = _
  have rep3 := PlusComposition.plus Generated.pegGrammar [("ind", ind)] ((.ref "Inline" ["ind"])) fuel
  cases read0 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ind" ["ind"]) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, rep3, read0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, rep3, read0]; rfl
    | some rest0 =>
      cases read1 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.notPred (.charClass [(32,32),(9,9)] "[ \\t]")) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1]; rfl
        | some rest1 =>
          cases read2 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.notPred (.ref "BlockStart" [])) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2]; rfl
            | some rest2 =>
              cases read3 : PlusComposition.scanPlus (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n ((.ref "Inline" ["ind"]))) fuel rest2 with
              | error reason => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2, read3]; rfl
              | ok value => cases value with
                | none => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2, read3]; rfl
                | some rest3 =>
                  cases read4 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.choice [[.ref "Nl" []], [.notPred .any]]) rest3 with
                  | error reason => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2, read3, read4]; rfl
                  | ok value => cases value with
                    | none => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2, read3, read4]; rfl
                    | some rest4 => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2, read3, read4]; rfl

/-- Exact canonical recognition composition for arbitrary suffix, indentation
    and fuel. Repetition preserves progress/errors; AST/actions and recovery
    diagnostics are separate obligations. -/
theorem I1_I2_generated_term (ind fuel : Nat) (input : List Char) :
  recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3) (.ref "DefTerm" ["ind"]) input =
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ind" ["ind"]) input) (fun rest0 =>
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "TermMark" []) rest0) (fun rest1 =>
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ws" []) rest1) (fun rest2 =>
    next (PlusComposition.scanPlus (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n ((.ref "HeadInline" ["col ind + 2"]))) fuel rest2) (fun rest3 =>
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.choice [[.ref "Nl" []], [.notPred .any]]) rest3)))) := by
  change recognizeEnv _ [("ind", ind)] (fuel + 2) (.choice [[.ref "Ind" ["ind"], .ref "TermMark" [], .ref "Ws" [], .plus (.ref "HeadInline" ["col ind + 2"]), .choice [[.ref "Nl" []], [.notPred .any]]]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc (fuel + 1) item rest) _ [("ind", ind)] xs input) [[.ref "Ind" ["ind"], .ref "TermMark" [], .ref "Ws" [], .plus (.ref "HeadInline" ["col ind + 2"]), .choice [[.ref "Nl" []], [.notPred .any]]]] = _
  have rep3 := PlusComposition.plus Generated.pegGrammar [("ind", ind)] ((.ref "HeadInline" ["col ind + 2"])) fuel
  cases read0 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ind" ["ind"]) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, rep3, read0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, rep3, read0]; rfl
    | some rest0 =>
      cases read1 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "TermMark" []) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1]; rfl
        | some rest1 =>
          cases read2 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ws" []) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2]; rfl
            | some rest2 =>
              cases read3 : PlusComposition.scanPlus (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n ((.ref "HeadInline" ["col ind + 2"]))) fuel rest2 with
              | error reason => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2, read3]; rfl
              | ok value => cases value with
                | none => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2, read3]; rfl
                | some rest3 =>
                  cases read4 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.choice [[.ref "Nl" []], [.notPred .any]]) rest3 with
                  | error reason => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2, read3, read4]; rfl
                  | ok value => cases value with
                    | none => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2, read3, read4]; rfl
                    | some rest4 => simp [runChoices, foldChoice, runSequence, next, rep3, read0, read1, read2, read3, read4]; rfl

/-- Exact canonical recognition composition for arbitrary suffix, indentation
    and fuel. Repetition preserves progress/errors; AST/actions and recovery
    diagnostics are separate obligations. -/
theorem I1_I2_generated_code (ind fuel : Nat) (input : List Char) :
  recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3) (.ref "CodeBlock" ["ind"]) input =
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ind" ["ind"]) input) (fun rest0 =>
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Fence" []) rest0) (fun rest1 =>
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.opt (.ref "Lang" [])) rest1) (fun rest2 =>
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Arguments" []) rest2) (fun rest3 =>
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Sp" []) rest3) (fun rest4 =>
    next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Nl" []) rest4) (fun rest5 =>
    next (RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n ((.choice [[.notPred (.ref "CodeClose" ["ind"]), .ref "CodeLine" []]]))) (fuel + 1) rest5) (fun rest6 =>
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.label (.choice [[.ref "CodeClose" ["ind"]]]) "code_close") rest6))))))) := by
  change recognizeEnv _ [("ind", ind)] (fuel + 2) (.choice [[.ref "Ind" ["ind"], .ref "Fence" [], .opt (.ref "Lang" []), .ref "Arguments" [], .ref "Sp" [], .ref "Nl" [], .star (.choice [[.notPred (.ref "CodeClose" ["ind"]), .ref "CodeLine" []]]), .label (.choice [[.ref "CodeClose" ["ind"]]]) "code_close"]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc (fuel + 1) item rest) _ [("ind", ind)] xs input) [[.ref "Ind" ["ind"], .ref "Fence" [], .opt (.ref "Lang" []), .ref "Arguments" [], .ref "Sp" [], .ref "Nl" [], .star (.choice [[.notPred (.ref "CodeClose" ["ind"]), .ref "CodeLine" []]]), .label (.choice [[.ref "CodeClose" ["ind"]]]) "code_close"]] = _
  have rep6 := RuleRepetition.star Generated.pegGrammar [("ind", ind)] ((.choice [[.notPred (.ref "CodeClose" ["ind"]), .ref "CodeLine" []]])) (fuel + 1)
  simp only [runChoices,foldChoice,List.foldlM,bind_pure]
  rw [UnboundSequenceTotal.sequence _ _ _ _ _ (by simp)]
  simp only [follow_next,follow_end,next_end,rep6]

end BlockComposition
