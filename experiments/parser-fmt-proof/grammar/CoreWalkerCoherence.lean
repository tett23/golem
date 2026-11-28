import StructuralCoherence
import UnboundSequenceTotal
namespace CoreWalkerCoherence
open PegModel

theorem walk (read : Expr → List Char → ParseResult) (items : List Expr) (input : List Char) :
    BoolPayload.walk read items input = UnboundSequenceTotal.follow read items input := by
  induction items generalizing input with
  | nil => rfl
  | cons item items ih =>
    cases result : read item input with
    | error reason => simp [BoolPayload.walk,UnboundSequenceTotal.follow,result]
    | ok value => cases value with
      | none => simp [BoolPayload.walk,UnboundSequenceTotal.follow,result]
      | some rest => simp [BoolPayload.walk,UnboundSequenceTotal.follow,result,ih]
#print axioms walk
end CoreWalkerCoherence
