import ThrowingPrefixTotal

open PegModelTest ThrowingPrefixTotal
set_option maxHeartbeats 1000000

namespace BackslashTotal

def expected (value next : String) (input : List Char) : Option (List Char) :=
  if value.toList.isPrefixOf input then
    let rest := input.drop value.toList.length
    if next.toList.isPrefixOf rest then some rest else none
  else none

theorem literal_then_lookahead (grammar : PegModel.Grammar) (env : PegModel.Params)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (value written next nextWritten : String) (input : List Char) (fuel : Nat) :
    PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 2) item rest)
      boundLength env [.lit value written, .andPred (.lit next nextWritten)] input =
      .ok (expected value next input) := by
  have literal := PegModelTest.literal_total grammar env (fuel + 1) value written input
  have literalFuel : fuel + 1 + 1 = fuel + 2 := by omega
  rw [literalFuel] at literal
  cases hp : value.toList.isPrefixOf input with
  | false => simp [PegModel.runSequence, literal, hp, expected] <;> rfl
  | true =>
      have look := ThrowingPrefixTotal.literal_lookahead_total grammar env fuel
        next nextWritten (input.drop value.toList.length)
      cases hn : next.toList.isPrefixOf (input.drop value.toList.length) <;>
        simp [PegModel.runSequence, literal, look, hp, hn, expected] <;> rfl

theorem generated_backslash (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 4)
      (.ref "Backslash" []) input =
      .ok (expected "\\" "\n" input) := by
  have refFuel : fuel + 4 = (fuel + 3) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
    (.choice [[.lit "\\" "'\\\\'", .andPred (.lit "\n" "'\\n'")]]) input = _
  have choiceFuel : fuel + 3 = (fuel + 2) + 1 := by omega
  rw [choiceFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 2) item rest)
      _ [] items input)
    [[.lit "\\" "'\\\\'", .andPred (.lit "\n" "'\\n'")]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  rw [literal_then_lookahead Generated.pegGrammar [] _ "\\" "'\\\\'" "\n" "'\\n'" input fuel]
  rfl

example : PegModel.recognizeEnv Generated.pegGrammar [] 4
    (.ref "Backslash" []) "\\\n".toList = .ok (some "\n".toList) := by
  simpa using generated_backslash "\\\n".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 4
    (.ref "Backslash" []) "\\x".toList = .ok none := by
  simpa using generated_backslash "\\x".toList 0

open PegModel

private theorem backslash_in_scope (env : Params) (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar env (fuel+4) (.ref "Backslash" []) input =
      .ok (expected "\\" "\n" input) := by
  exact generated_backslash input fuel

private def hasNext (result : ParseResult) : ParseResult :=
  match result with
  | .ok (some []) => .ok none
  | other => other

private theorem look_any (env : Params) (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar env (fuel+4) (.andPred .any) input =
      (match input with | [] => .ok none | _ :: _ => .ok (some input)) := by
  cases input <;> rfl

theorem generated_hard_break (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel+6) (.ref "HardBreak" ["ind"]) input =
      match expected "\\" "\n" input with
      | none => .ok none
      | some tail => hasNext (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel+4)
          (.ref "LineContinuation" ["ind"]) tail) := by
  change runChoices (fun items => runSequence (fun scope e x => recognizeEnv Generated.pegGrammar scope (fuel+4) e x)
    _ [("ind", ind)] items input)
    [[.ref "Backslash" [], .ref "LineContinuation" ["ind"], .andPred .any]] = _
  have opening := backslash_in_scope [("ind", ind)] input fuel
  cases slash : expected "\\" "\n" input with
  | none => simp [runChoices, foldChoice, runSequence, opening, slash]; rfl
  | some tail =>
      cases line : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel+4) (.ref "LineContinuation" ["ind"]) tail with
      | error reason => simp [runChoices, foldChoice, runSequence, opening, slash, line, hasNext]; rfl
      | ok value =>
          cases value with
          | none => simp [runChoices, foldChoice, runSequence, opening, slash, line, hasNext]; rfl
          | some rest => cases rest <;> simp [runChoices, foldChoice, runSequence, opening, slash, line, look_any, hasNext] <;> rfl

end BackslashTotal
