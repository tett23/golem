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
