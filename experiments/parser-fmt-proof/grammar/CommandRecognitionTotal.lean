import InertCaptureSequenceTotal
namespace CommandRecognitionTotal
open PegModel
def setItems : List Expr := [.ref "Ind" ["ind"], .ref "At" [], .ref "SetIdent" [], .ref "Ws" [], .ref "SetName" [], .ref "Sp" [], .ref "Eq" [], .ref "ExprBody" [], .choice [[.ref "Nl" []], [.notPred (.any)]]]
def callItems : List Expr := [.ref "Ind" ["ind"], .ref "At" [], .ref "Ident" [], .ref "Arguments" [], .ref "Sp" [], .choice [[.ref "Nl" []], [.notPred (.any)]], .bind (some "b") (.opt (.ref "CommandBody" ["ind"]))]
private def sourceRule : Rule :=
  (Generated.pegGrammar.rules.find? (fun rule => rule.name == "BlockCommand")).getD default
private def layout (line firstLine secondLine : Nat) : Rule :=
  {name := "BlockCommand", line := line, params := ["ind"], templateParams := [], resultType := "Bool", alts := [
   {line := firstLine, items := setItems, action := some " False ", constructor := none},
   {line := secondLine, items := callItems, action := some " maybe False (const True) b ", constructor := none}]}
theorem unit_ref (grammar : Grammar) (ind fuel : Nat) (input : List Char)
    (line firstLine secondLine : Nat)
    (found : grammar.rules.find? (fun rule => rule.name == "BlockCommand") = some (layout line firstLine secondLine)) :
    recognizeEnv grammar [("ind",ind)] (fuel+1) (.ref "BlockCommand" ["ind"]) input =
      recognizeEnv grammar [("ind",ind)] fuel (.choice [setItems,callItems]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]

theorem generated (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+2) (.ref "BlockCommand" ["ind"]) input =
      foldChoice (fun xs => UnboundSequenceTotal.follow (fun item rest => recognizeEnv Generated.pegGrammar [("ind",ind)] fuel item rest) xs input) [setItems,callItems] := by
  rw [unit_ref _ _ _ _ sourceRule.line (sourceRule.alts[0]?.map (·.line) |>.getD 0) (sourceRule.alts[1]?.map (·.line) |>.getD 0) (by rfl)]
  change runChoices (fun xs => runSequence (fun scope item rest => recognizeEnv Generated.pegGrammar scope fuel item rest)
    _ [("ind",ind)] xs input) [setItems,callItems] = _
  simp only [runChoices, foldChoice, List.foldlM]
  rw [InertCaptureSequenceTotal.sequence]
  · rw [InertCaptureSequenceTotal.sequence]
    intro item member scope before
    simp [callItems] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> rfl
  · intro item member scope before
    simp [setItems] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> rfl

#print axioms generated
end CommandRecognitionTotal
