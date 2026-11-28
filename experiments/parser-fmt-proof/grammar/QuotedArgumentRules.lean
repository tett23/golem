import Generated
namespace QuotedArgumentRules
open PegModel

def keywordItems : List Expr := [.ref "Word" [],.ref "Eq" [],.ref "ArgValue" []]
def valueItems : List (List Expr) := [[.ref "StringLit" []],[.ref "ExprCtx" []],
  [.ref "ReservedBracket" []],[.ref "InlineCommand" ["0"]],[.ref "Word" []]]
def stringItems : List Expr := [.lit "\"" "'\"'",.star (.choice [
  [.lit "\\" "'\\\\'",.any],[.notPred (.charClass [(34,34),(10,10)] "[\"\\n]"),.any]]),.lit "\"" "'\"'"]

def sourceRule (name : String) : Rule :=
  (Generated.pegGrammar.rules.find? (fun rule => rule.name == name)).getD default
private def alt (source : Rule) (index : Nat) (items : List Expr) : Alt :=
  {line := (source.alts[index]?.map (·.line)).getD 0,items := items,
    action := source.alts[index]?.bind (·.action),constructor := none}
def keywordLayout (source : Rule) : Rule :=
  {name := "KeywordArgument",line := source.line,params := [],templateParams := [],resultType := "()",
    alts := [alt source 0 keywordItems]}
def valueLayout (source : Rule) : Rule :=
  {name := "ArgValue",line := source.line,params := [],templateParams := [],resultType := "()",
    alts := [alt source 0 valueItems[0]!,alt source 1 valueItems[1]!,alt source 2 valueItems[2]!,
      alt source 3 valueItems[3]!,alt source 4 valueItems[4]!]}
def stringLayout (source : Rule) : Rule :=
  {name := "StringLit",line := source.line,params := [],templateParams := [],resultType := "()",
    alts := [alt source 0 stringItems]}

theorem keyword_found :
  Generated.pegGrammar.rules.find? (fun rule => rule.name == "KeywordArgument") =
    some (keywordLayout (sourceRule "KeywordArgument")) := by rfl
theorem value_found :
  Generated.pegGrammar.rules.find? (fun rule => rule.name == "ArgValue") =
    some (valueLayout (sourceRule "ArgValue")) := by rfl
theorem string_found :
  Generated.pegGrammar.rules.find? (fun rule => rule.name == "StringLit") =
    some (stringLayout (sourceRule "StringLit")) := by rfl
theorem escaped_first : Generated.stringLitEscapeFirst = true := by rfl

theorem keyword_ref (grammar : Grammar) (fuel : Nat) (input : List Char) (source : Rule)
    (found : grammar.rules.find? (fun rule => rule.name == "KeywordArgument") = some (keywordLayout source)) :
    recognizeEnv grammar [] (fuel+1) (.ref "KeywordArgument" []) input =
      recognizeEnv grammar [] fuel (.choice [keywordItems]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]
theorem value_ref (grammar : Grammar) (fuel : Nat) (input : List Char) (source : Rule)
    (found : grammar.rules.find? (fun rule => rule.name == "ArgValue") = some (valueLayout source)) :
    recognizeEnv grammar [] (fuel+1) (.ref "ArgValue" []) input =
      recognizeEnv grammar [] fuel (.choice valueItems) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]
#print axioms keyword_ref
#print axioms value_ref
end QuotedArgumentRules
