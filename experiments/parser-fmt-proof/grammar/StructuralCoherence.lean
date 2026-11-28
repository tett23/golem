import Generated
namespace PegModel

theorem structural_pack (grammar : Grammar) (fuel : Nat) (env : Params) (expr : Expr) (input : List Char) :
    recognizeEnv grammar env fuel expr input =
      (FuelTable.pack (interpreterStep grammar) fuel).fst env expr input := by
  induction fuel generalizing env expr input with
  | zero => rfl
  | succ fuel ih =>
      conv => lhs; unfold recognizeEnv; dsimp only
      simp only [ih]
      rfl

namespace FuelTable
universe u
theorem get_pack {α : Type u} (step : (n : Nat) → Nat.below (motive := fun _ => α) n → α)
    (n m : Nat) (bound : m < n) : get n (pack step n).snd m bound = (pack step m).fst := by
  induction n generalizing m with
  | zero => exact False.elim (Nat.not_lt_zero m bound)
  | succ n ih =>
      change (if small : m < n then get n (pack step n).snd m small else (pack step n).fst) = _
      by_cases small : m < n
      · simp only [dif_pos small]
        exact ih m small
      · have same : m = n := Nat.le_antisymm (Nat.le_of_lt_succ bound) (Nat.le_of_not_gt small)
        subst m
        simp only [dif_neg (Nat.lt_irrefl n)]
end FuelTable

theorem stored_recognizer (grammar : Grammar) (fuel n : Nat) (bound : n < fuel)
    (env : Params) (expr : Expr) (input : List Char) :
    FuelTable.get fuel (FuelTable.pack (interpreterStep grammar) fuel).snd n bound env expr input =
      recognizeEnv grammar env n expr input := by
  rw [FuelTable.get_pack,structural_pack]
#print axioms structural_pack
#print axioms FuelTable.get_pack
#print axioms stored_recognizer
end PegModel
