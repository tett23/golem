import PlusComposition

namespace BlockRemainderTotal
open PegModel

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

private def metadata (name : String) : Nat × Option String :=
  match Generated.pegGrammar.rules.find? (fun rule => rule.name == name) with
  | none => (0, none)
  | some rule => (rule.line, rule.alts.head?.bind (·.action))

def lineEnd : Expr := .choice [[.ref "Nl" []], [.notPred .any]]

def closing : Expr :=
  .opt (.choice [[.opt (.ref "BlankLines" []), .ref "Ind" ["ind"], .ref "DivMark" [],
    .ref "Sp" [], lineEnd]])

private def list_itemRule (line : Nat) (action : Option String) : Rule :=
  { name := "ListItem", line := line, params := ["ind", "ordered"], templateParams := [], resultType := "()",
    alts := [{ line := line, items := [.ref "Ind" ["ind"], .ref "ListMark" ["ordered"], .ref "Ws" [], .plus (.ref "Inline" ["col ind + 2"]), lineEnd, .ref "ItemTail" ["col ind + 2"]], action := action, constructor := none }] }

theorem list_item_ref (grammar : Grammar) (ind ordered fuel : Nat) (input : List Char)
    (line : Nat) (action : Option String)
    (found : grammar.rules.find? (fun rule => rule.name == "ListItem") = some (list_itemRule line action)) :
    recognizeEnv grammar [("ind", ind), ("ordered", ordered)] (fuel + 1) (.ref "ListItem" ["ind", "ordered"]) input =
      recognizeEnv grammar [("ind", ind), ("ordered", ordered)] fuel (.choice [[.ref "Ind" ["ind"], .ref "ListMark" ["ordered"], .ref "Ws" [], .plus (.ref "Inline" ["col ind + 2"]), lineEnd, .ref "ItemTail" ["col ind + 2"]]]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]

theorem generated_list_item (ind ordered fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (fuel + 3) (.ref "ListItem" ["ind", "ordered"]) input =
      next (recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (fuel + 1) (.ref "Ind" ["ind"]) input) (fun rest0 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (fuel + 1) (.ref "ListMark" ["ordered"]) rest0) (fun rest1 =>
          next (recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (fuel + 1) (.ref "Ws" []) rest1) (fun rest2 =>
            next (PlusComposition.scanPlus (fun n => recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] n
          (.ref "Inline" ["col ind + 2"])) fuel rest2) (fun rest3 =>
              next (recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (fuel + 1) (.choice [[.ref "Nl" []], [.notPred .any]]) rest3) (fun rest4 =>
                recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (fuel + 1) (.ref "ItemTail" ["col ind + 2"]) rest4))))) := by
  rw [list_item_ref _ _ _ _ _ (metadata "ListItem").1 (metadata "ListItem").2 (by rfl)]
  change runChoices (fun xs => runSequence
    (fun scope item rest => recognizeEnv Generated.pegGrammar scope (fuel + 1) item rest)
    _ [("ind", ind), ("ordered", ordered)] xs input)
    [[.ref "Ind" ["ind"], .ref "ListMark" ["ordered"], .ref "Ws" [], .plus (.ref "Inline" ["col ind + 2"]), lineEnd, .ref "ItemTail" ["col ind + 2"]]] = _
  unfold lineEnd
  have repeated := PlusComposition.plus Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (.ref "Inline" ["col ind + 2"]) fuel
  cases r0 : recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (fuel + 1) (.ref "Ind" ["ind"]) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, r0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, repeated, r0]; rfl
    | some rest0 =>
      cases r1 : recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (fuel + 1) (.ref "ListMark" ["ordered"]) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, r0, r1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, repeated, r0, r1]; rfl
        | some rest1 =>
          cases r2 : recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (fuel + 1) (.ref "Ws" []) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, r0, r1, r2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, repeated, r0, r1, r2]; rfl
            | some rest2 =>
              cases r3 : PlusComposition.scanPlus (fun n => recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] n
          (.ref "Inline" ["col ind + 2"])) fuel rest2 with
              | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, r0, r1, r2, r3]; rfl
              | ok value => cases value with
                | none => simp [runChoices, foldChoice, runSequence, next, repeated, r0, r1, r2, r3]; rfl
                | some rest3 =>
                  cases r4 : recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (fuel + 1) (.choice [[.ref "Nl" []], [.notPred .any]]) rest3 with
                  | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, r0, r1, r2, r3, r4]; rfl
                  | ok value => cases value with
                    | none => simp [runChoices, foldChoice, runSequence, next, repeated, r0, r1, r2, r3, r4]; rfl
                    | some rest4 =>
                      cases r5 : recognizeEnv Generated.pegGrammar [("ind", ind), ("ordered", ordered)] (fuel + 1) (.ref "ItemTail" ["col ind + 2"]) rest4 with
                      | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, r0, r1, r2, r3, r4, r5]; rfl
                      | ok value => cases value with
                        | none => simp [runChoices, foldChoice, runSequence, next, repeated, r0, r1, r2, r3, r4, r5]; rfl
                        | some rest5 => simp [runChoices, foldChoice, runSequence, next, repeated, r0, r1, r2, r3, r4, r5]; rfl

