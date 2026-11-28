import CapturedValueTotal
namespace TableCompositionTotal
open PegModel
def tableItems : List Expr := [.bind (some "h") (.ref "TableRow" ["ind"]), .ref "Nl" [], .label (.choice [[.ref "TableDelimiter" ["ind"]]]) "table_delimiter", .star (.ref "TableBodyRow" ["ind", "h"]), .label (.choice [[.notPred (.choice [[.ref "Nl" [], .ref "Ind" ["ind"], .ref "Pipe" []]])]]) "table_row", .choice [[.ref "Nl" []], [.notPred (.any)]]]
private def tableSource : Rule := (Generated.pegGrammar.rules.find? (fun rule => rule.name == "Table")).getD default
private def tableLayout (line : Nat) (action : Option String) : Rule :=
  {name := "Table", line := line, params := ["ind"], templateParams := [], resultType := "()", alts := [{line := line, items := tableItems, action := action, constructor := none}]}
theorem table_ref (grammar : Grammar) (ind fuel : Nat) (input : List Char) (line : Nat) (action : Option String)
    (found : grammar.rules.find? (fun rule => rule.name == "Table") = some (tableLayout line action)) :
    recognizeEnv grammar [("ind",ind)] (fuel+1) (.ref "Table" ["ind"]) input =
      recognizeEnv grammar [("ind",ind)] fuel (.choice [tableItems]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]
theorem generated_table (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+2) (.ref "Table" ["ind"]) input =
      CapturedSequenceTotal.follow (fun scope item rest => recognizeEnv Generated.pegGrammar scope fuel item rest)
        (CapturedValueTotal.value Generated.pegGrammar (fun scope item rest => recognizeEnv Generated.pegGrammar scope fuel item rest) fuel)
        [("ind",ind)] tableItems input := by
  rw [table_ref _ _ _ _ tableSource.line (tableSource.alts.head?.bind (·.action)) (by rfl)]
  change runChoices (fun xs => runSequence (fun scope item rest => recognizeEnv Generated.pegGrammar scope fuel item rest)
    _ [("ind",ind)] xs input) [tableItems] = _
  simp only [runChoices, foldChoice, List.foldlM, bind_pure]
  exact CapturedSequenceTotal.sequence _ _ _ _ _
#print axioms generated_table
def bodyItems : List Expr := [.ref "Nl" [], .bind (some "r") (.ref "TableRow" ["ind"]), .label (.choice [[.semanticPred true " r == h "]]) "table_cells"]
private def bodySource : Rule := (Generated.pegGrammar.rules.find? (fun rule => rule.name == "TableBodyRow")).getD default
private def bodyLayout (line : Nat) (action : Option String) : Rule :=
  {name := "TableBodyRow", line := line, params := ["ind","h"], templateParams := [], resultType := "()", alts := [{line := line, items := bodyItems, action := action, constructor := none}]}
theorem body_ref (grammar : Grammar) (ind h fuel : Nat) (input : List Char) (line : Nat) (action : Option String)
    (found : grammar.rules.find? (fun rule => rule.name == "TableBodyRow") = some (bodyLayout line action)) :
    recognizeEnv grammar [("ind",ind),("h",h)] (fuel+1) (.ref "TableBodyRow" ["ind","h"]) input =
      recognizeEnv grammar [("ind",ind),("h",h)] fuel (.choice [bodyItems]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]
theorem generated_body (ind h fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind",ind),("h",h)] (fuel+2) (.ref "TableBodyRow" ["ind","h"]) input =
      CapturedSequenceTotal.follow (fun scope item rest => recognizeEnv Generated.pegGrammar scope fuel item rest)
        (CapturedValueTotal.value Generated.pegGrammar (fun scope item rest => recognizeEnv Generated.pegGrammar scope fuel item rest) fuel)
        [("ind",ind),("h",h)] bodyItems input := by
  rw [body_ref _ _ _ _ _ bodySource.line (bodySource.alts.head?.bind (·.action)) (by rfl)]
  change runChoices (fun xs => runSequence (fun scope item rest => recognizeEnv Generated.pegGrammar scope fuel item rest)
    _ [("ind",ind),("h",h)] xs input) [bodyItems] = _
  simp only [runChoices, foldChoice, List.foldlM, bind_pure]
  exact CapturedSequenceTotal.sequence _ _ _ _ _
#print axioms generated_body
end TableCompositionTotal
