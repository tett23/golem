import Generated

namespace WordRoundTrip

def allowed (c : Char) : Bool := !(Generated.wordForbidden.contains c)

private theorem space_forbidden : allowed ' ' = false := by decide
private theorem equals_forbidden : allowed '=' = false := by decide
private theorem newline_forbidden : allowed '\n' = false := by decide

structure Word where
  chars : List Char
  valid : ∀ c ∈ chars, allowed c = true
  nonempty : chars ≠ []

def startsComment : List Char → Bool
  | '%' :: '%' :: _ => true
  | _ => false

def safeNames (args : List (Word × Word)) : Prop :=
  ∀ pair ∈ args, startsComment pair.1.chars = false

private theorem safe_name_before_equals (name : Word) (tail : List Char)
    (safe : startsComment name.chars = false) :
    startsComment (name.chars ++ '=' :: tail) = false := by
  cases chars : name.chars with
  | nil => exact False.elim (name.nonempty chars)
  | cons c rest =>
      cases rest with
      | nil => simp [startsComment]
      | cons d more =>
          by_cases hc : c = '%'
          · subst c
            by_cases hd : d = '%'
            · subst d
              simp [startsComment, chars] at safe
            · simp [startsComment, hd]
          · simp [startsComment, hc]

def printArgs : List (Word × Word) → List Char
  | [] => ['\n']
  | (name, value) :: rest => ' ' :: name.chars ++ '=' :: value.chars ++ printArgs rest

def parseArgs : Nat → List Char → Option (List (List Char × List Char))
  | _, ['\n'] => some []
  | fuel + 1, ' ' :: rest =>
      if startsComment rest then none else
      let name := rest.takeWhile allowed
      let afterName := rest.dropWhile allowed
      if name.isEmpty then none
      else
        match afterName with
        | '=' :: valueStart =>
            let value := valueStart.takeWhile allowed
            let afterValue := valueStart.dropWhile allowed
            if value.isEmpty then none
            else (parseArgs fuel afterValue).map ((name, value) :: ·)
        | _ => none
  | _, _ => none

example : parseArgs 1 [' ', '%', '%', '=', 'x', '\n'] = none := by rfl
example : parseArgs 1 [' ', '%', '%', 'f', 'o', 'o', '=', 'x', '\n'] = none := by rfl
example : parseArgs 1 [' ', 'f', 'o', 'o', '=', '%', '%', '\n'] =
    some [(['f', 'o', 'o'], ['%', '%'])] := by rfl

theorem take_append (word : List Char) (tail : List Char) (sep : Char)
    (valid : ∀ c ∈ word, allowed c = true) (blocked : allowed sep = false) :
    (word ++ sep :: tail).takeWhile allowed = word := by
  induction word with
  | nil => simp [List.takeWhile, blocked]
  | cons c rest ih =>
      have hc : allowed c = true := valid c (by simp)
      have hr : ∀ x ∈ rest, allowed x = true := by
        intro x hx
        exact valid x (by simp [hx])
      simp [List.takeWhile, hc, ih hr]

theorem drop_append (word : List Char) (tail : List Char) (sep : Char)
    (valid : ∀ c ∈ word, allowed c = true) (blocked : allowed sep = false) :
    (word ++ sep :: tail).dropWhile allowed = sep :: tail := by
  induction word with
  | nil => simp [List.dropWhile, blocked]
  | cons c rest ih =>
      have hc : allowed c = true := valid c (by simp)
      have hr : ∀ x ∈ rest, allowed x = true := by
        intro x hx
        exact valid x (by simp [hx])
      simp [List.dropWhile, hc, ih hr]

theorem printed_tail (args : List (Word × Word)) :
    ∃ sep tail, printArgs args = sep :: tail ∧ allowed sep = false := by
  cases args with
  | nil => exact ⟨'\n', [], rfl, newline_forbidden⟩
  | cons pair rest =>
      rcases pair with ⟨name, value⟩
      exact ⟨' ', name.chars ++ '=' :: value.chars ++ printArgs rest, rfl, space_forbidden⟩

private theorem not_empty (word : Word) : word.chars.isEmpty = false := by
  cases h : word.chars with
  | nil => exact False.elim (word.nonempty h)
  | cons _ _ => rfl

