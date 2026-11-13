import Generated

namespace LeftRecursionTotal

open PegModel

-- Follow successive operator/operand suffixes until they stop or fail.
def finish (suffix : List Char → ParseResult) (rest : List Char) : ParseResult :=
  match suffix rest with
  | .error reason => .error reason
  | .ok none => .ok (some rest)
  | .ok (some next) =>
      if next.length < rest.length then finish suffix next
      else .error "zero-width left recursion"
termination_by rest.length

private theorem stopped (suffix : List Char → ParseResult) (ticks : List Nat) (result : ParseResult) :
    ticks.foldl (growLeftStep suffix) (result, true) = (result, true) := by
  induction ticks with
  | nil => rfl
  | cons _ _ ih => cases result <;> simp_all [List.foldl, growLeftStep]

private theorem enough (suffix : List Char → ParseResult) (rest : List Char) (ticks : List Nat)
    (budget : rest.length < ticks.length) :
    ticks.foldl (growLeftStep suffix) (.ok (some rest), false) = (finish suffix rest, true) := by
  cases ticks with
  | nil => simp at budget; omega
  | cons tick ticks =>
      rw [List.foldl, finish]
      cases step : suffix rest with
      | error reason => simpa [growLeftStep, step] using stopped suffix ticks (.error reason)
      | ok value =>
          cases value with
          | none => simpa [growLeftStep, step] using stopped suffix ticks (.ok (some rest))
          | some next =>
              by_cases shrinks : next.length < rest.length
              · simp [growLeftStep, step, shrinks]
                exact enough suffix next ticks (by simp at budget; omega)
              · simpa [growLeftStep, step, shrinks] using
                  stopped suffix ticks (.error "zero-width left recursion")
termination_by rest.length

private theorem ticks_length (n : Nat) (acc : List Nat) :
    (List.range.loop n acc).length = n + acc.length := by
  induction n generalizing acc with
  | zero => simp [List.range.loop]
  | succ n ih => simp [List.range.loop, ih]; omega

theorem growth_result (suffix : List Char → ParseResult) (rest : List Char) (fuel : Nat)
    (budget : rest.length < fuel) :
    growLeft suffix fuel (.ok (some rest)) = finish suffix rest := by
  have ticks : rest.length < (List.range fuel).length := by
    simpa [List.range, ticks_length] using budget
  simp [growLeft, enough suffix rest _ ticks]

private theorem terminal_seed (suffix : List Char → ParseResult) (result : ParseResult)
    (terminal : result = .ok none ∨ ∃ reason, result = .error reason) (fuel : Nat) :
    growLeft suffix (fuel + 1) result = result := by
  have length : (List.range (fuel + 1)).length = fuel + 1 := by simp [List.range, ticks_length]
  unfold growLeft
  cases ticks : List.range (fuel + 1) with
  | nil => rw [ticks] at length; simp at length; omega
  | cons tick rest =>
      rcases terminal with h | ⟨reason, h⟩ <;> subst result <;>
        simp [List.foldl, growLeftStep, stopped]

def binarySuffix (op operand : String) : Expr :=
  .choice [[.ref "ES" [], .ref op [], .ref "ES" [], .ref operand []]]

def seed (operand : String) : Expr := .choice [[.ref operand []]]

theorem generated_binary_growth (env : Params) (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar env (fuel + 1) (.ref "AddExpr" []) input =
      growLeft (recognizeEnv Generated.pegGrammar [] fuel (binarySuffix "AddOp" "MulExpr")) fuel
        (recognizeEnv Generated.pegGrammar [] fuel (seed "MulExpr") input) ∧
    recognizeEnv Generated.pegGrammar env (fuel + 1) (.ref "MulExpr" []) input =
      growLeft (recognizeEnv Generated.pegGrammar [] fuel (binarySuffix "MulOp" "UnaryExpr")) fuel
        (recognizeEnv Generated.pegGrammar [] fuel (seed "UnaryExpr") input) := by
  exact ⟨rfl, rfl⟩

theorem binary_result (name op operand : String)
    (which : (name = "AddExpr" ∧ op = "AddOp" ∧ operand = "MulExpr") ∨
      (name = "MulExpr" ∧ op = "MulOp" ∧ operand = "UnaryExpr"))
    (env : Params) (input : List Char) (fuel : Nat)
    (budget : ∀ rest, recognizeEnv Generated.pegGrammar [] (fuel + 1) (seed operand) input =
      .ok (some rest) → rest.length < fuel + 1) :
    let parse := recognizeEnv Generated.pegGrammar [] (fuel + 1)
    recognizeEnv Generated.pegGrammar env (fuel + 2) (.ref name []) input =
      match parse (seed operand) input with
      | .error reason => .error reason
      | .ok none => .ok none
      | .ok (some rest) => finish (parse (binarySuffix op operand)) rest := by
  dsimp only
  have growth := generated_binary_growth env input (fuel + 1)
  have rule : recognizeEnv Generated.pegGrammar env (fuel + 2) (.ref name []) input =
      growLeft (recognizeEnv Generated.pegGrammar [] (fuel + 1) (binarySuffix op operand))
        (fuel + 1) (recognizeEnv Generated.pegGrammar [] (fuel + 1) (seed operand) input) := by
    rcases which with ⟨rfl, rfl, rfl⟩ | ⟨rfl, rfl, rfl⟩
    · exact growth.1
    · exact growth.2
  rw [rule]
  cases start : recognizeEnv Generated.pegGrammar [] (fuel + 1) (seed operand) input with
  | error reason => exact terminal_seed _ _ (Or.inr ⟨_, rfl⟩) _
  | ok result =>
      cases result with
      | none => exact terminal_seed _ _ (Or.inl rfl) _
      | some rest => exact growth_result _ rest _ (budget rest start)

end LeftRecursionTotal
