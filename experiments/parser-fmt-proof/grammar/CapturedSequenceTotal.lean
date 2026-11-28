import PegModelTest
namespace CapturedSequenceTotal
open PegModel

def follow (parse : Params → Expr → List Char → ParseResult)
    (bound : Params → Expr → List Char → Except String (Option Nat)) :
    Params → List Expr → List Char → ParseResult
  | _, [], input => .ok (some input)
  | scope, item :: items, input =>
      match parse scope item input with
      | .error reason => .error reason
      | .ok none => .ok none
      | .ok (some rest) =>
          match item with
          | .bind (some name) _ =>
              match bound scope item input with
              | .error reason => .error reason
              | .ok none => follow parse bound scope items rest
              | .ok (some value) => follow parse bound ((name,value)::scope) items rest
          | _ => follow parse bound scope items rest

private theorem folded (parse : Params → Expr → List Char → ParseResult)
    (bound : Params → Expr → List Char → Except String (Option Nat))
    (items : List Expr) (state : Option (List Char × Params)) :
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
                  match bound scope item rest with
                  | .error reason => Except.error reason
                  | .ok none => pure (some (next, scope))
                  | .ok (some value) => pure (some (next, (name, value) :: scope))
              | _ => pure (some (next, scope))) state :
        Except String (Option (List Char × Params))).map (Option.map Prod.fst) =
      match state with
      | none => .ok none
      | some (rest, scope) => follow parse bound scope items rest := by
  induction items generalizing state with
  | nil => cases state <;> rfl
  | cons item items ih =>
      cases state with
      | none => exact ih none
      | some pair =>
          rcases pair with ⟨rest, scope⟩
          simp only [List.foldlM, follow]
          cases hit : parse scope item rest with
          | error reason => rfl
          | ok value => cases value with
            | none => exact ih none
            | some next =>
                cases item <;> try exact ih (some (next,scope))
                case bind name child =>
                  cases name with
                  | none => exact ih (some (next,scope))
                  | some name =>
                    cases count : bound scope (.bind (some name) child) rest with
                    | error reason => rfl
                    | ok value => cases value with
                      | none => exact ih (some (next,scope))
                      | some value => exact ih (some (next,(name,value)::scope))

theorem sequence (parse : Params → Expr → List Char → ParseResult)
    (bound : Params → Expr → List Char → Except String (Option Nat))
    (env : Params) (items : List Expr) (input : List Char) :
    runSequence parse bound env items input = follow parse bound env items input := by
  exact folded parse bound items (some (input,env))
#print axioms sequence
end CapturedSequenceTotal
