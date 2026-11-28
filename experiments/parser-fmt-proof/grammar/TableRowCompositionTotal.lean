import InertCaptureSequenceTotal
namespace TableRowCompositionTotal
open PegModel

def items : List Expr := [.ref "Ind" ["ind"], .bind (some "cs") (.plus (.ref "TableCellAndPipe" [])), .ref "Pipe" [], .ref "Sp" [], .opt (.ref "RowBreak" [])]
private def sourceRule : Rule :=
  (Generated.pegGrammar.rules.find? (fun rule => rule.name == "TableRow")).getD default
private def layout (line : Nat) (altLine : Nat) : Rule :=
  {name := "TableRow", line := line, params := ["ind"], templateParams := [], resultType := "Int", alts := [{line := altLine, items := items, action := some " length cs ", constructor := none}]}

theorem unit_ref (grammar : Grammar) (ind fuel : Nat) (input : List Char)
    (line altLine : Nat)
    (found : grammar.rules.find? (fun rule => rule.name == "TableRow") = some (layout line altLine)) :
    recognizeEnv grammar [("ind",ind)] (fuel+1) (.ref "TableRow" ["ind"]) input =
      recognizeEnv grammar [("ind",ind)] fuel (.choice [items]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]

theorem generated (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+2) (.ref "TableRow" ["ind"]) input =
      UnboundSequenceTotal.follow (fun item rest => recognizeEnv Generated.pegGrammar [("ind",ind)] fuel item rest) items input := by
  rw [unit_ref _ _ _ _ sourceRule.line (sourceRule.alts.head?.map (·.line) |>.getD 0) (by rfl)]
  change runChoices (fun xs => runSequence (fun scope item rest => recognizeEnv Generated.pegGrammar scope fuel item rest)
    _ [("ind",ind)] xs input) [items] = _
  simp only [runChoices, foldChoice, List.foldlM]
  simp only [bind_pure]
  apply InertCaptureSequenceTotal.sequence
  intro item member scope before
  simp [items] at member
  rcases member with rfl | rfl | rfl | rfl | rfl <;> rfl

#print axioms generated
end TableRowCompositionTotal
