import Generated
namespace PosArgTrace
open PegModel

def sourceRule : Rule :=
  (Generated.pegGrammar.rules.find? (fun rule => rule.name == "PosArg")).getD default
def noComment : Expr := .notPred (.lit "%%" "'%%'")
def noKeyword : Expr := .notPred (.choice [[.ref "Word" [], .ref "Eq" []]])
def noDoubleSplat : Expr := .notPred (.lit "**[" "'**['")
def noSplat : Expr := .notPred (.ref "Splat" [])
def branches : List (List Expr) :=
  [[noComment,noKeyword,noDoubleSplat,.ref "SplatArgument" []],
   [noComment,noKeyword,noSplat,.ref "Argument" []]]
def layout (source : Rule) : Rule :=
  {name := "PosArg",line := source.line,params := [],templateParams := [],resultType := "()",
   alts := ([0,1] : List Nat).map fun index =>
     {line := (source.alts[index]?.map (·.line)).getD 0,items := (branches[index]?).getD [],
      action := source.alts[index]?.bind (·.action),constructor := none}}

theorem posarg_found : Generated.pegGrammar.rules.find? (fun rule => rule.name == "PosArg") =
    some (layout sourceRule) := by rfl
theorem posarg_inline : Generated.pegGrammar.inline.contains "PosArg" = true := by decide
theorem posarg_not_token : Generated.pegGrammar.tokens.contains "PosArg" = false := by decide
end PosArgTrace
