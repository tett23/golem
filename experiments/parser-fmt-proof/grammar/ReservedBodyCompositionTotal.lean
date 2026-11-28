import RuleRepetition
import UnboundSequenceTotal
namespace ReservedBodyCompositionTotal
open PegModel

theorem scan_no_miss (read : Nat → List Char → ParseResult) (fuel : Nat) (input : List Char) :
    RuleRepetition.scan read fuel input ≠ .ok none := by
  induction fuel generalizing input with
  | zero => simp [RuleRepetition.scan]
  | succ fuel ih =>
      cases result : read fuel input with
      | error reason => simp [RuleRepetition.scan, result]
      | ok value => cases value with
        | none => simp [RuleRepetition.scan, result]
        | some rest =>
          by_cases progress : rest.length < input.length
          · simp [RuleRepetition.scan, result, progress, ih]
          · simp [RuleRepetition.scan, result, progress]

private def sourceRule : Rule :=
  (Generated.pegGrammar.rules.find? (fun rule => rule.name == "ReservedBracketBody")).getD default

def step : Expr :=
  let first : Option (List Expr) := sourceRule.alts.head?.map (fun alt : Alt => alt.items)
  match first with
  | some [Expr.star item] => item
  | _ => .any


def nestedItems : List Expr := match step with
  | .choice alternatives => alternatives[2]?.getD []
  | _ => []

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with | .ok (some rest) => read rest | other => other

private def layout (line : Nat) (action : Option String) (body : Expr) : Rule :=
  { name := "ReservedBracketBody", line := line, params := [], templateParams := [], resultType := "()",
    alts := [{ line := line, items := [.star body], action := action, constructor := none }] }

theorem unit_ref (grammar : Grammar) (env : Params) (fuel : Nat) (input : List Char)
    (line : Nat) (action : Option String) (body : Expr)
    (found : grammar.rules.find? (fun rule => rule.name == "ReservedBracketBody") = some (layout line action body)) :
    recognizeEnv grammar env (fuel + 1) (.ref "ReservedBracketBody" []) input =
      recognizeEnv grammar [] fuel (.choice [[.star body]]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]

private theorem nested_shape :
    nestedItems = [.lit "[" "'['", .ref "ReservedBracketBody" [], .lit "]" "']'"] := by rfl

theorem generated (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 2) (.ref "ReservedBracketBody" []) input =
      RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [] n step) fuel input := by
  rw [unit_ref _ _ _ _ sourceRule.line (sourceRule.alts.head?.bind (·.action)) step (by rfl)]
  change recognizeEnv Generated.pegGrammar [] (fuel + 1) (.choice [[.star step]]) input = _
  rw [PegModelTest.single_group _ _ _ _ _ (by simp), RuleRepetition.star]

theorem nested (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [] (fuel + 1) (.choice [nestedItems]) input =
      next (recognizeEnv Generated.pegGrammar [] fuel (.lit "[" "'['") input) (fun afterOpen =>
        next (recognizeEnv Generated.pegGrammar [] fuel (.ref "ReservedBracketBody" []) afterOpen)
          (fun afterBody => recognizeEnv Generated.pegGrammar [] fuel (.lit "]" "']'") afterBody)) := by
  rw [nested_shape]
  change runChoices (fun items => runSequence
    (fun scope item rest => recognizeEnv Generated.pegGrammar scope fuel item rest)
    _ [] items input) [[.lit "[" "'['", .ref "ReservedBracketBody" [], .lit "]" "']'"]] = _
  simp [runChoices, foldChoice, UnboundSequenceTotal.sequence, UnboundSequenceTotal.follow, next]
  cases opening : recognizeEnv Generated.pegGrammar [] fuel (.lit "[" "'['") input with
  | error reason => simp [opening]
  | ok value => cases value with
    | none => simp [opening]
    | some rest =>
      cases body : recognizeEnv Generated.pegGrammar [] fuel (.ref "ReservedBracketBody" []) rest with
      | error reason => simp [opening, body]
      | ok value => cases value with
        | none => simp [opening, body]
        | some afterBody =>
          cases closing : recognizeEnv Generated.pegGrammar [] fuel (.lit "]" "']'") afterBody with
          | error reason => simp [opening, body, closing]
          | ok value => cases value <;> simp [opening, body, closing]

theorem generated_no_miss (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 2) (.ref "ReservedBracketBody" []) input ≠ .ok none := by
  rw [generated]
  exact scan_no_miss _ _ _

#print axioms scan_no_miss
#print axioms generated
#print axioms nested
end ReservedBodyCompositionTotal
