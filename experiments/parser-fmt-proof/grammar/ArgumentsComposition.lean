import ExpressionComposition
import SyntaxComposition

namespace ArgumentsComposition

open PegModel PegModelTest

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

private def noComment := Expr.notPred (.lit "%%" "'%%'")
private def noKeyword := Expr.notPred (.choice [[.ref "Word" [], .ref "Eq" []]])
private def positionalBranches : List (List Expr) :=
  [[noComment, noKeyword, .notPred (.lit "**[" "'**['"), .ref "SplatArgument" []],
   [noComment, noKeyword, .notPred (.ref "Splat" []), .ref "Argument" []]]

/-- Both branches restart at the same suffix. Only ordinary failure allows
    the normal argument branch after a splat attempt; errors retain priority. -/
theorem I1_I2_generated_positional (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "PosArg" []) input =
      ExpressionComposition.choose (positionalBranches.map (fun items =>
        recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice [items]) input)) := by
  change recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice positionalBranches) input = _
  rw [ExpressionComposition.regroup]
  exact ExpressionComposition.choices_eq _ _

private def comments := Expr.choice [[.ref "Sp" [], .ref "ArgComment" []]]
private def positional := Expr.choice [[.ref "Sp" [], .ref "PosArg" [], .star comments]]
private def keyword := Expr.choice [[.ref "Sp" [], .ref "KwArg" [], .star comments]]

/-- The canonical Arguments sequence for every suffix and fuel budget.
    Comment loops, keyword ordering and closing labels keep their error result;
    no AST/action/formatter equivalence is assumed. -/
theorem I1_I2_generated_arguments (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "Arguments" []) input =
      next (RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [] n comments) (fuel + 1) input) (fun rest0 =>
        next (RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [] n positional) (fuel + 1) rest0) (fun rest1 =>
        next (RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [] n keyword) (fuel + 1) rest1) (fun rest2 =>
        recognizeEnv Generated.pegGrammar [] (fuel + 1) (.label (.choice [[.notPred (.choice [[.ref "Sp" [], .ref "PosArg" []]])]]) "arg_order") rest2))) := by
  change recognizeEnv _ [] (fuel + 2) (.choice [[.star comments, .star positional, .star keyword, .label (.choice [[.notPred (.choice [[.ref "Sp" [], .ref "PosArg" []]])]]) "arg_order"]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 1) item rest) _ [] xs input) [[.star comments, .star positional, .star keyword, .label (.choice [[.notPred (.choice [[.ref "Sp" [], .ref "PosArg" []]])]]) "arg_order"]] = _
  have repeated0 := RuleRepetition.star Generated.pegGrammar [] comments (fuel + 1)
  have repeated1 := RuleRepetition.star Generated.pegGrammar [] positional (fuel + 1)
  have repeated2 := RuleRepetition.star Generated.pegGrammar [] keyword (fuel + 1)
  cases read0 : RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [] n comments) (fuel + 1) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, repeated0, repeated1, repeated2, read0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, repeated0, repeated1, repeated2, read0]; rfl
    | some rest0 =>
      cases read1 : RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [] n positional) (fuel + 1) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, repeated0, repeated1, repeated2, read0, read1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, repeated0, repeated1, repeated2, read0, read1]; rfl
        | some rest1 =>
          cases read2 : RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [] n keyword) (fuel + 1) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, repeated0, repeated1, repeated2, read0, read1, read2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, repeated0, repeated1, repeated2, read0, read1, read2]; rfl
            | some rest2 =>
              cases read3 : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.label (.choice [[.notPred (.choice [[.ref "Sp" [], .ref "PosArg" []]])]]) "arg_order") rest2 with
              | error reason => simp [runChoices, foldChoice, runSequence, next, repeated0, repeated1, repeated2, read0, read1, read2, read3]; rfl
              | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, repeated0, repeated1, repeated2, read0, read1, read2, read3] <;> rfl

/-- The canonical InlineCommand sequence for every suffix and fuel budget.
    Comment loops, keyword ordering and closing labels keep their error result;
    no AST/action/formatter equivalence is assumed. -/
theorem I1_I2_generated_inline (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3) (.ref "InlineCommand" ["ind"]) input =
      next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "LBr" []) input) (fun rest0 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ident" []) rest0) (fun rest1 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Arguments" []) rest1) (fun rest2 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.opt (.ref "ProseSlots" ["ind"])) rest2) (fun rest3 =>
        recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.label (.choice [[.ref "Sp" [], .ref "RBr" []]]) "close") rest3)))) := by
  change recognizeEnv _ [("ind", ind)] (fuel + 2) (.choice [[.ref "LBr" [], .ref "Ident" [], .ref "Arguments" [], .opt (.ref "ProseSlots" ["ind"]), .label (.choice [[.ref "Sp" [], .ref "RBr" []]]) "close"]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 1) item rest) _ [("ind", ind)] xs input) [[.ref "LBr" [], .ref "Ident" [], .ref "Arguments" [], .opt (.ref "ProseSlots" ["ind"]), .label (.choice [[.ref "Sp" [], .ref "RBr" []]]) "close"]] = _
  cases read0 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "LBr" []) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, read0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, read0]; rfl
    | some rest0 =>
      cases read1 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ident" []) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, read0, read1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, read0, read1]; rfl
        | some rest1 =>
          cases read2 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Arguments" []) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, read0, read1, read2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, read0, read1, read2]; rfl
            | some rest2 =>
              cases read3 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.opt (.ref "ProseSlots" ["ind"])) rest2 with
              | error reason => simp [runChoices, foldChoice, runSequence, next, read0, read1, read2, read3]; rfl
              | ok value => cases value with
                | none => simp [runChoices, foldChoice, runSequence, next, read0, read1, read2, read3]; rfl
                | some rest3 =>
                  cases read4 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.label (.choice [[.ref "Sp" [], .ref "RBr" []]]) "close") rest3 with
                  | error reason => simp [runChoices, foldChoice, runSequence, next, read0, read1, read2, read3, read4]; rfl
                  | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, read0, read1, read2, read3, read4] <;> rfl

end ArgumentsComposition
