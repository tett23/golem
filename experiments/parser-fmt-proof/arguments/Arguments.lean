/- Golem ADR 0351 I6-I8: an executable model of argument diagnostics.
   An occurrence remains in the input after an error. Positions are ordinal
   here; the Haskell comparison checks the corresponding source spans. -/
namespace ArgumentDiagnostics

inductive Kind where
  | nat | string | bool
  deriving DecidableEq, Repr

structure Rule where
  name : String
  kind : Kind
  required : Bool
  repeatable : Bool
  deriving Repr

structure Argument where
  name : String
  kind : Kind
  deriving Repr

inductive Error where
  | unknown | duplicate | wrongType | missing
  deriving DecidableEq, Repr

structure Finding where
  position : Nat
  name : String
  error : Error
  deriving DecidableEq, Repr

def ruleFor (rules : List Rule) (name : String) : Option Rule :=
  rules.find? (fun rule => rule.name == name)

/- The order of these three lists is the tie break at one occurrence. An
   unknown name is also non-repeatable, so later occurrences report both. -/
def atOccurrence (rules : List Rule) (seen : List String)
    (position : Nat) (arg : Argument) : List Finding :=
  let rule := ruleFor rules arg.name
  (if rule.isNone then [{ position, name := arg.name, error := .unknown }] else []) ++
  (if seen.contains arg.name && (rule.isNone || rule.any (fun r => !r.repeatable))
   then [{ position, name := arg.name, error := .duplicate }] else []) ++
  (if rule.any (fun r => r.kind != arg.kind)
   then [{ position, name := arg.name, error := .wrongType }] else [])

def scan (rules : List Rule) : List Argument → List String → Nat → List Finding
  | [], _, _ => []
  | arg :: rest, seen, position =>
      atOccurrence rules seen position arg ++
        scan rules rest (arg.name :: seen) (position + 1)

/- Presence is checked by name alone. A value of the wrong kind still
   supplies a required argument. Missing findings follow the source. -/
def missing (rules : List Rule) (args : List Argument) : List Finding :=
  (rules.filter (fun rule => rule.required && !(args.any (fun arg => arg.name == rule.name)))).map
    (fun rule => { position := args.length, name := rule.name, error := .missing })

def check (rules : List Rule) (args : List Argument) : List Finding :=
  scan rules args [] 0 ++ missing rules args

private theorem splitMembership {xs ys : List α} {x : α} (h : x ∈ xs ++ ys) :
    x ∈ xs ∨ x ∈ ys := by
  induction xs with
  | nil => exact Or.inr h
  | cons a rest ih =>
      cases h with
      | head => exact Or.inl (.head _)
      | tail _ later =>
          exact (ih later).elim (fun h => Or.inl (.tail _ h)) Or.inr

theorem occurrencePosition {rules seen position arg finding}
    (found : finding ∈ atOccurrence rules seen position arg) :
    finding.position = position := by
  simp only [atOccurrence] at found
  split at found <;> split at found <;> split at found <;>
    simp_all <;> rcases found with h | h <;> first | simp [h] | rcases h with h | h <;> simp [h]

theorem scanPositionBounds {rules seen position args finding}
    (found : finding ∈ scan rules args seen position) :
    position ≤ finding.position ∧ finding.position < position + args.length := by
  induction args generalizing seen position with
  | nil => simp [scan] at found
  | cons arg rest ih =>
      cases splitMembership (show finding ∈ _ ++ _ from found) with
      | inl here =>
          rw [occurrencePosition here]
          simp only [List.length_cons]
          omega
      | inr later =>
          have bounds := ih later
          simp only [List.length_cons]
          omega

-- Each finding precedes only findings at the same or a later position.
def InSourceOrder : List Finding → Prop
  | [] => True
  | x :: xs => (∀ y ∈ xs, x.position ≤ y.position) ∧ InSourceOrder xs

private theorem samePositionOrdered {xs : List Finding} {n : Nat}
    (h : ∀ x ∈ xs, x.position = n) : InSourceOrder xs := by
  induction xs with
  | nil => trivial
  | cons x xs ih =>
      have tail : ∀ y ∈ xs, y.position = n := fun y hy => h y (.tail _ hy)
      exact ⟨fun y hy => Nat.le_of_eq ((h x (.head _)).trans (tail y hy).symm), ih tail⟩

private theorem orderedAppend {xs ys : List Finding} (left : InSourceOrder xs)
    (right : InSourceOrder ys) (cross : ∀ x ∈ xs, ∀ y ∈ ys, x.position ≤ y.position) :
    InSourceOrder (xs ++ ys) := by
  induction xs with
  | nil => exact right
  | cons x xs ih =>
      constructor
      · intro y hy
        exact (splitMembership hy).elim (left.1 y) (cross x (.head _) y)
      · exact ih left.2 (fun z hz => cross z (.tail _ hz))

