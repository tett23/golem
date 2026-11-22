import RuleRepetition
import ThrowingPrefixTotal

namespace ExpressionComposition

open PegModel PegModelTest

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

private def callNamespace := Expr.choice [[.ref "ES" [], .ref "Dot" [], .ref "ES" [], .ref "ExprIdent" []]]

/-- Calls preserve the single optional namespace and the complete argument
    group. The collection proof covers arbitrary repetitions and error propagation;
    no action value, AST equality or formatter result is assumed. -/
theorem I1_I2_generated_call (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 4) (.ref "CallExpr" []) input =
      next (recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "ExprIdent" []) input) (fun rest0 =>
        next (recognizeEnv Generated.pegGrammar [] (fuel + 2) (.opt callNamespace) rest0) (fun rest1 =>
        next (recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "ES" []) rest1) (fun rest2 =>
        next (recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "LParen" []) rest2) (fun rest3 =>
        next (recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "ES" []) rest3) (fun rest4 =>
        next (RuleRepetition.readEntries "Expr" fuel rest4) (fun rest5 =>
        recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "RParen" []) rest5)))))) := by
  change recognizeEnv _ [] (fuel + 3) (.choice [[.ref "ExprIdent" [], .opt callNamespace, .ref "ES" [], .ref "LParen" [], .ref "ES" [], RuleRepetition.entries "Expr", .ref "RParen" []]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 2) item rest) _ [] xs input) [[.ref "ExprIdent" [], .opt callNamespace, .ref "ES" [], .ref "LParen" [], .ref "ES" [], RuleRepetition.entries "Expr", .ref "RParen" []]] = _
  have arguments := RuleRepetition.entries_eq "Expr" fuel
  simp only [RuleRepetition.entries] at arguments ⊢
  cases read0 : recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "ExprIdent" []) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, arguments, read0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, arguments, read0]; rfl
    | some rest0 =>
      cases read1 : recognizeEnv Generated.pegGrammar [] (fuel + 2) (.opt callNamespace) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1]; rfl
        | some rest1 =>
          cases read2 : recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "ES" []) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1, read2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1, read2]; rfl
            | some rest2 =>
              cases read3 : recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "LParen" []) rest2 with
              | error reason => simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1, read2, read3]; rfl
              | ok value => cases value with
                | none => simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1, read2, read3]; rfl
                | some rest3 =>
                  cases read4 : recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "ES" []) rest3 with
                  | error reason => simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1, read2, read3, read4]; rfl
                  | ok value => cases value with
                    | none => simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1, read2, read3, read4]; rfl
                    | some rest4 =>
                      cases read5 : RuleRepetition.readEntries "Expr" fuel rest4 with
                      | error reason => simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1, read2, read3, read4, read5]; rfl
                      | ok value => cases value with
                        | none => simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1, read2, read3, read4, read5]; rfl
                        | some rest5 =>
                          cases read6 : recognizeEnv Generated.pegGrammar [] (fuel + 2) (.ref "RParen" []) rest5 with
                          | error reason => simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1, read2, read3, read4, read5, read6]; rfl
                          | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, arguments, read0, read1, read2, read3, read4, read5, read6] <;> rfl

/-- PEG chooses the first success or error; only an ordinary miss permits
    a later alternative. Unselected errors cannot replace an earlier success. -/
def choose : List ParseResult → ParseResult
  | [] => .ok none
  | Except.ok none :: rest => choose rest
  | result :: _ => result

theorem choices_eq {α : Type} (parse : α → ParseResult) (alts : List α) :
    foldChoice parse alts = choose (alts.map parse) := by
  induction alts with
  | nil => rfl
  | cons a alts ih =>
    simp only [foldChoice, List.foldlM, List.map]
    cases result : parse a with
    | error reason => simp [result, choose, Bind.bind, Except.bind]
    | ok value => cases value with
      | none => simpa only [result, choose, Bind.bind, Except.bind, pure, Except.pure] using ih
      | some rest =>
        simp only [result, choose, Bind.bind, Except.bind, pure, Except.pure]
        clear ih
        induction alts with
        | nil => rfl
        | cons item tail ih => simpa only [List.foldlM] using ih

private theorem one_choice (sequence : List Expr → ParseResult) (items : List Expr) :
    runChoices sequence [items] = sequence items := by
  cases result : sequence items with
  | error reason => simp [runChoices, foldChoice, List.foldlM, result]
  | ok value => simp [runChoices, foldChoice, List.foldlM, result]

private theorem regroup (grammar : Grammar) (env : Params) (fuel : Nat)
    (alts : List (List Expr)) (input : List Char) :
    recognizeEnv grammar env (fuel + 1) (.choice alts) input =
      runChoices (fun items => recognizeEnv grammar env (fuel + 1) (.choice [items]) input) alts := by
  conv => rhs; arg 1; ext items; unfold recognizeEnv; simp only [one_choice]

private def missingRange : List Expr :=
  [.andPred (.lit "..." "'...'"),
    .label (.choice [[.semanticPred true " False ", .lit "..." "'...'"]]) "range_end"]
