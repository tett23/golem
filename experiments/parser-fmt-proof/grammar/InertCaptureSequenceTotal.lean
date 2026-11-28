import UnboundSequenceTotal
namespace InertCaptureSequenceTotal
open PegModel

private theorem folded (parse : Params → Expr → List Char → ParseResult)
    (boundLength : Params → Expr → List Char → Except String (Option Nat))
    (env : Params) (items : List Expr)
    (unbound : ∀ item ∈ items, ∀ scope before, boundLength scope item before = .ok none)
    (state : Option (List Char × Params))
    (fixed : ∀ rest scope, state = some (rest, scope) → scope = env) :
    (items.foldlM (fun state item =>
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
      | some (rest, _) => UnboundSequenceTotal.follow (parse env) items rest := by
  induction items generalizing state with
  | nil => cases state <;> rfl
  | cons item items ih =>
      have headFree := unbound item (by simp)
      have tailFree : ∀ child ∈ items, ∀ scope before, boundLength scope child before = .ok none := by
        intro child member
        exact unbound child (by simp [member])
      cases state with
      | none => exact ih tailFree none (by simp)
      | some pair =>
          rcases pair with ⟨rest, scope⟩
          have same := fixed rest scope rfl
          subst scope
          simp only [List.foldlM, UnboundSequenceTotal.follow]
          cases hit : parse env item rest with
          | error reason => rfl
          | ok value => cases value with
            | none => exact ih tailFree none (by simp)
            | some next =>
                cases item <;> try exact ih tailFree (some (next, env)) (by simp_all)
                case bind name child =>
                  cases name <;> simp_all

theorem sequence (parse : Params → Expr → List Char → ParseResult)
    (boundLength : Params → Expr → List Char → Except String (Option Nat))
    (env : Params) (items : List Expr) (input : List Char)
    (unbound : ∀ item ∈ items, ∀ scope before, boundLength scope item before = .ok none) :
    runSequence parse boundLength env items input = UnboundSequenceTotal.follow (parse env) items input := by
  exact folded parse boundLength env items unbound (some (input, env)) (by simp_all)

#print axioms sequence
end InertCaptureSequenceTotal