private def divRule (line : Nat) (action : Option String) : Rule :=
  { name := "Div", line := line, params := ["ind"], templateParams := [], resultType := "()",
    alts := [{ line := line, items := [.ref "Ind" ["ind"], .ref "DivMark" [], .ref "Sp" [], lineEnd, .ref "DivBlocks" ["fenced ind"], closing], action := action, constructor := none }] }

theorem div_ref (grammar : Grammar) (ind fuel : Nat) (input : List Char)
    (line : Nat) (action : Option String)
    (found : grammar.rules.find? (fun rule => rule.name == "Div") = some (divRule line action)) :
    recognizeEnv grammar [("ind", ind)] (fuel + 1) (.ref "Div" ["ind"]) input =
      recognizeEnv grammar [("ind", ind)] fuel (.choice [[.ref "Ind" ["ind"], .ref "DivMark" [], .ref "Sp" [], lineEnd, .ref "DivBlocks" ["fenced ind"], closing]]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]

theorem generated_div (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 3) (.ref "Div" ["ind"]) input =
      next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ind" ["ind"]) input) (fun rest0 =>
        next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "DivMark" []) rest0) (fun rest1 =>
          next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Sp" []) rest1) (fun rest2 =>
            next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.choice [[.ref "Nl" []], [.notPred .any]]) rest2) (fun rest3 =>
              next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "DivBlocks" ["fenced ind"]) rest3) (fun rest4 =>
                recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.opt (.choice [[.opt (.ref "BlankLines" []), .ref "Ind" ["ind"], .ref "DivMark" [], .ref "Sp" [], .choice [[.ref "Nl" []], [.notPred .any]]]])) rest4))))) := by
  rw [div_ref _ _ _ _ (metadata "Div").1 (metadata "Div").2 (by rfl)]
  change runChoices (fun xs => runSequence
    (fun scope item rest => recognizeEnv Generated.pegGrammar scope (fuel + 1) item rest)
    _ [("ind", ind)] xs input)
    [[.ref "Ind" ["ind"], .ref "DivMark" [], .ref "Sp" [], lineEnd, .ref "DivBlocks" ["fenced ind"], closing]] = _
  unfold closing lineEnd
  cases r0 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Ind" ["ind"]) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, r0]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, r0]; rfl
    | some rest0 =>
      cases r1 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "DivMark" []) rest0 with
      | error reason => simp [runChoices, foldChoice, runSequence, next, r0, r1]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, r0, r1]; rfl
        | some rest1 =>
          cases r2 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "Sp" []) rest1 with
          | error reason => simp [runChoices, foldChoice, runSequence, next, r0, r1, r2]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, r0, r1, r2]; rfl
            | some rest2 =>
              cases r3 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.choice [[.ref "Nl" []], [.notPred .any]]) rest2 with
              | error reason => simp [runChoices, foldChoice, runSequence, next, r0, r1, r2, r3]; rfl
              | ok value => cases value with
                | none => simp [runChoices, foldChoice, runSequence, next, r0, r1, r2, r3]; rfl
                | some rest3 =>
                  cases r4 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.ref "DivBlocks" ["fenced ind"]) rest3 with
                  | error reason => simp [runChoices, foldChoice, runSequence, next, r0, r1, r2, r3, r4]; rfl
                  | ok value => cases value with
                    | none => simp [runChoices, foldChoice, runSequence, next, r0, r1, r2, r3, r4]; rfl
                    | some rest4 =>
                      cases r5 : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1) (.opt (.choice [[.opt (.ref "BlankLines" []), .ref "Ind" ["ind"], .ref "DivMark" [], .ref "Sp" [], .choice [[.ref "Nl" []], [.notPred .any]]]])) rest4 with
                      | error reason => simp [runChoices, foldChoice, runSequence, next, r0, r1, r2, r3, r4, r5]; rfl
                      | ok value => cases value with
                        | none => simp [runChoices, foldChoice, runSequence, next, r0, r1, r2, r3, r4, r5]; rfl
                        | some rest5 => simp [runChoices, foldChoice, runSequence, next, r0, r1, r2, r3, r4, r5]; rfl

#print axioms generated_list_item
#print axioms generated_div
end BlockRemainderTotal
