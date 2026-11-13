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

theorem follow_suffix (read : String → List Char → ParseResult)
    (child : ∀ name input rest, read name input = .ok (some rest) →
      ∃ consumed, input = consumed ++ rest)
    (names : List String) (input rest : List Char)
    (parsed : follow read names input = .ok (some rest)) :
    ∃ consumed, input = consumed ++ rest := by
  induction names generalizing input with
  | nil =>
      simp [follow] at parsed
      exact ⟨[], by simpa using parsed⟩
  | cons name names ih =>
      cases result : read name input with
      | error reason => simp [follow, result] at parsed
      | ok val =>
          cases val with
          | none => simp [follow, result] at parsed
          | some next =>
              obtain ⟨first, first_eq⟩ := child name input next result
              obtain ⟨later, later_eq⟩ := ih next (by simpa [follow, result] using parsed)
              exact ⟨first ++ later, by rw [first_eq, later_eq, List.append_assoc]⟩

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

private def closedItems (opening : String) : List Expr :=
  [.ref opening [], .ref "ExprBody" [], .label (.choice [[.ref "RBr" []]]) "close"]

private def after (result : ParseResult) (next : List Char → ParseResult) : ParseResult :=
  match result with
  | .error reason => .error reason
  | .ok none => .ok none
  | .ok (some rest) => next rest

private def closeBracket (input : List Char) : ParseResult :=
  match input with
  | ']' :: rest => .ok (some rest)
  | _ => .error "label: close"

private theorem closing_total (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [] (fuel + 7)
      (.label (.choice [[.ref "RBr" []]]) "close") input = closeBracket input := by
  have lit := PegModelTest.literal_total Generated.pegGrammar [] (fuel + 2) "]" "']'" input
  change (match recognizeEnv Generated.pegGrammar [] (fuel + 6) (.choice [[.ref "RBr" []]]) input with
    | .ok none => Except.error "label: close"
    | result => result) = _
  have eq : recognizeEnv Generated.pegGrammar [] (fuel + 6) (.choice [[.ref "RBr" []]]) input =
      (if "]".toList.isPrefixOf input then .ok (some (input.drop 1)) else .ok none) := by
    change runChoices (fun items => runSequence (fun env e x => recognizeEnv Generated.pegGrammar env (fuel+5) e x) _ [] items input) [[.ref "RBr" []]] = _
    have child : recognizeEnv Generated.pegGrammar [] (fuel+5) (.ref "RBr" []) input =
        (if "]".toList.isPrefixOf input then .ok (some (input.drop 1)) else .ok none) := by
      change runChoices (fun items => runSequence (fun env e x => recognizeEnv Generated.pegGrammar env (fuel+3) e x) _ [] items input) [[.lit "]" "']'"]] = _
      cases hit : "]".toList.isPrefixOf input <;> simp [runChoices, foldChoice, runSequence, lit, hit] <;> rfl
    cases hit : "]".toList.isPrefixOf input <;> simp [runChoices, foldChoice, runSequence, child, hit] <;> rfl
  rw [eq]
  cases input with
  | nil => rfl
  | cons c rest =>
      by_cases h : c = ']'
      · subst c; simp [closeBracket, List.isPrefixOf]
      · have ne : (']' == c) = false := by
          cases b : (']' == c) with
          | false => rfl
          | true => exact False.elim (h (eq_of_beq b).symm)
        simp [closeBracket, h, List.isPrefixOf, ne]

theorem generated_closed (name opening : String)
    (rule : (name = "ExprCtx" ∧ opening = "ExprOpen") ∨ (name = "SplatArgument" ∧ opening = "Splat"))
    (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 9) (.ref name []) input =
      after (recognizeEnv Generated.pegGrammar [] (fuel + 7) (.ref opening []) input)
        (fun rest => after (recognizeEnv Generated.pegGrammar [] (fuel + 7) (.ref "ExprBody" []) rest) closeBracket) := by
  have outer : recognizeEnv Generated.pegGrammar env (fuel + 9) (.ref name []) input =
      recognizeEnv Generated.pegGrammar [] (fuel + 8) (.choice [closedItems opening]) input := by
    rcases rule with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> rfl
  rw [outer]
  change runChoices (fun items => runSequence (fun scope e x => recognizeEnv Generated.pegGrammar scope (fuel+7) e x) _ [] items input) [closedItems opening] = _
  cases first : recognizeEnv Generated.pegGrammar [] (fuel+7) (.ref opening []) input with
  | error reason => simp [closedItems, runChoices, foldChoice, runSequence, first, after]; rfl
  | ok value =>
      cases value with
      | none => simp [closedItems, runChoices, foldChoice, runSequence, first, after]; rfl
      | some rest =>
          cases body : recognizeEnv Generated.pegGrammar [] (fuel+7) (.ref "ExprBody" []) rest with
          | error reason => simp [closedItems, runChoices, foldChoice, runSequence, first, body, after]; rfl
          | ok val =>
              cases val with
              | none => simp [closedItems, runChoices, foldChoice, runSequence, first, body, after]; rfl
              | some endBody =>
                  cases closer : closeBracket endBody with
                  | error reason => simp [closedItems, runChoices, foldChoice, runSequence, first, body, after, closing_total, closer]; rfl
                  | ok tail =>
                      cases tail <;> simp [closedItems, runChoices, foldChoice, runSequence, first, body, after, closing_total, closer] <;> rfl

end ReferenceSequence
