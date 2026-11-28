import PayloadSequenceTotal
import CommandRecognitionTotal
namespace CommandBoolProjectionTotal
open PegModel OptionalBoolTotal PayloadSequenceTotal
private def callPrefix : List Expr := CommandRecognitionTotal.callItems.take 6
private def body : Expr := .ref "CommandBody" ["ind"]
private theorem shape : CommandRecognitionTotal.callItems =
    callPrefix ++ [.bind (some "b") (.opt body)] := by rfl

def call (ind fuel : Nat) (input : List Char) : BoolResult :=
  match UnboundSequenceTotal.follow
      (fun item rest => recognizeEnv Generated.pegGrammar [("ind",ind)] fuel item rest) callPrefix input with
  | .error reason => .error reason
  | .ok none => .ok none
  | .ok (some rest) => capturedOptional Generated.pegGrammar [("ind",ind)] fuel body rest

private theorem follow_one (read : Expr → List Char → ParseResult) (item : Expr) (input : List Char) :
    UnboundSequenceTotal.follow read [item] input = read item input := by
  cases result : read item input with
  | error reason => simp [UnboundSequenceTotal.follow,result]
  | ok value => cases value <;> simp [UnboundSequenceTotal.follow,result]

theorem erase_call (ind fuel : Nat) (input : List Char) :
    erase (call ind fuel input) = UnboundSequenceTotal.follow
      (fun item rest => recognizeEnv Generated.pegGrammar [("ind",ind)] fuel item rest)
      CommandRecognitionTotal.callItems input := by
  rw [shape,follow_append]
  have one : UnboundSequenceTotal.follow
      (fun item rest => recognizeEnv Generated.pegGrammar [("ind",ind)] fuel item rest)
      [.bind (some "b") (.opt body)] =
      (fun rest => recognizeEnv Generated.pegGrammar [("ind",ind)] fuel (.bind (some "b") (.opt body)) rest) := by
    funext rest
    exact follow_one _ _ _
  rw [one]
  unfold call
  cases result : UnboundSequenceTotal.follow
      (fun item rest => recognizeEnv Generated.pegGrammar [("ind",ind)] fuel item rest) callPrefix input with
  | error reason => rfl
  | ok value => cases value with
    | none => rfl
    | some rest => exact erase_captured _ _ _ _ _ _

def reader (ind fuel : Nat) (input : List Char) (isCall : Bool) : BoolResult :=
  if isCall then call ind fuel input else markFalse (UnboundSequenceTotal.follow
    (fun item rest => recognizeEnv Generated.pegGrammar [("ind",ind)] fuel item rest)
    CommandRecognitionTotal.setItems input)
def command (ind fuel : Nat) (input : List Char) : BoolResult :=
  foldChoice (reader ind fuel input) [false,true]
private theorem erase_map (result : BoolResult) :
    erase result = result.map (Option.map Prod.fst) := by
  cases result <;> rfl

theorem erase_command (ind fuel : Nat) (input : List Char) :
    erase (command ind fuel input) =
      recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+2) (.ref "BlockCommand" ["ind"]) input := by
  rw [erase_map]
  unfold command
  rw [ChoicePayloadTotal.choice_map]
  have projection : (fun isCall => (reader ind fuel input isCall).map (Option.map Prod.fst)) =
      (fun isCall => UnboundSequenceTotal.follow
        (fun item rest => recognizeEnv Generated.pegGrammar [("ind",ind)] fuel item rest)
        (if isCall then CommandRecognitionTotal.callItems else CommandRecognitionTotal.setItems) input) := by
    funext isCall
    rw [← erase_map]
    cases isCall with
    | false => exact erase_false _
    | true => exact erase_call _ _ _
  rw [projection,CommandRecognitionTotal.generated]
  rfl
#print axioms erase_call
#print axioms erase_command
end CommandBoolProjectionTotal
