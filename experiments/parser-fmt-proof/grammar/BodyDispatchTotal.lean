import DefinitionCompositionTotal

namespace BodyDispatchTotal
open PegModel
private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

private def commandRule (line : Nat) (action : Option String) : Rule :=
  { name := "CommandBody", line := line, params := ["ind"], templateParams := [], resultType := "()",
    alts := [{ line := line, items := [DefinitionCompositionTotal.bodyGuard, .ref "Blocks" ["col ind + 2"]], action := action, constructor := none }] }

theorem command_ref (grammar : Grammar) (ind fuel : Nat) (input : List Char)
    (line : Nat) (action : Option String)
    (found : grammar.rules.find? (fun rule => rule.name == "CommandBody") = some (commandRule line action)) :
    recognizeEnv grammar [("ind", ind)] (fuel + 1) (.ref "CommandBody" ["ind"]) input =
      recognizeEnv grammar [("ind", ind)] fuel
        (.choice [[DefinitionCompositionTotal.bodyGuard, .ref "Blocks" ["col ind + 2"]]]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]

theorem generated_command_body (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3)
      (.ref "CommandBody" ["ind"]) input =
      next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
        DefinitionCompositionTotal.bodyGuard input) (fun rest =>
        recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
          (.ref "Blocks" ["col ind + 2"]) rest) := by
  rw [command_ref _ _ _ _ 649 (some " () ") (by rfl)]
  change runChoices (fun xs => runSequence
    (fun scope item rest => recognizeEnv Generated.pegGrammar scope (fuel + 1) item rest)
    _ [("ind", ind)] xs input)
    [[DefinitionCompositionTotal.bodyGuard, .ref "Blocks" ["col ind + 2"]]] = _
  unfold DefinitionCompositionTotal.bodyGuard
  cases guard : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
      (.andPred (.choice [[.ref "Ind" ["col ind + 2"],
        .notPred (.charClass [(32, 32), (9, 9)] "[ \\t]"),
        .notPred (.ref "BlankLine" []), .any]])) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, guard]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, guard]; rfl
    | some rest =>
      cases body : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
          (.ref "Blocks" ["col ind + 2"]) rest with
      | error reason => simp [runChoices, foldChoice, runSequence, next, guard, body]; rfl
      | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, guard, body] <;> rfl

def groupGuard : Expr :=
  .andPred (.choice [[.ref "Ind" ["ind"], .notPred (.ref "BlockCommandStart" []),
    .notPred (.charClass [(32,32),(9,9)] "[ \\t]"), .notPred (.ref "BlankLine" [])]])

private def groupRule (line otherLine : Nat) (action : Option String) : Rule :=
  { name := "GroupBody", line := line, params := ["ind"], templateParams := [], resultType := "()",
    alts := [{ line := line, items := [.ref "Div" ["ind"]], action := action, constructor := none },
      { line := otherLine, items := [groupGuard, .ref "AttributedBlock" ["ind"]], action := action, constructor := none }] }

theorem group_ref (grammar : Grammar) (ind fuel : Nat) (input : List Char)
    (line otherLine : Nat) (action : Option String)
    (found : grammar.rules.find? (fun rule => rule.name == "GroupBody") = some (groupRule line otherLine action)) :
    recognizeEnv grammar [("ind", ind)] (fuel + 1) (.ref "GroupBody" ["ind"]) input =
      recognizeEnv grammar [("ind", ind)] fuel
        (.choice [[.ref "Div" ["ind"]], [groupGuard, .ref "AttributedBlock" ["ind"]]]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]

theorem generated_group_body (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3)
      (.ref "GroupBody" ["ind"]) input =
      match recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
          (.ref "Div" ["ind"]) input with
      | .ok none =>
          next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) groupGuard input)
            (fun rest => recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
              (.ref "AttributedBlock" ["ind"]) rest)
      | result => result := by
  rw [group_ref _ _ _ _ 604 605 (some " () ") (by rfl)]
  change runChoices (fun xs => runSequence
    (fun scope item rest => recognizeEnv Generated.pegGrammar scope (fuel + 1) item rest)
    _ [("ind", ind)] xs input)
    [[.ref "Div" ["ind"]], [groupGuard, .ref "AttributedBlock" ["ind"]]] = _
  unfold groupGuard
  cases fenced : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Div" ["ind"]) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, fenced]; rfl
  | ok value => cases value with
    | some rest => simp [runChoices, foldChoice, runSequence, next, fenced]; rfl
    | none =>
      cases guard : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
        (.andPred (.choice [[.ref "Ind" ["ind"], .notPred (.ref "BlockCommandStart" []),
          .notPred (.charClass [(32,32),(9,9)] "[ \\t]"), .notPred (.ref "BlankLine" [])]])) input with
      | error reason => simp [runChoices, foldChoice, runSequence, next, fenced, guard]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, fenced, guard]; rfl
        | some rest =>
          cases body : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
              (.ref "AttributedBlock" ["ind"]) rest with
          | error reason => simp [runChoices, foldChoice, runSequence, next, fenced, guard, body]; rfl
          | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, fenced, guard, body] <;> rfl

#print axioms generated_command_body
#print axioms generated_group_body
end BodyDispatchTotal
