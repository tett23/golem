import RuleRepetition
namespace PlusComposition
open PegModel

def scanPlus (read : Nat → List Char → ParseResult) (fuel : Nat) (input : List Char) : ParseResult :=
  match read fuel input with
  | .error reason => .error reason
  | .ok none => .ok none
  | .ok (some rest) => if rest.length < input.length then RuleRepetition.scan read fuel rest
                       else .error "zero-width repetition"

theorem plus (grammar : Grammar) (env : Params) (item : Expr) (fuel : Nat) (input : List Char) :
    recognizeEnv grammar env (fuel + 1) (.plus item) input =
      scanPlus (fun n => recognizeEnv grammar env n item) fuel input := by
  change (match recognizeEnv grammar env fuel item input with
    | .error reason => Except.error reason
    | .ok none => Except.ok none
    | .ok (some rest) => if rest.length < input.length then recognizeEnv grammar env fuel (.star item) rest
                          else Except.error "zero-width repetition") = _
  cases result : recognizeEnv grammar env fuel item input with
  | error reason => simp [scanPlus, result]
  | ok value => cases value with
    | none => simp [scanPlus, result]
    | some rest => simp [scanPlus, result, RuleRepetition.star]
end PlusComposition
