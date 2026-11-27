import ListCompositionTotal

namespace BlockSequenceTotal
open PegModel

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

def blocksStep : Expr :=
  .choice [[.opt (.ref "BlankLines" []),
    .andPred (.choice [[.ref "Ind" ["ind"], .notPred (.ref "BlankLine" []), .any]]),
    .ref "Block" ["ind"]]]

def nonblankGuard : Expr :=
  .andPred (.choice [[.ref "Ind" ["ind"],
    .notPred (.charClass [(32, 32), (9, 9)] "[ \\t]"),
    .notPred (.ref "BlankLine" []), .any]])

def itemStep : Expr :=
  .choice [[.opt (.ref "BlankLines" []), nonblankGuard, .ref "Block" ["ind"]]]

def divStep : Expr :=
  .choice [[.opt (.ref "BlankLines" []),
    .notPred (.choice [[.ref "Ind" ["ind"], .ref "DivLine" []]]),
    nonblankGuard, .ref "Block" ["ind"]]]

/-- The actual Blocks rule requires the first child and then scans guarded
    children, preserving arbitrary child outcomes and repetition progress. -/
theorem generated_blocks (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3)
      (.ref "Blocks" ["ind"]) input =
      next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
        (.ref "Block" ["ind"]) input) (fun rest =>
        RuleRepetition.scan
          (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n blocksStep)
          (fuel + 1) rest) := by
  change recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2)
    (.choice [[.ref "Block" ["ind"], .star blocksStep]]) input = _
  exact ListCompositionTotal.first_then_repeated _ _ _ _ _ _ _

/-- The actual ItemTail is a zero-or-more scan of its guarded block step.
    A failed step retains the input before its optional blank lines. -/
theorem generated_item_tail (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2)
      (.ref "ItemTail" ["ind"]) input =
      RuleRepetition.scan
        (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n itemStep)
        fuel input := by
  change recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
    (.choice [[.star itemStep]]) input = _
  rw [PegModelTest.single_group _ _ _ _ _ (by simp), RuleRepetition.star]

/-- The actual fenced-body scan retains the closing-line guard. Its child
    outcomes, fuel exhaustion and zero-width errors remain in the result. -/
theorem generated_div_blocks (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2)
      (.ref "DivBlocks" ["ind"]) input =
      RuleRepetition.scan
        (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n divStep)
        fuel input := by
  change recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
    (.choice [[.star divStep]]) input = _
  rw [PegModelTest.single_group _ _ _ _ _ (by simp), RuleRepetition.star]

#print axioms generated_blocks
#print axioms generated_item_tail
#print axioms generated_div_blocks

end BlockSequenceTotal
