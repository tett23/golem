import PegModelTest

namespace RuleRepetition

open PegModel

/-- A repetition consults the item at each suffix using the same remaining
    fuel as the PEG interpreter. Stop on an ordinary miss; propagate errors. -/
def scan (read : Nat → List Char → ParseResult) : Nat → List Char → ParseResult
  | 0, _ => .error "fuel exhausted"
  | fuel + 1, input =>
      match read fuel input with
      | .error reason => .error reason
      | .ok none => .ok (some input)
      | .ok (some rest) => if rest.length < input.length then scan read fuel rest
                            else .error "zero-width repetition"

theorem star (grammar : Grammar) (env : Params) (item : Expr) (fuel : Nat) (input : List Char) :
    recognizeEnv grammar env fuel (.star item) input =
      scan (fun n => recognizeEnv grammar env n item) fuel input := by
  induction fuel generalizing input with
  | zero => rfl
  | succ n ih =>
      unfold scan
      change (match recognizeEnv grammar env n item input with
        | .error reason => Except.error reason
        | .ok none => Except.ok (some input)
        | .ok (some rest) => if rest.length < input.length then recognizeEnv grammar env n (.star item) rest
                              else Except.error "zero-width repetition") = _
      cases result : recognizeEnv grammar env n item input with
      | error reason => rfl
      | ok value =>
          cases value with
          | none => rfl
          | some rest => simp [ih]

theorem generated_slot (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2) (.ref "ProseSlot" ["ind"]) input =
      scan (fun n => recognizeEnv Generated.pegGrammar [("ind", ind)] n (.ref "SlotInline" ["ind"])) fuel input := by
  change recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 1)
    (.choice [[.star (.ref "SlotInline" ["ind"])]]) input = _
  rw [PegModelTest.single_group _ _ _ _ _ (by simp), star]

theorem generated_table_cell (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 2) (.ref "TableCell" []) input =
      scan (fun n => recognizeEnv Generated.pegGrammar [] n (.ref "CellInline" [])) fuel input := by
  change recognizeEnv Generated.pegGrammar [] (fuel + 1)
    (.choice [[.star (.ref "CellInline" [])]]) input = _
  rw [PegModelTest.single_group _ _ _ _ _ (by simp), star]

private def recoveryArgument : Expr := .choice [[.ref "Sp" [], .ref "PosArg" []]]

theorem generated_skipped (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "SkippedArgs" []) input =
      match recognizeEnv Generated.pegGrammar [] fuel recoveryArgument input with
      | .error reason => .error reason
      | .ok none => .ok none
      | .ok (some rest) => if rest.length < input.length then
          scan (fun n => recognizeEnv Generated.pegGrammar [] n recoveryArgument) fuel rest
        else .error "zero-width repetition" := by
  change recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice [[.plus recoveryArgument]]) input = _
  rw [PegModelTest.single_group _ _ _ _ _ (by simp)]
  change (match recognizeEnv Generated.pegGrammar [] fuel recoveryArgument input with
    | .error reason => Except.error reason
    | .ok none => Except.ok none
    | .ok (some rest) => if rest.length < input.length then recognizeEnv Generated.pegGrammar [] fuel (.star recoveryArgument) rest
                          else Except.error "zero-width repetition") = _
  cases result : recognizeEnv Generated.pegGrammar [] fuel recoveryArgument input with
  | error reason => rfl
  | ok value =>
      cases value with
      | none => rfl
      | some rest => simp [star]

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

private def optional (input : List Char) : ParseResult → ParseResult
  | .ok none => .ok (some input)
  | other => other

private def separatedTail (element : String) : Expr :=
  .choice [[.ref "Comma" [], .ref "ES" [], .ref element [], .ref "ES" []]]

private def entries (element : String) : Expr :=
  .opt (.choice [[.ref element [], .ref "ES" [], .star (separatedTail element)]])

private def readEntries (element : String) (fuel : Nat) (input : List Char) : ParseResult :=
  let read := recognizeEnv Generated.pegGrammar [] fuel
  optional input (next (read (.ref element []) input) (fun rest =>
    next (read (.ref "ES" []) rest)
      (scan (fun n => recognizeEnv Generated.pegGrammar [] n (separatedTail element)) fuel)))

