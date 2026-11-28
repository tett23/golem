import Generated
namespace PosArgDelimited
open PegModel

def ruleItems (name : String) : Option (List (List Expr)) :=
  (Generated.pegGrammar.rules.find? (fun rule => rule.name == name)).map
    (fun rule => rule.alts.map (·.items))

theorem eq_items : ruleItems "Eq" = some [[.lit "=" "'='"]] := by rfl
theorem splat_items : ruleItems "Splat" =
    some [[.lit "**[" "'**['"], [.lit "*[" "'*['"]] := by rfl
end PosArgDelimited
