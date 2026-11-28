import PlusComposition
import OptionalBoolTotal
namespace BoolRepetitionTotal
open PegModel OptionalBoolTotal
abbrev ValuesResult := Except String (Option (List Char × List Bool))
def eraseValues : ValuesResult → ParseResult
  | .error reason => .error reason
  | .ok value => .ok (value.map Prod.fst)
def prepend (value : Bool) (result : ValuesResult) : ValuesResult :=
  result.map (Option.map (fun pair => (pair.1,value::pair.2)))
theorem erase_prepend (value : Bool) (result : ValuesResult) :
    eraseValues (prepend value result) = eraseValues result := by
  cases result with
  | error reason => rfl
  | ok result => cases result <;> rfl

def scan (read : Nat → List Char → BoolResult) : Nat → List Char → ValuesResult
  | 0, _ => .error "fuel exhausted"
  | fuel+1, input =>
      match read fuel input with
      | .error reason => .error reason
      | .ok none => .ok (some (input,[]))
      | .ok (some (rest,value)) => if rest.length < input.length then prepend value (scan read fuel rest)
                                 else .error "zero-width repetition"

theorem erase_scan (read : Nat → List Char → BoolResult) (fuel : Nat) (input : List Char) :
    eraseValues (scan read fuel input) =
      RuleRepetition.scan (fun n rest => erase (read n rest)) fuel input := by
  induction fuel generalizing input with
  | zero => rfl
  | succ fuel ih =>
      cases result : read fuel input with
      | error reason => simp [scan,RuleRepetition.scan,erase,eraseValues,result]
      | ok value => cases value with
        | none => simp [scan,RuleRepetition.scan,erase,eraseValues,result]
        | some pair =>
          rcases pair with ⟨rest,value⟩
          by_cases progress : rest.length < input.length
          · simp [scan,RuleRepetition.scan,result,erase,progress,erase_prepend,ih]
          · simp [scan,RuleRepetition.scan,result,erase,eraseValues,progress]

def plus (read : Nat → List Char → BoolResult) (fuel : Nat) (input : List Char) : ValuesResult :=
  match read fuel input with
  | .error reason => .error reason
  | .ok none => .ok none
  | .ok (some (rest,value)) => if rest.length < input.length then prepend value (scan read fuel rest)
                             else .error "zero-width repetition"

theorem erase_plus (read : Nat → List Char → BoolResult) (fuel : Nat) (input : List Char) :
    eraseValues (plus read fuel input) =
      PlusComposition.scanPlus (fun n rest => erase (read n rest)) fuel input := by
  cases result : read fuel input with
  | error reason => simp [plus,PlusComposition.scanPlus,erase,eraseValues,result]
  | ok value => cases value with
    | none => simp [plus,PlusComposition.scanPlus,erase,eraseValues,result]
    | some pair =>
      rcases pair with ⟨rest,value⟩
      by_cases progress : rest.length < input.length
      · simp [plus,PlusComposition.scanPlus,result,erase,progress,erase_prepend,erase_scan]
      · simp [plus,PlusComposition.scanPlus,result,erase,eraseValues,progress]
theorem prepend_nonempty (value : Bool) (result : ValuesResult) (rest : List Char) :
    prepend value result ≠ .ok (some (rest,[])) := by
  cases result with
  | error reason => simp [prepend,Except.map]
  | ok result => cases result with
    | none => simp [prepend,Except.map]
    | some pair => rcases pair with ⟨input,values⟩; simp [prepend,Except.map]

theorem plus_nonempty (read : Nat → List Char → BoolResult) (fuel : Nat)
    (input rest : List Char) : plus read fuel input ≠ .ok (some (rest,[])) := by
  cases result : read fuel input with
  | error reason => simp [plus,result]
  | ok value => cases value with
    | none => simp [plus,result]
    | some pair =>
      rcases pair with ⟨next,value⟩
      by_cases progress : next.length < input.length
      · simp [plus,result,progress,prepend_nonempty]
      · simp [plus,result,progress]
#print axioms prepend_nonempty
#print axioms plus_nonempty
#print axioms erase_prepend
#print axioms erase_scan
#print axioms erase_plus
end BoolRepetitionTotal