theorem parse_print_args (args : List (Word × Word)) (namesSafe : safeNames args) :
    ∀ fuel, args.length ≤ fuel →
      parseArgs fuel (printArgs args) =
        some (args.map fun (name, value) => (name.chars, value.chars)) := by
  induction args with
  | nil =>
      intro fuel _
      cases fuel <;> rfl
  | cons pair rest ih =>
      intro fuel enough
      cases fuel with
      | zero => simp at enough
      | succ n =>
          have h : rest.length ≤ n := Nat.le_of_succ_le_succ enough
          rcases pair with ⟨name, value⟩
          obtain ⟨sep, tail, printed, blocked⟩ := printed_tail rest
          have vt : (value.chars ++ printArgs rest).takeWhile allowed = value.chars := by
            rw [printed]
            exact take_append value.chars tail sep value.valid blocked
          have vd : (value.chars ++ printArgs rest).dropWhile allowed = printArgs rest := by
            rw [printed]
            exact drop_append value.chars tail sep value.valid blocked
          have nameSafe : startsComment name.chars = false :=
            namesSafe (name, value) (by simp)
          have guarded : startsComment (name.chars ++ '=' :: (value.chars ++ printArgs rest)) = false :=
            safe_name_before_equals name (value.chars ++ printArgs rest) nameSafe
          have restSafe : safeNames rest := by
            intro pair member
            exact namesSafe pair (by simp [member])
          simp [printArgs, parseArgs,
            take_append name.chars (value.chars ++ printArgs rest) '=' name.valid equals_forbidden,
            drop_append name.chars (value.chars ++ printArgs rest) '=' name.valid equals_forbidden,
            not_empty name, not_empty value,
            guarded, vt, vd,
            ih restSafe n h]

def renderRaw : List (List Char × List Char) → List Char
  | [] => ['\n']
  | (name, value) :: rest => ' ' :: name ++ '=' :: value ++ renderRaw rest

theorem render_raw_print (args : List (Word × Word)) :
    renderRaw (args.map fun (name, value) => (name.chars, value.chars)) = printArgs args := by
  induction args with
  | nil => rfl
  | cons pair rest ih =>
      rcases pair with ⟨name, value⟩
      simp [renderRaw, printArgs, ih]

def format (fuel : Nat) (input : List Char) : Option (List Char) :=
  (parseArgs fuel input).map renderRaw

theorem format_print (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (enough : args.length ≤ fuel) :
    format fuel (printArgs args) = some (printArgs args) := by
  simp [format, parse_print_args args namesSafe fuel enough, render_raw_print]

theorem parse_after_format (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (enough : args.length ≤ fuel) :
    (format fuel (printArgs args)).bind (parseArgs fuel) =
      some (args.map fun (name, value) => (name.chars, value.chars)) := by
  simp [format_print args fuel namesSafe enough, parse_print_args args namesSafe fuel enough]

theorem format_twice (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (enough : args.length ≤ fuel) :
    (format fuel (printArgs args)).bind (format fuel) = some (printArgs args) := by
  simp [format_print args fuel namesSafe enough]

theorem I1_word_keyword_arguments (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (enough : args.length ≤ fuel) :
    parseArgs fuel (printArgs args) =
      some (args.map fun (name, value) => (name.chars, value.chars)) :=
  parse_print_args args namesSafe fuel enough

theorem I2_word_keyword_ast (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (enough : args.length ≤ fuel) :
    (format fuel (printArgs args)).bind (parseArgs fuel) =
      some (args.map fun (name, value) => (name.chars, value.chars)) :=
  parse_after_format args fuel namesSafe enough

theorem I3_word_keyword_idempotence (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (enough : args.length ≤ fuel) :
    (format fuel (printArgs args)).bind (format fuel) = some (printArgs args) :=
  format_twice args fuel namesSafe enough

-- Any order, omission and repetition is still a list of arbitrary length.
theorem I4_word_keyword_sequences (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (enough : args.length ≤ fuel) :
    parseArgs fuel (printArgs args) =
      some (args.map fun (name, value) => (name.chars, value.chars)) ∧
    (format fuel (printArgs args)).bind (parseArgs fuel) =
      some (args.map fun (name, value) => (name.chars, value.chars)) :=
  ⟨I1_word_keyword_arguments args fuel namesSafe enough,
    I2_word_keyword_ast args fuel namesSafe enough⟩

end WordRoundTrip
