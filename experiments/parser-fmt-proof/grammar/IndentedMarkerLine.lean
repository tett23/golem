import IndentTotal
import LineBoundaryTotal

namespace IndentedMarkerLine

open PegModel

inductive Marker where | code | definition

def Marker.rule : Marker → String | .code => "CodeClose" | .definition => "DefNew"
def Marker.token : Marker → String | .code => "Fence" | .definition => "NewDefMark"
def Marker.text : Marker → String | .code => "```" | .definition => "=:"

private def tokenRest (m : Marker) (input : List Char) : Option (List Char) :=
  if m.text.toList.isPrefixOf input then some (input.drop m.text.toList.length) else none

private theorem token_total (m : Marker) (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref m.token []) input = .ok (tokenRest m input) := by
  let written := "'" ++ m.text ++ "'"
  have resolve : recognizeEnv Generated.pegGrammar env (fuel+3) (.ref m.token []) input =
      recognizeEnv Generated.pegGrammar [] (fuel+2) (.choice [[.lit m.text written]]) input := by
    cases m <;> rfl
  rw [resolve, PegModelTest.single_literal_choice, PegModelTest.literal_total]
  rfl

private def endLine : List Char → Option (List Char)
  | [] => some []
  | '\n' :: rest => some rest
  | _ => none

def expected (m : Marker) (ind : Nat) (input : List Char) : Option (List Char) := do
  let rest ← IndentTotal.expected ind input
  let tail ← tokenRest m rest
  endLine (tail.dropWhile LineBoundaryTotal.whitespace)

private theorem indentBound (n : Nat) (input rest : List Char)
    (ok : IndentTotal.expected n input = some rest) : rest.length ≤ input.length := by
  induction n generalizing input with
  | zero => simp [IndentTotal.expected] at ok; subst rest; exact Nat.le_refl _
  | succ n ih =>
      cases input with
      | nil => simp [IndentTotal.expected] at ok
      | cons c tail =>
          by_cases h : c = ' '
          · simp [IndentTotal.expected, h] at ok
            exact Nat.le_trans (ih tail ok) (Nat.le_succ _)
          · simp [IndentTotal.expected, h] at ok

theorem total (m : Marker) (ind extra : Nat) (input : List Char) :
    let n := input.length + 2 * ind + 7 + extra
    recognizeEnv Generated.pegGrammar [("ind", ind)] (n + 2) (.ref m.rule ["ind"]) input =
      .ok (expected m ind input) := by
  let n := input.length + 2 * ind + 7 + extra
  let env : Params := [("ind", ind)]
  let ending : Expr := .choice [[.ref "Nl" []], [.notPred .any]]
  let items : List Expr := [.ref "Ind" ["ind"], .ref m.token [], .ref "Sp" [], ending]
  change recognizeEnv Generated.pegGrammar env (n + 2) (.ref m.rule ["ind"]) input = _
  have shape : recognizeEnv Generated.pegGrammar env (n+2) (.ref m.rule ["ind"]) input =
      recognizeEnv Generated.pegGrammar env (n+1) (.choice [items]) input := by cases m <;> rfl
  rw [shape]
  change runChoices (fun xs => runSequence (fun scope e x => recognizeEnv Generated.pegGrammar scope n e x) _ env xs input) [items] = _
  have indAt := IndentTotal.generated_indent ind input env "ind" (n - (2*ind+3)) (by rfl)
  rw [show 2*ind+3 + (n - (2*ind+3)) = n by dsimp [n]; omega] at indAt
  cases i : IndentTotal.expected ind input with
  | none => simp [items, runChoices, foldChoice, runSequence, indAt, i, expected]; rfl
  | some rest =>
      have mark := token_total m env (n-3) rest
      rw [show n-3+3=n by dsimp [n]; omega] at mark
      cases t : tokenRest m rest with
      | none => simp [items, runChoices, foldChoice, runSequence, indAt, i, mark, t, expected]; rfl
      | some tail =>
          have limit := indentBound ind input rest i
          have bound : tail.length ≤ rest.length := by
            unfold tokenRest at t
            split at t <;> simp_all
            subst tail; simp; omega
          have space := LineBoundaryTotal.generated_sp env tail (n-(tail.length+7))
          rw [show tail.length+7+(n-(tail.length+7))=n by dsimp [n]; omega] at space
          have endingAt := PegModelTest.generated_newline_or_eof env (n-6) (tail.dropWhile LineBoundaryTotal.whitespace)
          rw [show n-6+6=n by dsimp [n]; omega] at endingAt
          have lineEnd : recognizeEnv Generated.pegGrammar env n ending (tail.dropWhile LineBoundaryTotal.whitespace) =
              .ok (endLine (tail.dropWhile LineBoundaryTotal.whitespace)) := by
            rw [show ending = .choice [[.ref "Nl" []], [.notPred .any]] by rfl, endingAt]
            cases tail.dropWhile LineBoundaryTotal.whitespace with
            | nil => rfl
            | cons c cs => by_cases h : c = '\n' <;> simp [h, endLine]
          cases e : endLine (tail.dropWhile LineBoundaryTotal.whitespace) <;>
            simp [items, runChoices, foldChoice, runSequence, indAt, i, mark, t, space, lineEnd, e, expected] <;> rfl

