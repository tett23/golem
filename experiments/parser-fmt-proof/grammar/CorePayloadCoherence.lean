import CoreWalkerCoherence
import GenericBoolPayloadTotal
namespace CorePayloadCoherence
open PegModel OptionalBoolTotal

theorem optional (read : BoolPayload.Read) (env : Params) (fuel : Nat)
    (child : Expr) (input : List Char) :
    BoolPayload.optional read env fuel child input = GenericBoolPayloadTotal.optional read env fuel child input := by
  cases fuel with
  | zero => rfl
  | succ n => cases n <;> rfl

theorem command (read : BoolPayload.Read) (ind fuel : Nat) (input : List Char) :
    BoolPayload.command read ind fuel input = GenericBoolPayloadTotal.command read ind fuel input := by
  dsimp only [BoolPayload.command,GenericBoolPayloadTotal.command]
  apply congrArg (fun reader => foldChoice reader [false,true])
  funext isCall
  cases isCall with
  | false =>
    simp only [GenericBoolPayloadTotal.reader,CoreWalkerCoherence.walk]
    rfl
  | true =>
    simp only [GenericBoolPayloadTotal.reader,GenericBoolPayloadTotal.call,CoreWalkerCoherence.walk,optional]
    rfl

theorem reference (read : BoolPayload.Read) (ind fuel : Nat) (input : List Char) :
    BoolPayload.reference read ind fuel input = GenericBoolPayloadTotal.reference read ind fuel input := by
  cases fuel with
  | zero => rfl
  | succ n => cases n with
    | zero => rfl
    | succ fuel => exact command read ind fuel input

theorem scan (read : BoolPayload.Read) (ind fuel : Nat) (input : List Char) :
    BoolPayload.scan read ind fuel input =
      BoolRepetitionTotal.scan (GenericBoolPayloadTotal.reference read ind) fuel input := by
  induction fuel generalizing input with
  | zero => rfl
  | succ fuel ih =>
    simp only [BoolPayload.scan,BoolRepetitionTotal.scan,reference]
    cases result : GenericBoolPayloadTotal.reference read ind fuel input with
    | error reason => rfl
    | ok value => cases value with
      | none => rfl
      | some pair =>
        rcases pair with ⟨rest,value⟩
        by_cases progress : rest.length < input.length
        · simp only [if_pos progress,ih]
          rfl
        · simp only [if_neg progress]

theorem plus (read : BoolPayload.Read) (ind fuel : Nat) (input : List Char) :
    BoolPayload.plus read ind fuel input =
      BoolRepetitionTotal.plus (GenericBoolPayloadTotal.reference read ind) fuel input := by
  simp only [BoolPayload.plus,BoolRepetitionTotal.plus,reference]
  cases result : GenericBoolPayloadTotal.reference read ind fuel input with
  | error reason => rfl
  | ok value => cases value with
    | none => rfl
    | some pair =>
      rcases pair with ⟨rest,value⟩
      by_cases progress : rest.length < input.length
      · simp only [if_pos progress,scan]
        rfl
      · simp only [if_neg progress]

theorem captured (read : BoolPayload.Read) (ind fuel : Nat) (input : List Char) :
    BoolPayload.captured read ind fuel input = GenericBoolPayloadTotal.captured read ind fuel input := by
  cases fuel with
  | zero => rfl
  | succ n => cases n with
    | zero => rfl
    | succ fuel => exact plus read ind fuel input
#print axioms captured
end CorePayloadCoherence
