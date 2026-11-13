import PegModelTest

namespace ReferenceSequence

open PegModel

def expressions (names : List String) : List Expr := names.map (fun name => .ref name [])

def follow (read : String → List Char → ParseResult) : List String → List Char → ParseResult
  | [], input => .ok (some input)
  | name :: names, input =>
      match read name input with
      | .error reason => .error reason
      | .ok none => .ok none
      | .ok (some rest) => follow read names rest

private theorem folded (parse : Params → Expr → List Char → ParseResult)
    (boundLength : Params → Expr → List Char → Except String (Option Nat))
    (env : Params) (names : List String) (state : Option (List Char × Params))
    (fixed : ∀ rest scope, state = some (rest, scope) → scope = env) :
    ((expressions names).foldlM (fun state item =>
    match state with
    | none => pure none
    | some (rest, scope) => do
        match parse scope item rest with
        | .error reason => Except.error reason
        | .ok none => pure none
        | .ok (some next) =>
            match item with
            | .bind (some name) _ =>
                match boundLength scope item rest with
                | .error reason => Except.error reason
                | .ok none => pure (some (next, scope))
                | .ok (some value) => pure (some (next, (name, value) :: scope))
            | _ => pure (some (next, scope))) state :
      Except String (Option (List Char × Params))).map (Option.map Prod.fst) =
      match state with
      | none => .ok none
      | some (rest, _) => follow (fun name => parse env (.ref name [])) names rest := by
  induction names generalizing state with
  | nil => cases state <;> rfl
  | cons name names ih =>
      cases state with
      | none => exact ih none (by simp)
      | some pair =>
          rcases pair with ⟨rest, scope⟩
          have same := fixed rest scope rfl
          subst scope
          simp only [expressions, List.map, List.foldlM, follow]
          cases read : parse env (.ref name []) rest with
          | error reason => rfl
          | ok val =>
              cases val with
              | none => exact ih none (by simp)
              | some next => exact ih (some (next, env)) (by simp_all)

theorem sequence (parse : Params → Expr → List Char → ParseResult)
    (boundLength : Params → Expr → List Char → Except String (Option Nat))
    (env : Params) (names : List String) (input : List Char) :
    runSequence parse boundLength env (expressions names) input =
      follow (fun name => parse env (.ref name [])) names input := by
  exact folded parse boundLength env names (some (input, env)) (by simp_all)

private def alternative (name : String) (idx : Nat) : Option (List Expr) := do
  let rule ← Generated.pegGrammar.rules.find? (fun r => r.name == name)
  let alt ← rule.alts[idx]?
  pure alt.items

private def chains : List (String × Nat × List String) :=
  [("KwArg", 0, ["KeywordArgument"]),
   ("KeywordArgument", 0, ["Word", "Eq", "ArgValue"]),
   ("RangeExpr", 1, ["ReservedRange"]), ("RangeExpr", 2, ["AddExpr", "ES", "ReservedRange"]),
   ("RangeExpr", 4, ["CompareExpr"]),
   ("CompareExpr", 0, ["AddExpr", "ES", "CmpOp", "ES", "AddExpr"]), ("CompareExpr", 1, ["AddExpr"]),
   ("AddExpr", 1, ["MulExpr"]), ("MulExpr", 1, ["UnaryExpr"]),
   ("UnaryExpr", 0, ["NegOp", "ES", "UnaryExpr"]), ("UnaryExpr", 1, ["PowExpr"]),
   ("PowExpr", 0, ["PostfixExpr", "ES", "PowOp", "ES", "UnaryExpr"]), ("PowExpr", 1, ["PostfixExpr"]),
   ("ParenExpr", 0, ["LParen", "ES", "Expr", "ES", "RParen"]),
   ("BlockStart", 6, ["SetDeclarationStart"])]

theorem generated_chains :
    chains.map (fun (name, idx, _) => alternative name idx) =
      chains.map (fun (_, _, names) => some (expressions names)) := by rfl

end ReferenceSequence
