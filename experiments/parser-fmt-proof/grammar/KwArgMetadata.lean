import Generated
namespace KwArgTrace
open PegModel
def fallback : List (List Expr) :=
  ((Generated.pegGrammar.rules.find? (fun rule => rule.name == "KwArg")).map
    (fun rule => (rule.alts.map (·.items)).drop 1)).getD []

theorem kwarg_found :
    ((Generated.pegGrammar.rules.find? (fun rule => rule.name == "KwArg")).map
      (fun rule => (rule.params,rule.templateParams,rule.alts.map (·.items)))) =
      some ([],[],[.ref "KeywordArgument" []]::fallback) := by rfl

theorem kwarg_inline : Generated.pegGrammar.inline.contains "KwArg" = true := by decide

end KwArgTrace