/-- The separator line of root ADR 0398: `Ind(ind) '---' EOL`. -/
def separatorExpected (ind : Nat) (input : List Char) : Option (List Char) := do
  let rest ← IndentTotal.expected ind input
  let tail ← if "---".toList.isPrefixOf rest then some (rest.drop 3) else none
  endLine (tail.dropWhile LineBoundaryTotal.whitespace)

theorem separator_total (ind extra : Nat) (input : List Char) :
    let n := input.length + 2 * ind + 9 + extra
    recognizeEnv Generated.pegGrammar [("ind", ind)] (n + 2) (.ref "SeparatorLine" ["ind"]) input =
      .ok (separatorExpected ind input) := by
  let n := input.length + 2 * ind + 9 + extra
  let env : Params := [("ind", ind)]
  let items : List Expr := [.ref "Ind" ["ind"], .lit "---" "'---'", .ref "EOL" []]
  change recognizeEnv Generated.pegGrammar env (n + 2) (.ref "SeparatorLine" ["ind"]) input = _
  have shape : recognizeEnv Generated.pegGrammar env (n+2) (.ref "SeparatorLine" ["ind"]) input =
      recognizeEnv Generated.pegGrammar env (n+1) (.choice [items]) input := rfl
  rw [shape]
  change runChoices (fun xs => runSequence (fun scope e x => recognizeEnv Generated.pegGrammar scope n e x) _ env xs input) [items] = _
  have indAt := IndentTotal.generated_indent ind input env "ind" (n - (2*ind+3)) (by rfl)
  rw [show 2*ind+3 + (n - (2*ind+3)) = n by dsimp [n]; omega] at indAt
  cases i : IndentTotal.expected ind input with
  | none => simp [items, runChoices, foldChoice, runSequence, indAt, i, separatorExpected]; rfl
  | some rest =>
      have limit := indentBound ind input rest i
      have mark := PegModelTest.literal_total Generated.pegGrammar env (n-1) "---" "'---'" rest
      rw [show n-1+1=n by dsimp [n]; omega] at mark
      cases hp : "---".toList.isPrefixOf rest with
      | false =>
          simp [items, runChoices, foldChoice, runSequence, indAt, i, mark, hp, separatorExpected]; rfl
      | true =>
          have drop3 : rest.drop "---".toList.length = rest.drop 3 := rfl
          have bound : (rest.drop 3).length ≤ rest.length := by simp [Nat.sub_le]
          have eol := LineBoundaryTotal.generated_eol env (rest.drop 3) (n - ((rest.drop 3).length + 9))
          rw [show (rest.drop 3).length + 9 + (n - ((rest.drop 3).length + 9)) = n by dsimp [n]; omega] at eol
          cases suffix : (rest.drop 3).dropWhile LineBoundaryTotal.whitespace with
          | nil =>
              rw [suffix] at eol
              simp [items, runChoices, foldChoice, runSequence, indAt, i, mark, hp, drop3, eol, suffix,
                separatorExpected, endLine] <;> rfl
          | cons c cs =>
              rw [suffix] at eol
              by_cases line : c = '\n'
              · subst line
                simp [items, runChoices, foldChoice, runSequence, indAt, i, mark, hp, drop3, eol, suffix,
                  separatorExpected, endLine] <;> rfl
              · simp [items, runChoices, foldChoice, runSequence, indAt, i, mark, hp, drop3, eol, suffix,
                  line, separatorExpected, endLine] <;> rfl

end IndentedMarkerLine
