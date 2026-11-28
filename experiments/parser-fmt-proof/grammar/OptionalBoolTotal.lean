import PegModelTest
namespace OptionalBoolTotal
open PegModel
abbrev BoolResult := Except String (Option (List Char × Bool))
def erase : BoolResult → ParseResult
  | .error reason => .error reason
  | .ok value => .ok (value.map Prod.fst)
def flag (read : List Char → ParseResult) (input : List Char) : BoolResult :=
  match read input with
  | .error reason => .error reason
  | .ok none => .ok (some (input,false))
  | .ok (some rest) => .ok (some (rest,true))
def optional (read : List Char → ParseResult) (input : List Char) : ParseResult :=
  match read input with
  | .error reason => .error reason
  | .ok none => .ok (some input)
  | .ok hit => .ok hit
theorem erase_flag (read : List Char → ParseResult) (input : List Char) :
    erase (flag read input) = optional read input := by
  cases result : read input with
  | error reason => simp [erase,flag,optional,result]
  | ok value => cases value <;> simp [erase,flag,optional,result]

theorem payload_flag (read : List Char → ParseResult) (input : List Char) :
    (flag read input).map (Option.map Prod.snd) =
      (read input).map (fun body => some body.isSome) := by
  cases result : read input with
  | error reason => simp [flag,result]; rfl
  | ok value => cases value <;> (simp [flag,result]; rfl)

theorem generated_optional (grammar : Grammar) (env : Params) (fuel : Nat)
    (child : Expr) (input : List Char) :
    erase (flag (fun rest => recognizeEnv grammar env fuel child rest) input) =
      recognizeEnv grammar env (fuel+1) (.opt child) input := by
  rw [erase_flag]
  rfl

theorem generated_capture (grammar : Grammar) (env : Params) (fuel : Nat)
    (name : String) (child : Expr) (input : List Char) :
    erase (flag (fun rest => recognizeEnv grammar env fuel child rest) input) =
      recognizeEnv grammar env (fuel+2) (.bind (some name) (.opt child)) input := by
  exact generated_optional grammar env fuel child input

theorem maybe_action {α : Type} (body : Option α) :
    body.elim false (fun _ => true) = body.isSome := by
  cases body <;> rfl
#print axioms payload_flag
#print axioms erase_flag
#print axioms generated_optional
#print axioms generated_capture
#print axioms maybe_action
end OptionalBoolTotal
