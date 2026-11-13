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

private theorem pipe_total (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar [] (fuel + 3) (.ref "Pipe" []) input =
      (if "|".toList.isPrefixOf input then .ok (some (input.drop 1)) else .ok none) := by
  change runChoices (fun items => runSequence (fun env e x => recognizeEnv Generated.pegGrammar env (fuel+1) e x) _ [] items input) [[.lit "|" "'|'"]] = _
  have lit := PegModelTest.literal_total Generated.pegGrammar [] fuel "|" "'|'" input
  cases hit : "|".toList.isPrefixOf input <;> simp [runChoices, foldChoice, runSequence, lit, hit] <;> rfl

private theorem pipe_ahead (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar [] (fuel + 5) (.andPred (.choice [[.ref "Pipe" []]])) input =
      (if "|".toList.isPrefixOf input then .ok (some input) else .ok none) := by
  change (match recognizeEnv Generated.pegGrammar [] (fuel + 4) (.choice [[.ref "Pipe" []]]) input with
    | .error reason => if isLabelFailure reason then Except.ok none else Except.error reason
    | .ok none => Except.ok none
    | .ok (some _) => Except.ok (some input)) = _
  rw [PegModelTest.single_group _ _ _ _ _ (by simp), pipe_total]
  cases "|".toList.isPrefixOf input <;> rfl

theorem generated_table_cell_and_pipe (env : Params) (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar env (fuel + 7) (.ref "TableCellAndPipe" []) input =
      if "|".toList.isPrefixOf input then
        after (recognizeEnv Generated.pegGrammar [] (fuel+5) (.ref "TableCell" []) (input.drop 1))
          (fun rest => if "|".toList.isPrefixOf rest then .ok (some rest) else .ok none)
      else .ok none := by
  change runChoices (fun items => runSequence (fun scope e x => recognizeEnv Generated.pegGrammar scope (fuel+5) e x) _ [] items input)
    [[.ref "Pipe" [], .ref "TableCell" [], .andPred (.choice [[.ref "Pipe" []]])]] = _
  have opening := pipe_total input (fuel+2)
  cases hit : "|".toList.isPrefixOf input with
  | false => simp [runChoices, foldChoice, runSequence, opening, hit]; rfl
  | true =>
      cases cell : recognizeEnv Generated.pegGrammar [] (fuel+5) (.ref "TableCell" []) (input.drop 1) with
      | error reason => simp [runChoices, foldChoice, runSequence, opening, hit, cell, after]; rfl
      | ok value =>
          cases value with
          | none => simp [runChoices, foldChoice, runSequence, opening, hit, cell, after]; rfl
          | some rest =>
              cases tail : "|".toList.isPrefixOf rest <;>
                simp [runChoices, foldChoice, runSequence, opening, hit, cell, after, pipe_ahead, tail] <;> rfl

private def requireExpr (result : ParseResult) : ParseResult :=
  match result with
  | .ok none => .error "label: expr"
  | other => other

private theorem required_expr (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [] (fuel+2) (.label (.choice [[.ref "Expr" []]]) "expr") input =
      requireExpr (recognizeEnv Generated.pegGrammar [] fuel (.ref "Expr" []) input) := by
  change (match recognizeEnv Generated.pegGrammar [] (fuel+1) (.choice [[.ref "Expr" []]]) input with
    | .ok none => Except.error "label: expr"
    | result => result) = _
  rw [PegModelTest.single_group _ _ _ _ _ (by simp)]
  rfl

theorem generated_expr_body (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel+4) (.ref "ExprBody" []) input =
      after (recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "ES" []) input)
        (fun rest => after (requireExpr (recognizeEnv Generated.pegGrammar [] fuel (.ref "Expr" []) rest))
          (recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "ES" []))) := by
  change runChoices (fun items => runSequence (fun scope e x => recognizeEnv Generated.pegGrammar scope (fuel+2) e x) _ [] items input)
    [[.ref "ES" [], .label (.choice [[.ref "Expr" []]]) "expr", .ref "ES" []]] = _
  cases first : recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "ES" []) input with
  | error reason => simp [runChoices, foldChoice, runSequence, first, after]; rfl
  | ok value =>
      cases value with
      | none => simp [runChoices, foldChoice, runSequence, first, after]; rfl
      | some rest =>
          cases body : requireExpr (recognizeEnv Generated.pegGrammar [] fuel (.ref "Expr" []) rest) with
          | error reason => simp [runChoices, foldChoice, runSequence, first, after, required_expr, body]; rfl
          | ok val =>
              cases val with
              | none => simp [runChoices, foldChoice, runSequence, first, after, required_expr, body]; rfl
              | some endBody =>
                  cases last : recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "ES" []) endBody with
                  | error reason => simp [runChoices, foldChoice, runSequence, first, after, required_expr, body, last]; rfl
                  | ok tail => cases tail <;> simp [runChoices, foldChoice, runSequence, first, after, required_expr, body, last] <;> rfl

private theorem splat_ahead (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [] (fuel+2) (.andPred (.lit "**[" "'**['")) input =
      .ok (if "**[".toList.isPrefixOf input then some input else none) := by
  change (match recognizeEnv Generated.pegGrammar [] (fuel+1) (.lit "**[" "'**['") input with
    | .error reason => if isLabelFailure reason then Except.ok none else Except.error reason
    | .ok none => Except.ok none
    | .ok (some _) => Except.ok (some input)) = _
  rw [PegModelTest.literal_total]
  cases "**[".toList.isPrefixOf input <;> rfl

theorem generated_kwarg (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel+4) (.ref "KwArg" []) input =
      match recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "KeywordArgument" []) input with
      | .ok none => if "**[".toList.isPrefixOf input then
          recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "SplatArgument" []) input else .ok none
      | result => result := by
  change runChoices (fun items => runSequence (fun scope e x => recognizeEnv Generated.pegGrammar scope (fuel+2) e x) _ [] items input)
    [[.ref "KeywordArgument" []], [.andPred (.lit "**[" "'**['"), .ref "SplatArgument" []]] = _
  cases first : recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "KeywordArgument" []) input with
  | error reason => simp [runChoices, foldChoice, runSequence, first]; rfl
  | ok val =>
      cases val with
      | some rest => simp [runChoices, foldChoice, runSequence, first]; rfl
      | none =>
          cases guardHit : "**[".toList.isPrefixOf input with
          | false => simp [runChoices, foldChoice, runSequence, first, splat_ahead, guardHit]; rfl
          | true =>
              cases splat : recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "SplatArgument" []) input with
              | error reason => simp [runChoices, foldChoice, runSequence, first, splat_ahead, guardHit, splat]; rfl
              | ok tail => cases tail <;> simp [runChoices, foldChoice, runSequence, first, splat_ahead, guardHit, splat] <;> rfl

end ReferenceSequence
