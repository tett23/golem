import PegModelTest

namespace FileCompositionTotal
open PegModel

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

private def optional (input : List Char) : ParseResult → ParseResult
  | .ok none => .ok (some input)
  | other => other

theorem optional_eq (grammar : Grammar) (env : Params) (fuel : Nat) (item : Expr) (input : List Char) :
    recognizeEnv grammar env (fuel + 1) (.opt item) input =
      optional input (recognizeEnv grammar env fuel item input) := by
  change (match recognizeEnv grammar env fuel item input with
    | .error reason => Except.error reason
    | .ok none => Except.ok (some input)
    | .ok hit => Except.ok hit) = _
  cases hit : recognizeEnv grammar env fuel item input with
  | error reason => rfl
  | ok value => cases value <;> rfl

def body : Expr := .choice [[.andPred .any, .ref "Blocks" ["0"], .opt (.ref "BlankLines" [])]]

theorem nonempty_guard (grammar : Grammar) (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv grammar env (fuel + 2) (.andPred .any) input =
      if input.isEmpty then .ok none else .ok (some input) := by
  cases input <;> rfl

theorem body_eq (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [] (fuel + 3) body input =
      if input.isEmpty then .ok none else
        next (recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "Blocks" ["0"]) input)
          (fun rest => optional rest
            (recognizeEnv Generated.pegGrammar [] (fuel + 1) (.ref "BlankLines" []) rest)) := by
  change runChoices (fun items => runSequence
    (fun scope item rest => recognizeEnv Generated.pegGrammar scope (fuel + 2) item rest)
    _ [] items input) [[.andPred .any, .ref "Blocks" ["0"], .opt (.ref "BlankLines" [])]] = _
  cases input with
  | nil => simp [runChoices, foldChoice, runSequence, nonempty_guard]; rfl
  | cons c cs =>
      cases blocks : recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "Blocks" ["0"]) (c :: cs) with
      | error reason => simp [runChoices, foldChoice, runSequence, nonempty_guard, List.isEmpty, optional_eq, next, blocks]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, nonempty_guard, List.isEmpty, optional_eq, next, blocks]; rfl
        | some rest =>
          cases blanks : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.ref "BlankLines" []) rest with
          | error reason => simp [runChoices, foldChoice, runSequence, nonempty_guard, List.isEmpty, optional_eq, next, optional, blocks, blanks]; rfl
          | ok value => cases value <;>
            simp [runChoices, foldChoice, runSequence, nonempty_guard, List.isEmpty, optional_eq, next, optional, blocks, blanks] <;> rfl

private def fileRule (line : Nat) (action : Option String) : Rule :=
  { name := "File", line := line, params := [], templateParams := [], resultType := "()",
    alts := [{ line := line, items := [.opt (.ref "BlankLines" []), .opt body], action := action, constructor := none }] }

theorem file_ref (grammar : Grammar) (env : Params) (fuel : Nat) (input : List Char)
    (line : Nat) (action : Option String)
    (found : grammar.rules.find? (fun rule => rule.name == "File") = some (fileRule line action)) :
    recognizeEnv grammar env (fuel + 1) (.ref "File" []) input =
      recognizeEnv grammar [] fuel (.choice [[.opt (.ref "BlankLines" []), .opt body]]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]

theorem generated_file (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 6) (.ref "File" []) input =
      next (optional input
        (recognizeEnv Generated.pegGrammar [] (fuel + 3) (.ref "BlankLines" []) input))
        (fun rest => optional rest (if rest.isEmpty then .ok none else
          next (recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "Blocks" ["0"]) rest)
            (fun tail => optional tail
              (recognizeEnv Generated.pegGrammar [] (fuel + 1) (.ref "BlankLines" []) tail)))) := by
  rw [file_ref _ _ _ _ 179 (some " () ") (by rfl)]
  simp only [← body_eq]
  change runChoices (fun items => runSequence
    (fun scope item rest => recognizeEnv Generated.pegGrammar scope (fuel + 4) item rest)
    _ [] items input) [[.opt (.ref "BlankLines" []), .opt body]] = _
  cases first : recognizeEnv Generated.pegGrammar [] (fuel + 3) (.ref "BlankLines" []) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, optional, optional_eq, first]; rfl
  | ok value => cases value with
    | none =>
      cases later : recognizeEnv Generated.pegGrammar [] (fuel + 3) body input with
      | error reason => simp [runChoices, foldChoice, runSequence, next, optional, optional_eq, first, later]; rfl
      | ok value => cases value <;>
        simp [runChoices, foldChoice, runSequence, next, optional, optional_eq, first, later] <;> rfl
    | some rest =>
      cases later : recognizeEnv Generated.pegGrammar [] (fuel + 3) body rest with
      | error reason => simp [runChoices, foldChoice, runSequence, next, optional, optional_eq, first, later]; rfl
      | ok value => cases value <;>
        simp [runChoices, foldChoice, runSequence, next, optional, optional_eq, first, later] <;> rfl

#print axioms nonempty_guard
#print axioms body_eq
#print axioms generated_file
end FileCompositionTotal