theorem scanInSourceOrder (rules : List Rule) (args : List Argument)
    (seen : List String) (position : Nat) : InSourceOrder (scan rules args seen position) := by
  induction args generalizing seen position with
  | nil => trivial
  | cons a rest ih =>
      apply orderedAppend (samePositionOrdered (fun _ h => occurrencePosition h)) (ih _ _)
      intro x hx y hy
      have bounds := (scanPositionBounds hy).1
      rw [occurrencePosition hx]
      omega

theorem checkInSourceOrder (rules : List Rule) (args : List Argument) :
    InSourceOrder (check rules args) := by
  have endPos : ∀ f ∈ missing rules args, f.position = args.length := by
    intro f hf
    obtain ⟨rule, _, eq⟩ := List.mem_map.mp hf
    subst f
    rfl
  apply orderedAppend (scanInSourceOrder rules args [] 0) (samePositionOrdered endPos)
  intro x hx y hy
  rw [endPos y hy]
  exact Nat.le_of_lt (by simpa using (scanPositionBounds hx).2)

-- Every reported occurrence belongs to the call. Only declaration
-- omissions can point just past its last argument.
theorem checkPosition {rules args finding} (found : finding ∈ check rules args) :
    finding.position < args.length ∨
      (finding.position = args.length ∧ finding.error = .missing) := by
  cases splitMembership (show finding ∈ _ ++ _ from found) with
  | inl scanned => exact Or.inl (by simpa using (scanPositionBounds scanned).2)
  | inr omitted =>
      obtain ⟨rule, _, eq⟩ := List.mem_map.mp omitted
      subst finding
      exact Or.inr ⟨rfl, rfl⟩

-- At a single supplied argument, the emitted codes form a subsequence
-- of the specified tie order. The Boolean choices include absent codes.
theorem occurrenceErrorOrder (rules : List Rule) (seen : List String)
    (position : Nat) (arg : Argument) :
    ∃ unknown duplicate wrongType : Bool,
      (atOccurrence rules seen position arg).map Finding.error =
        (if unknown then [Error.unknown] else []) ++
        (if duplicate then [Error.duplicate] else []) ++
        (if wrongType then [Error.wrongType] else []) := by
  let rule := ruleFor rules arg.name
  refine ⟨rule.isNone, seen.contains arg.name && (rule.isNone || rule.any (fun r => !r.repeatable)),
    rule.any (fun r => r.kind != arg.kind), ?_⟩
  simp only [atOccurrence, rule, List.map_append]
  repeat first | split | rfl

theorem absentUnknown (rules : List Rule) (seen : List String)
    (position : Nat) (arg : Argument) (h : ruleFor rules arg.name = none) :
    { position, name := arg.name, error := Error.unknown } ∈
      atOccurrence rules seen position arg := by
  simp [atOccurrence, h]

/- Golem ADR 0351 I7/I8: the value and the distance from an earlier
   occurrence do not affect the two findings for a repeated unknown name. -/
theorem repeatedUnknownFindings (rules : List Rule) (seen : List String)
    (position : Nat) (arg : Argument) (unknown : ruleFor rules arg.name = none)
    (repeated : seen.contains arg.name = true) :
    atOccurrence rules seen position arg =
      [{ position, name := arg.name, error := .unknown },
       { position, name := arg.name, error := .duplicate }] := by
  simp [atOccurrence, unknown, repeated, Option.any]

/- Splitting at any occurrence preserves all preceding findings and passes
   exactly the preceding names to the remaining scan. -/
theorem scan_split (rules : List Rule) (before after : List Argument)
    (seen : List String) (position : Nat) :
    scan rules (before ++ after) seen position =
      scan rules before seen position ++
        scan rules after ((before.map Argument.name).reverse ++ seen) (position + before.length) := by
  induction before generalizing seen position with
  | nil => simp [scan]
  | cons arg rest ih =>
      simp [scan, ih, List.reverse_cons, List.append_assoc, Nat.add_assoc,
        Nat.add_comm, Nat.add_left_comm]

theorem scan_repeated_unknown (rules : List Rule) (before after : List Argument)
    (arg : Argument) (unknown : ruleFor rules arg.name = none)
    (repeated : (before.map Argument.name).reverse.contains arg.name = true) :
    scan rules (before ++ arg :: after) [] 0 =
      scan rules before [] 0 ++
        [{ position := before.length, name := arg.name, error := Error.unknown },
         { position := before.length, name := arg.name, error := Error.duplicate }] ++
        scan rules after (arg.name :: (before.map Argument.name).reverse) (before.length + 1) := by
  rw [scan_split]
  simp [scan, repeatedUnknownFindings rules _ _ _ unknown repeated, List.append_assoc]

