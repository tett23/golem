import OptionalBoolTotal
import ChoicePayloadTotal
import UnboundSequenceTotal
namespace PayloadSequenceTotal
open PegModel OptionalBoolTotal

def markFalse (result : ParseResult) : BoolResult :=
  result.map (Option.map (fun rest => (rest,false)))
theorem erase_false (result : ParseResult) : erase (markFalse result) = result := by
  cases result with
  | error reason => rfl
  | ok value => cases value <;> rfl

def capturedOptional (grammar : Grammar) (env : Params) : Nat → Expr → List Char → BoolResult
  | 0, _, _ => .error "fuel exhausted"
  | 1, _, _ => .error "fuel exhausted"
  | fuel+2, child, input => flag (fun rest => recognizeEnv grammar env fuel child rest) input

theorem erase_captured (grammar : Grammar) (env : Params) (fuel : Nat)
    (name : String) (child : Expr) (input : List Char) :
    erase (capturedOptional grammar env fuel child input) =
      recognizeEnv grammar env fuel (.bind (some name) (.opt child)) input := by
  cases fuel with
  | zero => rfl
  | succ n => cases n with
    | zero => rfl
    | succ fuel => exact generated_capture grammar env fuel name child input

def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .error reason => .error reason
  | .ok none => .ok none
  | .ok (some rest) => read rest

theorem follow_append (read : Expr → List Char → ParseResult)
    (left right : List Expr) (input : List Char) :
    UnboundSequenceTotal.follow read (left ++ right) input =
      next (UnboundSequenceTotal.follow read left input) (UnboundSequenceTotal.follow read right) := by
  induction left generalizing input with
  | nil => rfl
  | cons item items ih =>
      cases result : read item input with
      | error reason => simp [UnboundSequenceTotal.follow,next,result]
      | ok value => cases value with
        | none => simp [UnboundSequenceTotal.follow,next,result]
        | some rest => simp [UnboundSequenceTotal.follow,next,result,ih]
#print axioms erase_false
#print axioms erase_captured
#print axioms follow_append
end PayloadSequenceTotal
