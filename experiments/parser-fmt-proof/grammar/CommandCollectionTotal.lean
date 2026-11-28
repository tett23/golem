import CommandBoolProjectionTotal
import BoolRepetitionTotal
namespace CommandCollectionTotal
open PegModel OptionalBoolTotal BoolRepetitionTotal

def reference (ind : Nat) : Nat → List Char → BoolResult
  | 0, _ => .error "fuel exhausted"
  | 1, _ => .error "fuel exhausted"
  | fuel+2, input => CommandBoolProjectionTotal.command ind fuel input

theorem erase_reference (ind fuel : Nat) (input : List Char) :
    erase (reference ind fuel input) =
      recognizeEnv Generated.pegGrammar [("ind",ind)] fuel (.ref "BlockCommand" ["ind"]) input := by
  cases fuel with
  | zero => rfl
  | succ n => cases n with
    | zero => rfl
    | succ fuel => exact CommandBoolProjectionTotal.erase_command ind fuel input

theorem erase_collection (ind fuel : Nat) (input : List Char) :
    eraseValues (plus (reference ind) fuel input) =
      recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+1) (.plus (.ref "BlockCommand" ["ind"])) input := by
  rw [erase_plus]
  simp only [erase_reference]
  exact (PlusComposition.plus _ _ _ _ _).symm

def captured (ind : Nat) : Nat → List Char → ValuesResult
  | 0, _ => .error "fuel exhausted"
  | 1, _ => .error "fuel exhausted"
  | fuel+2, input => plus (reference ind) fuel input

theorem erase_captured (ind fuel : Nat) (input : List Char) :
    eraseValues (captured ind fuel input) =
      recognizeEnv Generated.pegGrammar [("ind",ind)] fuel
        (.bind (some "cs") (.plus (.ref "BlockCommand" ["ind"]))) input := by
  cases fuel with
  | zero => rfl
  | succ n => cases n with
    | zero => rfl
    | succ fuel => exact erase_collection ind fuel input
#print axioms erase_reference
#print axioms erase_collection
#print axioms erase_captured
end CommandCollectionTotal
