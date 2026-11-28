import QuotedCanonical
namespace MixedKeywords
open WordRoundTrip
inductive Input where
  | word (value : Word)
  | string (parts : List StringRoundTrip.Part)
abbrev Entry := Word × Input
abbrev Value := QuotedKeywords.Value

def spelling : Input → List Char
  | .word value => value.chars
  | .string parts => '"' :: (StringRoundTrip.spell parts ++ ['"'])
def abstractValue : Input → Value
  | .word value => .word value.chars
  | .string parts => .string (parts.map StringRoundTrip.partValue)
def abstract (entry : Entry) : List Char × Value := (entry.1.chars,abstractValue entry.2)
def printArgs : List Entry → List Char
  | [] => ['\n']
  | (name,value)::rest => ' ' :: name.chars ++ '=' :: (spelling value ++ printArgs rest)
def scanValue (input : List Char) : Option (Value × List Char) :=
  match input with
  | '"'::body => do
      let (spelling,after) ← StringRoundTrip.scanString Generated.stringLitEscapeFirst body
      some (.string (StringRoundTrip.unescape spelling),after)
  | _ =>
    let value := input.takeWhile allowed
    let after := input.dropWhile allowed
    if value.isEmpty || containsDoublePercent value then none else some (.word value,after)
def parseArgs : Nat → List Char → Option (List (List Char × Value))
  | _, ['\n'] => some []
  | fuel+1, ' '::rest =>
    if startsComment rest then none else
    let name := rest.takeWhile allowed
    let afterName := rest.dropWhile allowed
    if name.isEmpty then none else
    match afterName with
    | '='::valueStart => do
      let (value,afterValue) ← scanValue valueStart
      let values ← parseArgs fuel afterValue
      some ((name,value)::values)
    | _ => none
  | _, _ => none

def safeNames (args : List Entry) : Prop := ∀ entry ∈ args, startsComment entry.1.chars = false
def safeValue : Input → Prop
  | .word value => containsDoublePercent value.chars = false
  | .string _ => True
def safeValues (args : List Entry) : Prop := ∀ entry ∈ args, safeValue entry.2
private theorem not_empty (word : Word) : word.chars.isEmpty = false := by
  cases h : word.chars with
  | nil => exact False.elim (word.nonempty h)
  | cons c rest => rfl

theorem printed_tail (args : List Entry) : ∃ sep tail,
    printArgs args = sep::tail ∧ allowed sep = false := by
  cases args with
  | nil => exact ⟨'\n',[],rfl,by decide⟩
  | cons pair args => exact ⟨' ',pair.1.chars ++ '='::(spelling pair.2 ++ printArgs args),rfl,by decide⟩

theorem scan_spelling (value : Input) (sep : Char) (tail : List Char)
    (blocked : allowed sep = false) (safe : safeValue value) :
    scanValue (spelling value ++ sep::tail) = some (abstractValue value,sep::tail) := by
  cases value with
  | string parts => simp [scanValue,spelling,abstractValue,List.append_assoc,
      StringRoundTrip.scan_spell,StringRoundTrip.unescape_spell]
  | word value =>
    have first : value.chars ≠ [] := value.nonempty
    cases chars : value.chars with
    | nil => exact False.elim (first chars)
    | cons c cs =>
      have noquote : c ≠ '"' := by
        intro eq
        have valid := value.valid c (by simp [chars])
        subst c
        change false = true at valid
        contradiction
      have take := take_append value.chars tail sep value.valid blocked
      have drop := drop_append value.chars tail sep value.valid blocked
      simp only [spelling,abstractValue]
      unfold scanValue
      split
      next body eq =>
        have bad : c = '"' := by simpa [chars,List.cons_append] using congrArg List.head? eq
        exact False.elim (noquote bad)
      next unmatched =>
        rw [take,drop]
        simp only [safeValue] at safe
        simp [not_empty value,safe]

theorem I1_I2_mixed_arguments (args : List Entry) (fuel : Nat)
    (names : safeNames args) (values : safeValues args) (enough : args.length ≤ fuel) :
    parseArgs fuel (printArgs args) = some (args.map abstract) := by
  induction args generalizing fuel with
  | nil => cases fuel <;> rfl
  | cons entry args ih =>
    cases fuel with
    | zero => simp at enough
    | succ fuel =>
      rcases entry with ⟨name,value⟩
      have guarded := safe_name_before_equals name (spelling value ++ printArgs args) (names (name,value) (by simp))
      have restNames : safeNames args := by intro entry member; exact names entry (by simp [member])
      have restValues : safeValues args := by intro entry member; exact values entry (by simp [member])
      obtain ⟨sep,tail,printed,blocked⟩ := printed_tail args
      have scanned : scanValue (spelling value ++ printArgs args) = some (abstractValue value,printArgs args) := by
        rw [printed]; exact scan_spelling value sep tail blocked (values (name,value) (by simp))
      simp [printArgs,parseArgs,
        take_append name.chars (spelling value ++ printArgs args) '=' name.valid (by decide),
        drop_append name.chars (spelling value ++ printArgs args) '=' name.valid (by decide),
        guarded,not_empty name,scanned,ih fuel restNames restValues (Nat.le_of_succ_le_succ enough),abstract]
#print axioms I1_I2_mixed_arguments
end MixedKeywords