theorem repeatedKnownFindings (rules : List Rule) (seen : List String)
    (position : Nat) (arg : Argument) (rule : Rule)
    (known : ruleFor rules arg.name = some rule) (once : rule.repeatable = false)
    (repeated : seen.contains arg.name = true) :
    atOccurrence rules seen position arg =
      [{ position, name := arg.name, error := .duplicate }] ++
        (if rule.kind != arg.kind then [{ position, name := arg.name, error := .wrongType }] else []) := by
  simp [atOccurrence, known, once, repeated, Option.any]

-- I7 also covers the first occurrence of a name, even after unrelated
-- errors. No duplicate is emitted until that same spelling appears again.
theorem firstUnknownFindings (rules : List Rule) (seen : List String)
    (position : Nat) (arg : Argument) (unknown : ruleFor rules arg.name = none)
    (first : seen.contains arg.name = false) :
    atOccurrence rules seen position arg =
      [{ position, name := arg.name, error := .unknown }] := by
  simp [atOccurrence, unknown, first, Option.any]

theorem scan_repeated_known (rules : List Rule) (before after : List Argument)
    (arg : Argument) (rule : Rule) (known : ruleFor rules arg.name = some rule)
    (once : rule.repeatable = false)
    (repeated : (before.map Argument.name).reverse.contains arg.name = true) :
    scan rules (before ++ arg :: after) [] 0 =
      scan rules before [] 0 ++
        [{ position := before.length, name := arg.name, error := Error.duplicate }] ++
        (if rule.kind != arg.kind then
          [{ position := before.length, name := arg.name, error := Error.wrongType }] else []) ++
        scan rules after (arg.name :: (before.map Argument.name).reverse) (before.length + 1) := by
  rw [scan_split]
  simp [scan, repeatedKnownFindings rules _ _ _ rule known once repeated, List.append_assoc]

theorem presentRequiredName (name : String) (kind : Kind) (rest : List Argument) :
    (({ name, kind } : Argument) :: rest).any (fun arg => arg.name == name) = true := by
  simp

/- Golem ADR 0351 I7: a supplied name cannot give rise to a missing
   finding, including when its value failed the declared type check. -/
theorem suppliedNeverMissing (rules : List Rule) (args : List Argument)
    (name : String) (supplied : args.any (fun arg => arg.name == name) = true) :
    { position := args.length, name, error := Error.missing } ∉ missing rules args := by
  intro found
  obtain ⟨rule, selected, eq⟩ := List.mem_map.mp found
  have same : rule.name = name := congrArg Finding.name eq
  have eligible := (List.mem_filter.mp selected).2
  simp [same, supplied] at eligible

/- Golem ADR 0351 I8: projecting the names of missing findings returns
   exactly the unsupplied required names in declaration order. -/
theorem missingInDeclarationOrder (rules : List Rule) (args : List Argument) :
    (missing rules args).map Finding.name =
      (rules.filter (fun rule => rule.required &&
        !(args.any (fun arg => arg.name == rule.name)))).map Rule.name := by
  simp [missing, List.map_map, Function.comp_def]

def known : List Rule :=
  [ { name := "tax", kind := .bool, required := false, repeatable := false },
    { name := "count", kind := .nat, required := true, repeatable := false },
    { name := "label", kind := .string, required := true, repeatable := false } ]

/- FunctionSpec's book.price accepts tax and unit after its positional
   value. The first positional value is omitted from this keyword model. -/
def bookPrice : List Rule :=
  [ { name := "tax", kind := .bool, required := false, repeatable := false },
    { name := "unit", kind := .string, required := false, repeatable := false } ]

example :
    check bookPrice
      [ { name := "x", kind := .nat },
        { name := "x", kind := .nat },
        { name := "x", kind := .nat },
        { name := "tax", kind := .string } ] =
      [ { position := 0, name := "x", error := .unknown },
        { position := 1, name := "x", error := .unknown },
        { position := 1, name := "x", error := .duplicate },
        { position := 2, name := "x", error := .unknown },
        { position := 2, name := "x", error := .duplicate },
        { position := 3, name := "tax", error := .wrongType } ] := by decide

/- These are the same boundaries used by the Haskell regression tests:
   unknown x three times, an ill-typed required argument, and two missing
   required names in declaration order. -/
example :
    check known
      [ { name := "x", kind := .nat },
        { name := "x", kind := .nat },
        { name := "x", kind := .string },
        { name := "count", kind := .string } ] =
      [ { position := 0, name := "x", error := .unknown },
        { position := 1, name := "x", error := .unknown },
        { position := 1, name := "x", error := .duplicate },
        { position := 2, name := "x", error := .unknown },
        { position := 2, name := "x", error := .duplicate },
        { position := 3, name := "count", error := .wrongType },
        { position := 4, name := "label", error := .missing } ] := by decide

example :
    missing known [] =
      [ { position := 0, name := "count", error := .missing },
        { position := 0, name := "label", error := .missing } ] := by decide

end ArgumentDiagnostics