private theorem entries_eq (element : String) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [] (fuel+2) (entries element) input = readEntries element fuel input := by
  have group : recognizeEnv Generated.pegGrammar [] (fuel+1)
      (.choice [[.ref element [], .ref "ES" [], .star (separatedTail element)]]) input =
      next (recognizeEnv Generated.pegGrammar [] fuel (.ref element []) input) (fun rest =>
        next (recognizeEnv Generated.pegGrammar [] fuel (.ref "ES" []) rest)
          (scan (fun n => recognizeEnv Generated.pegGrammar [] n (separatedTail element)) fuel)) := by
    change runChoices (fun items => runSequence (fun scope e x => recognizeEnv Generated.pegGrammar scope fuel e x) _ [] items input)
      [[.ref element [], .ref "ES" [], .star (separatedTail element)]] = _
    cases first : recognizeEnv Generated.pegGrammar [] fuel (.ref element []) input with
    | error reason => simp [runChoices, foldChoice, runSequence, next, first]; rfl
    | ok value =>
        cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, first]; rfl
        | some rest =>
            cases ws : recognizeEnv Generated.pegGrammar [] fuel (.ref "ES" []) rest with
            | error reason => simp [runChoices, foldChoice, runSequence, next, first, ws]; rfl
            | ok val =>
                cases val with
                | none => simp [runChoices, foldChoice, runSequence, next, first, ws]; rfl
                | some tail =>
                    cases more : scan (fun n => recognizeEnv Generated.pegGrammar [] n (separatedTail element)) fuel tail with
                    | error reason => simp [runChoices, foldChoice, runSequence, next, first, ws, star, more]; rfl
                    | ok ending => cases ending <;> simp [runChoices, foldChoice, runSequence, next, first, ws, star, more] <;> rfl
  change (match recognizeEnv Generated.pegGrammar [] (fuel+1) _ input with
    | .error reason => Except.error reason
    | .ok none => Except.ok (some input)
    | .ok hit => Except.ok hit) = _
  rw [group]
  dsimp only [readEntries]
  generalize next _ _ = result
  cases result with
  | error => rfl
  | ok value => cases value <;> rfl

private def delimited (left element right : String) : List Expr :=
  [.ref left [], .ref "ES" [], entries element, .ref right []]

theorem generated_collection (name left element right : String)
    (rule : (name = "ArrayExpr" ∧ left = "LBr" ∧ element = "Expr" ∧ right = "RBr") ∨
      (name = "HashExpr" ∧ left = "LBrace" ∧ element = "HashEntry" ∧ right = "RBrace"))
    (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel+4) (.ref name []) input =
      next (recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref left []) input) (fun afterLeft =>
        next (recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "ES" []) afterLeft) (fun body =>
          next (readEntries element fuel body) (recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref right [])))) := by
  have outer : recognizeEnv Generated.pegGrammar env (fuel+4) (.ref name []) input =
      recognizeEnv Generated.pegGrammar [] (fuel+3) (.choice [delimited left element right]) input := by
    rcases rule with ⟨rfl,rfl,rfl,rfl⟩ | ⟨rfl,rfl,rfl,rfl⟩ <;> rfl
  rw [outer]
  change runChoices (fun items => runSequence (fun scope e x => recognizeEnv Generated.pegGrammar scope (fuel+2) e x) _ [] items input)
    [delimited left element right] = _
  cases first : recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref left []) input with
  | error reason => simp [delimited, runChoices, foldChoice, runSequence, next, first]; rfl
  | ok value =>
      cases value with
      | none => simp [delimited, runChoices, foldChoice, runSequence, next, first]; rfl
      | some a =>
          cases ws : recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "ES" []) a with
          | error reason => simp [delimited, runChoices, foldChoice, runSequence, next, first, ws]; rfl
          | ok val =>
              cases val with
              | none => simp [delimited, runChoices, foldChoice, runSequence, next, first, ws]; rfl
              | some b =>
                  cases body : readEntries element fuel b with
                  | error reason => simp [delimited, runChoices, foldChoice, runSequence, next, first, ws, entries_eq, body]; rfl
                  | ok v =>
                      cases v with
                      | none => simp [delimited, runChoices, foldChoice, runSequence, next, first, ws, entries_eq, body]; rfl
                      | some c =>
                          have parsed := entries_eq element fuel b
                          rw [body] at parsed
                          unfold entries at parsed
                          cases close : recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref right []) c with
                          | error reason => simp [delimited, runChoices, foldChoice, runSequence, next, first, ws, entries, parsed, body, close]; rfl
                          | ok endVal => cases endVal <;> simp [delimited, runChoices, foldChoice, runSequence, next, first, ws, entries, parsed, body, close] <;> rfl

end RuleRepetition
