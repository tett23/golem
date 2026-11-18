import Eval

/- The checked Core fragment CPVar/CPWild/CPLit, CEq and CGuards.
   The source-to-Core translation remains a separate obligation. -/
namespace GolemEval.Selection

inductive Pattern where
  | variable : String → Pattern
  | wildcard : Pattern
  | literal : Value → Pattern

inductive Rhs where
  | plain : Expr → Rhs
  | guards : List (Option Expr × Expr) → Rhs

structure Equation where
  pattern : Pattern
  rhs : Rhs

def matchPattern (pattern : Pattern) (value : Value) : Option (List (String × Value)) :=
  match pattern with
  | .variable name => some [(name, value)]
  | .wildcard => some []
  | .literal expected => if expected = value then some [] else none

def runGuards : List (Option Expr × Expr) → Environment → Nat →
    Except Failure (Option Value × Nat)
  | [], _, budget => .ok (none, budget)
  | (none, body) :: _, env, budget => do
      let (value, left) ← run body env budget
      return (some value, left)
  | (some condition, body) :: rest, env, budget => do
      let (test, left) ← run condition env budget
      if test = .boolean true then
        let (value, afterBody) ← run body env left
        return (some value, afterBody)
      else runGuards rest env left

def runRhs (rhs : Rhs) (env : Environment) (budget : Nat) :
    Except Failure (Option Value × Nat) :=
  match rhs with
  | .plain body => do
      let (value, left) ← run body env budget
      return (some value, left)
  | .guards guards => runGuards guards env budget

def select : List Equation → Value → Environment → Nat → Except Failure (Value × Nat)
  | [], _, _, _ => .error .noEquation
  | equation :: rest, value, env, budget =>
      match matchPattern equation.pattern value with
      | none => select rest value env budget
      | some bindings => do
          let left ← spend 1 budget
          let (result, afterRhs) ← runRhs equation.rhs
            { env with variables := bindings ++ env.variables } left
          match result with
          | some result => .ok (result, afterRhs)
          | none => select rest value env afterRhs

def call (argument : Expr) (equations : List Equation)
    (env : Environment) (budget : Nat) : Except Failure (Value × Nat) := do
  let (value, afterArgument) ← run argument env budget
  let left ← spend 1 afterArgument
  select equations value env left

-- Selection follows the checked equation order: a failed literal costs no
-- step, a selected equation costs one, and a failed guard retains its budget.
theorem select_literal_miss (expected value : Value) (h : expected ≠ value)
    (rhs : Rhs) (rest : List Equation) (env : Environment) (budget : Nat) :
    select (⟨.literal expected, rhs⟩ :: rest) value env budget =
      select rest value env budget := by
  simp [select, matchPattern, h]

theorem guards_false_continue (condition body : Expr)
    (rest : List (Option Expr × Expr)) (env : Environment)
    (budget left : Nat) (value : Value)
    (h : run condition env budget = .ok (value, left))
    (hfalse : value ≠ .boolean true) :
    runGuards ((some condition, body) :: rest) env budget =
      runGuards rest env left := by
  simp [runGuards, h, hfalse, Bind.bind, Except.bind]

theorem select_exhausted_guards (name : String) (rest : List Equation)
    (value : Value) (env : Environment) (budget : Nat) :
    select (⟨.variable name, .guards []⟩ :: rest) value env (budget + 1) =
      select rest value env budget := by
  have exact : spend 1 (budget + 1) = .ok budget := by
    exact spend_exact budget 1
  simp [select, matchPattern, runRhs, runGuards, exact,
    Bind.bind, Except.bind, Pure.pure, Except.pure]

inductive SourceRhs where
  | plain : SourceExpr → SourceRhs
  | guards : List (Option SourceExpr × SourceExpr) → SourceRhs

structure SourceEquation where
  pattern : Pattern
  rhs : SourceRhs

def parseGuard (guard : Option SourceExpr × SourceExpr) : Option Expr × Expr :=
  (guard.1.map parsed, parsed guard.2)

def formatGuard (guard : Option SourceExpr × SourceExpr) :
    Option SourceExpr × SourceExpr :=
  (guard.1.map format, format guard.2)

def parseRhs : SourceRhs → Rhs
  | .plain body => .plain (parsed body)
  | .guards guards => .guards (guards.map parseGuard)

def formatRhs : SourceRhs → SourceRhs
  | .plain body => .plain (format body)
  | .guards guards => .guards (guards.map formatGuard)

def parseEquation (eq : SourceEquation) : Equation :=
  ⟨eq.pattern, parseRhs eq.rhs⟩

def formatEquation (eq : SourceEquation) : SourceEquation :=
  ⟨eq.pattern, formatRhs eq.rhs⟩

theorem parse_guard_format (guard : Option SourceExpr × SourceExpr) :
    parseGuard (formatGuard guard) = parseGuard guard := by
  cases guard with
  | mk condition body =>
    cases condition <;> simp [parseGuard, formatGuard, parsed_format]

theorem parse_rhs_format (rhs : SourceRhs) :
    parseRhs (formatRhs rhs) = parseRhs rhs := by
  cases rhs with
  | plain body => simp [parseRhs, formatRhs, parsed_format]
  | guards guards =>
    simp [parseRhs, formatRhs, List.map_map, Function.comp_def, parse_guard_format]

theorem parse_equation_format (eq : SourceEquation) :
    parseEquation (formatEquation eq) = parseEquation eq := by
  cases eq
  simp [parseEquation, formatEquation, parse_rhs_format]

-- For any finite checked equation list and any guard list in this Core
-- fragment, formatting trivia in the argument and all bodies is inert.
theorem I5_equation_selection_format (arg : SourceExpr)
    (equations : List SourceEquation) (env : Environment) (budget : Nat) :
    call (parsed (format arg))
      ((equations.map formatEquation).map parseEquation) env budget =
    call (parsed arg) (equations.map parseEquation) env budget := by
  have hmap : (equations.map formatEquation).map parseEquation =
      equations.map parseEquation := by
    induction equations with
    | nil => rfl
    | cons eq rest ih => simp [parse_equation_format, ih]
  rw [parsed_format, hmap]

theorem call_literal_format (arg : SourceExpr) (equations : List Equation)
    (env : Environment) (budget : Nat) :
    call (parsed (format arg)) equations env budget =
      call (parsed arg) equations env budget := by
  rw [parsed_format]

end GolemEval.Selection
