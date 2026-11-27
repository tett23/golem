import RuleRepetition

namespace ListCompositionTotal
open PegModel

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

-- An optional blank-line run belongs to the repeated step, not to the first
-- item. The actual ListItem reader, including its errors, stays in the model.
def step (ordered : String) : Expr :=
  .choice [[.opt (.ref "BlankLines" []), .ref "ListItem" ["ind", ordered]]]

theorem first_then_repeated (grammar : Grammar) (env : Params)
    (name : String) (args : List String) (repeated : Expr) (fuel : Nat) (input : List Char) :
    recognizeEnv grammar env (fuel + 2) (.choice [[.ref name args, .star repeated]]) input =
      next (recognizeEnv grammar env (fuel + 1) (.ref name args) input) (fun rest =>
        RuleRepetition.scan (fun n => recognizeEnv grammar env n repeated) (fuel + 1) rest) := by
  change runChoices (fun xs => runSequence
    (fun sc item rest => recognizeEnv grammar sc (fuel + 1) item rest)
    _ env xs input) [[.ref name args, .star repeated]] = _
  have rep := RuleRepetition.star grammar env repeated (fuel + 1)
  cases result : recognizeEnv grammar env (fuel + 1) (.ref name args) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, rep, result]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, rep, result]; rfl
    | some rest =>
      cases more : RuleRepetition.scan (fun n => recognizeEnv grammar env n repeated) (fuel + 1) rest with
      | error reason => simp [runChoices, foldChoice, runSequence, next, rep, result, more]; rfl
      | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, rep, result, more] <;> rfl

/-- Exact composition of both generated list rules for every input,
    indentation and fuel. No child success or result equality is assumed.
    AST actions and complete recursive ListItem semantics remain separate. -/
theorem generated_list (ordered : Bool) (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3)
      (.ref (if ordered then "OrderedList" else "BulletList") ["ind"]) input =
      next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
        (.ref "ListItem" ["ind", if ordered then "1" else "0"]) input) (fun rest =>
        RuleRepetition.scan
          (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n (step (if ordered then "1" else "0")))
          (fuel + 1) rest) := by
  cases ordered <;>
    change recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2)
      (.choice [[.ref "ListItem" ["ind", _], .star (step _)]]) input = _ <;>
    exact first_then_repeated _ _ _ _ _ _ _

#print axioms first_then_repeated
#print axioms generated_list

end ListCompositionTotal
