import Generated
namespace ArgumentTrace
open PegModel

def sourceRule : Rule :=
  (Generated.pegGrammar.rules.find? (fun rule => rule.name == "Argument")).getD default
def layout (source : Rule) : Rule :=
  {name := "Argument",line := source.line,params := [],templateParams := [],resultType := "()",
    alts := [{line := (source.alts[0]?.map (·.line)).getD 0,items := [.ref "ArgValue" []],action := source.alts[0]?.bind (·.action),constructor := none}]}

theorem argument_found :
    Generated.pegGrammar.rules.find? (fun rule => rule.name == "Argument") =
      some (layout sourceRule) := by rfl
theorem argument_not_inline : Generated.pegGrammar.inline.contains "Argument" = false := by decide
theorem argument_not_token : Generated.pegGrammar.tokens.contains "Argument" = false := by decide
end ArgumentTrace