private def requiredEnd := Expr.label (.choice [[.ref "AddExpr" []]]) "range_end"
private def rangeTailGuard := Expr.label (.choice [[.notPred (.choice [[.ref "ES" [], .lit ".." "'..'"]])]]) "range_end"
private def closedRange : List Expr :=
  [.ref "AddExpr" [], .ref "ES" [], .ref "RangeOp" [], .ref "ES" [], requiredEnd, rangeTailGuard]
private def rangeBranches : List (List Expr) :=
  [missingRange, [.ref "ReservedRange" []], [.ref "AddExpr" [], .ref "ES" [], .ref "ReservedRange" []],
    closedRange, [.ref "CompareExpr" []]]

/-- The actual ordered alternatives of the canonical rule. Each branch is
    interpreted at the same fuel; the singleton group adds no choice fallback. -/
theorem I1_I2_generated_range (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "RangeExpr" []) input =
      choose (rangeBranches.map (fun items =>
        recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice [items]) input)) := by
  change recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice rangeBranches) input = _
  rw [regroup]
  exact choices_eq _ _

/-- Missing the left endpoint reports range_end for every suffix beginning
    with ..., independently of the unused alternatives. -/
theorem I1_I2_missing_range (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (extra + 6) (.choice [missingRange]) input =
      if "...".toList.isPrefixOf input then .error "label: range_end" else .ok none := by
  exact ThrowingPrefixTotal.throwing_prefix_choice Generated.pegGrammar [] extra "..." "'...'" "range_end" input

private def readClosed (fuel : Nat) (input : List Char) : ParseResult :=
  next (recognizeEnv Generated.pegGrammar [] fuel (.ref "AddExpr" []) input) (fun rest0 =>
        next (recognizeEnv Generated.pegGrammar [] fuel (.ref "ES" []) rest0) (fun rest1 =>
        next (recognizeEnv Generated.pegGrammar [] fuel (.ref "RangeOp" []) rest1) (fun rest2 =>
        next (recognizeEnv Generated.pegGrammar [] fuel (.ref "ES" []) rest2) (fun rest3 =>
        next (recognizeEnv Generated.pegGrammar [] fuel (.label (.choice [[.ref "AddExpr" []]]) "range_end") rest3) (fun rest4 =>
        recognizeEnv Generated.pegGrammar [] fuel (.label (.choice [[.notPred (.choice [[.ref "ES" [], .lit ".." "'..'"]])]]) "range_end") rest4)))))

/-- Both required-end labels retain the original successful suffix or error;
    no endpoint or trailing-range failure is converted into an ordinary miss. -/
theorem I1_I2_closed_range (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [] (fuel + 1) (.choice [closedRange]) input =
      readClosed fuel input := by
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    fuel item rest) _ [] xs input) [closedRange] = _
  dsimp only [readClosed]
  simp only [closedRange, requiredEnd, rangeTailGuard]
  cases read0 : recognizeEnv Generated.pegGrammar [] fuel (.ref "AddExpr" []) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0]; rfl
    | some rest0 =>
      cases read1 : recognizeEnv Generated.pegGrammar [] fuel (.ref "ES" []) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0, read1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0, read1]; rfl
        | some rest1 =>
          cases read2 : recognizeEnv Generated.pegGrammar [] fuel (.ref "RangeOp" []) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0, read1, read2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0, read1, read2]; rfl
            | some rest2 =>
              cases read3 : recognizeEnv Generated.pegGrammar [] fuel (.ref "ES" []) rest2 with
              | error reason => simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0, read1, read2, read3]; rfl
              | ok value => cases value with
                | none => simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0, read1, read2, read3]; rfl
                | some rest3 =>
                  cases read4 : recognizeEnv Generated.pegGrammar [] fuel (.label (.choice [[.ref "AddExpr" []]]) "range_end") rest3 with
                  | error reason => simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0, read1, read2, read3, read4]; rfl
                  | ok value => cases value with
                    | none => simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0, read1, read2, read3, read4]; rfl
                    | some rest4 =>
                      cases read5 : recognizeEnv Generated.pegGrammar [] fuel (.label (.choice [[.notPred (.choice [[.ref "ES" [], .lit ".." "'..'"]])]]) "range_end") rest4 with
                      | error reason => simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0, read1, read2, read3, read4, read5]; rfl
                      | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, requiredEnd, rangeTailGuard, read0, read1, read2, read3, read4, read5] <;> rfl

/-- The five choices retain their order while the closed branch is expanded
    into the explicitly labelled endpoint and tail checks. -/
theorem I1_I2_generated_range_refined (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "RangeExpr" []) input =
      choose [recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice [missingRange]) input,
        recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice [[.ref "ReservedRange" []]]) input,
        recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice [[.ref "AddExpr" [], .ref "ES" [], .ref "ReservedRange" []]]) input,
        readClosed (fuel + 1) input,
        recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice [[.ref "CompareExpr" []]]) input] := by
  rw [I1_I2_generated_range]
  simp only [rangeBranches, List.map]
  rw [show fuel + 2 = (fuel + 1) + 1 by omega, I1_I2_closed_range]

end ExpressionComposition
