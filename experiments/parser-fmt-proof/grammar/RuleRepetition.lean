import PegModelTest

namespace RuleRepetition

open PegModel

/-- A repetition consults the item at each suffix using the same remaining
    fuel as the PEG interpreter. Stop on an ordinary miss; propagate errors. -/
def scan (read : Nat → List Char → ParseResult) : Nat → List Char → ParseResult
  | 0, _ => .error "fuel exhausted"
  | fuel + 1, input =>
      match read fuel input with
      | .error reason => .error reason
      | .ok none => .ok (some input)
      | .ok (some rest) => if rest.length < input.length then scan read fuel rest
                            else .error "zero-width repetition"

theorem star (grammar : Grammar) (env : Params) (item : Expr) (fuel : Nat) (input : List Char) :
    recognizeEnv grammar env fuel (.star item) input =
      scan (fun n => recognizeEnv grammar env n item) fuel input := by
  induction fuel generalizing input with
  | zero => rfl
  | succ n ih =>
      unfold scan
      change (match recognizeEnv grammar env n item input with
        | .error reason => Except.error reason
        | .ok none => Except.ok (some input)
        | .ok (some rest) => if rest.length < input.length then recognizeEnv grammar env n (.star item) rest
                              else Except.error "zero-width repetition") = _
      cases result : recognizeEnv grammar env n item input with
      | error reason => rfl
      | ok value =>
          cases value with
          | none => rfl
          | some rest => simp [ih]

theorem generated_slot (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2) (.ref "ProseSlot" ["ind"]) input =
      scan (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n (.ref "SlotInline" ["ind"])) fuel input := by
  change recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
    (.choice [[.star (.ref "SlotInline" ["ind"])]]) input = _
  rw [PegModelTest.single_group _ _ _ _ _ (by simp), star]

theorem generated_table_cell (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 2) (.ref "TableCell" []) input =
      scan (fun n => recognizeEnv Generated.pegGrammar [] n (.ref "CellInline" [])) fuel input := by
  change recognizeEnv Generated.pegGrammar [] (fuel + 1)
    (.choice [[.star (.ref "CellInline" [])]]) input = _
  rw [PegModelTest.single_group _ _ _ _ _ (by simp), star]

private def recoveryArgument : Expr := .choice [[.ref "Sp" [], .ref "PosArg" []]]

theorem generated_skipped (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "SkippedArgs" []) input =
      match recognizeEnv Generated.pegGrammar [] fuel recoveryArgument input with
      | .error reason => .error reason
      | .ok none => .ok none
      | .ok (some rest) => if rest.length < input.length then
          scan (fun n => recognizeEnv Generated.pegGrammar [] n recoveryArgument) fuel rest
        else .error "zero-width repetition" := by
  change recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice [[.plus recoveryArgument]]) input = _
  rw [PegModelTest.single_group _ _ _ _ _ (by simp)]
  change (match recognizeEnv Generated.pegGrammar [] fuel recoveryArgument input with
    | .error reason => Except.error reason
    | .ok none => Except.ok none
    | .ok (some rest) => if rest.length < input.length then recognizeEnv Generated.pegGrammar [] fuel (.star recoveryArgument) rest
                          else Except.error "zero-width repetition") = _
  cases result : recognizeEnv Generated.pegGrammar [] fuel recoveryArgument input with
  | error reason => rfl
  | ok value =>
      cases value with
      | none => rfl
      | some rest => simp [star]

end RuleRepetition
