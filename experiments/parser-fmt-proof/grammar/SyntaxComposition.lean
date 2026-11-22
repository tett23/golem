import LexicalTotal
import IndentTotal

namespace SyntaxComposition

open PegModel PegModelTest

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

private def variableStep := Expr.choice [[.ref "ES" [], .ref "Dot" [], .ref "ES" [], .ref "ExprIdent" []]]
private def proseStep := Expr.choice [[.ref "Sp" [], .ref "Pipe" [], .ref "Sp" [], .ref "ProseSlot" ["ind"]]]

/-- Canonical VarExpr for every input suffix and fuel budget, including
    ordinary misses and errors. This is a recognition composition theorem;
    Haskell actions, AST equality and formatting are separate obligations. -/
theorem I1_I2_generated_variable (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "VarExpr" []) input =
      next (recognizeEnv Generated.pegGrammar [] (fuel + 1) (.notPred (.ref "Keyword" [])) input) (fun rest0 =>
        next (recognizeEnv Generated.pegGrammar [] (fuel + 1) (.ref "ExprIdent" []) rest0) (fun rest1 =>
        RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [] n variableStep) (fuel + 1) rest1)) := by
  change recognizeEnv _ [] (fuel + 2) (.choice [[.notPred (.ref "Keyword" []), .ref "ExprIdent" [], .star variableStep]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 1) item rest) _ [] xs input) [[.notPred (.ref "Keyword" []), .ref "ExprIdent" [], .star variableStep]] = _
  have repeated := RuleRepetition.star Generated.pegGrammar [] variableStep (fuel + 1)
  cases read0 : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.notPred (.ref "Keyword" [])) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, read0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, repeated, read0]; rfl
    | some rest0 =>
      cases read1 : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.ref "ExprIdent" []) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1]; rfl
        | some rest1 =>
          cases read2 : RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [] n variableStep) (fuel + 1) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1, read2]; rfl
          | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1, read2] <;> rfl

/-- Canonical ProseSlots for every input suffix and fuel budget, including
    ordinary misses and errors. This is a recognition composition theorem;
    Haskell actions, AST equality and formatting are separate obligations. -/
theorem I1_I2_generated_prose_slots (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3) (.ref "ProseSlots" ["ind"]) input =
      next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Sp" []) input) (fun rest0 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Colon" []) rest0) (fun rest1 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Sp" []) rest1) (fun rest2 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "ProseSlot" ["ind"]) rest2) (fun rest3 =>
        RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n proseStep) (fuel + 1) rest3)))) := by
  change recognizeEnv _ [("ind", ind)] (fuel + 2) (.choice [[.ref "Sp" [], .ref "Colon" [], .ref "Sp" [], .ref "ProseSlot" ["ind"], .star proseStep]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 1) item rest) _ [("ind", ind)] xs input) [[.ref "Sp" [], .ref "Colon" [], .ref "Sp" [], .ref "ProseSlot" ["ind"], .star proseStep]] = _
  have repeated := RuleRepetition.star Generated.pegGrammar [("ind", ind)] proseStep (fuel + 1)
  cases read0 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Sp" []) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, read0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, repeated, read0]; rfl
    | some rest0 =>
      cases read1 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Colon" []) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1]; rfl
        | some rest1 =>
          cases read2 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Sp" []) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1, read2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1, read2]; rfl
            | some rest2 =>
              cases read3 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "ProseSlot" ["ind"]) rest2 with
              | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1, read2, read3]; rfl
              | ok value => cases value with
                | none => simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1, read2, read3]; rfl
                | some rest3 =>
                  cases read4 : RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n proseStep) (fuel + 1) rest3 with
                  | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1, read2, read3, read4]; rfl
                  | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, repeated, read0, read1, read2, read3, read4] <;> rfl

/-- Canonical LineContinuation for every input suffix and fuel budget, including
    ordinary misses and errors. This is a recognition composition theorem;
    Haskell actions, AST equality and formatting are separate obligations. -/
theorem I1_I2_generated_continuation (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3) (.ref "LineContinuation" ["ind"]) input =
      next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Nl" []) input) (fun rest0 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.notPred (.ref "BlankLine" [])) rest0) (fun rest1 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ind" ["ind"]) rest1) (fun rest2 =>
        recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.notPred (.ref "BlockStart" [])) rest2))) := by
  change recognizeEnv _ [("ind", ind)] (fuel + 2) (.choice [[.ref "Nl" [], .notPred (.ref "BlankLine" []), .ref "Ind" ["ind"], .notPred (.ref "BlockStart" [])]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 1) item rest) _ [("ind", ind)] xs input) [[.ref "Nl" [], .notPred (.ref "BlankLine" []), .ref "Ind" ["ind"], .notPred (.ref "BlockStart" [])]] = _
  cases read0 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Nl" []) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, read0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, read0]; rfl
    | some rest0 =>
      cases read1 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.notPred (.ref "BlankLine" [])) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, read0, read1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, read0, read1]; rfl
        | some rest1 =>
          cases read2 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ind" ["ind"]) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, read0, read1, read2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, read0, read1, read2]; rfl
            | some rest2 =>
              cases read3 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.notPred (.ref "BlockStart" [])) rest2 with
              | error reason => simp [runChoices, foldChoice, runSequence, next, read0, read1, read2, read3]; rfl
              | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, read0, read1, read2, read3] <;> rfl

end SyntaxComposition
