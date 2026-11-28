import CommandCollectionTotal
namespace GenericBoolPayloadTotal
open PegModel OptionalBoolTotal BoolRepetitionTotal
abbrev Read := Params → Nat → Expr → List Char → ParseResult
private def callPrefix : List Expr := CommandRecognitionTotal.callItems.take 6
private def body : Expr := .ref "CommandBody" ["ind"]
def optional (read : Read) (env : Params) : Nat → Expr → List Char → BoolResult
  | 0, _, _ => .error "fuel exhausted"
  | 1, _, _ => .error "fuel exhausted"
  | fuel+2, child, input => flag (fun rest => read env fuel child rest) input

def call (read : Read) (ind fuel : Nat) (input : List Char) : BoolResult :=
  match UnboundSequenceTotal.follow (fun item rest => read [("ind",ind)] fuel item rest) callPrefix input with
  | .error reason => .error reason
  | .ok none => .ok none
  | .ok (some rest) => optional read [("ind",ind)] fuel body rest

def reader (read : Read) (ind fuel : Nat) (input : List Char) (isCall : Bool) : BoolResult :=
  if isCall then call read ind fuel input else PayloadSequenceTotal.markFalse
    (UnboundSequenceTotal.follow (fun item rest => read [("ind",ind)] fuel item rest)
      CommandRecognitionTotal.setItems input)
def command (read : Read) (ind fuel : Nat) (input : List Char) : BoolResult :=
  foldChoice (reader read ind fuel input) [false,true]
def reference (read : Read) (ind : Nat) : Nat → List Char → BoolResult
  | 0, _ => .error "fuel exhausted"
  | 1, _ => .error "fuel exhausted"
  | fuel+2, input => command read ind fuel input

def captured (read : Read) (ind : Nat) : Nat → List Char → ValuesResult
  | 0, _ => .error "fuel exhausted"
  | 1, _ => .error "fuel exhausted"
  | fuel+2, input => plus (reference read ind) fuel input

theorem actual (ind fuel : Nat) (input : List Char) :
    captured (fun env n item rest => recognizeEnv Generated.pegGrammar env n item rest) ind fuel input =
      CommandCollectionTotal.captured ind fuel input := by rfl
def clip (read : Read) (cap : Nat) : Read :=
  fun env fuel item rest => read env (min fuel cap) item rest

private theorem drop_two {n cap : Nat} (bound : n+2 ≤ cap) : n ≤ cap :=
  Nat.le_trans (Nat.le_succ n) (Nat.le_trans (Nat.le_succ (n+1)) bound)

theorem optional_clip (read : Read) (cap fuel : Nat) (env : Params) (child : Expr)
    (input : List Char) (bound : fuel ≤ cap) :
    optional (clip read cap) env fuel child input = optional read env fuel child input := by
  cases fuel with
  | zero => rfl
  | succ n => cases n with
    | zero => rfl
    | succ fuel =>
      have lower : fuel ≤ cap := drop_two bound
      simp [optional,clip,Nat.min_eq_left lower]

theorem call_clip (read : Read) (cap ind fuel : Nat) (input : List Char) (bound : fuel ≤ cap) :
    call (clip read cap) ind fuel input = call read ind fuel input := by
  simp only [call,clip,Nat.min_eq_left bound]
  cases result : UnboundSequenceTotal.follow
      (fun item rest => read [("ind",ind)] fuel item rest) callPrefix input with
  | error reason => rfl
  | ok value => cases value with
    | none => rfl
    | some rest => exact optional_clip read cap fuel _ _ _ bound

theorem command_clip (read : Read) (cap ind fuel : Nat) (input : List Char) (bound : fuel ≤ cap) :
    command (clip read cap) ind fuel input = command read ind fuel input := by
  have same : reader (clip read cap) ind fuel input = reader read ind fuel input := by
    funext isCall
    cases isCall with
    | false => simp [reader,clip,Nat.min_eq_left bound]
    | true => exact call_clip read cap ind fuel input bound
  simp only [command,same]

theorem reference_clip (read : Read) (cap ind fuel : Nat) (input : List Char) (bound : fuel ≤ cap) :
    reference (clip read cap) ind fuel input = reference read ind fuel input := by
  cases fuel with
  | zero => rfl
  | succ n => cases n with
    | zero => rfl
    | succ fuel => exact command_clip read cap ind fuel input (drop_two bound)

theorem scan_clip (read : Read) (cap ind fuel : Nat) (input : List Char) (bound : fuel ≤ cap) :
    scan (reference (clip read cap) ind) fuel input = scan (reference read ind) fuel input := by
  induction fuel generalizing input with
  | zero => rfl
  | succ fuel ih =>
    have lower : fuel ≤ cap := Nat.le_trans (Nat.le_succ fuel) bound
    simp only [scan,reference_clip read cap ind fuel input lower]
    cases result : reference read ind fuel input with
    | error reason => rfl
    | ok value => cases value with
      | none => rfl
      | some pair =>
        rcases pair with ⟨rest,value⟩
        by_cases progress : rest.length < input.length
        · simp [progress,ih rest lower]
        · simp [progress]

theorem plus_clip (read : Read) (cap ind fuel : Nat) (input : List Char) (bound : fuel ≤ cap) :
    plus (reference (clip read cap) ind) fuel input = plus (reference read ind) fuel input := by
  simp only [plus,reference_clip read cap ind fuel input bound]
  cases result : reference read ind fuel input with
  | error reason => rfl
  | ok value => cases value with
    | none => rfl
    | some pair =>
      rcases pair with ⟨rest,value⟩
      by_cases progress : rest.length < input.length
      · simp [progress,scan_clip read cap ind fuel rest bound]
      · simp [progress]

theorem captured_clip (read : Read) (cap ind fuel : Nat) (input : List Char) (bound : fuel ≤ cap) :
    captured (clip read cap) ind fuel input = captured read ind fuel input := by
  cases fuel with
  | zero => rfl
  | succ n => cases n with
    | zero => rfl
    | succ fuel => exact plus_clip read cap ind fuel input (drop_two bound)
theorem clipped_erasure (cap ind fuel : Nat) (input : List Char) (bound : fuel ≤ cap) :
    eraseValues (captured (clip (fun env n item rest => recognizeEnv Generated.pegGrammar env n item rest) cap)
      ind fuel input) =
      recognizeEnv Generated.pegGrammar [("ind",ind)] fuel
        (.bind (some "cs") (.plus (.ref "BlockCommand" ["ind"]))) input := by
  rw [captured_clip _ cap ind fuel input bound, actual]
  exact CommandCollectionTotal.erase_captured ind fuel input
#print axioms clipped_erasure
#print axioms captured_clip
#print axioms actual
end GenericBoolPayloadTotal
