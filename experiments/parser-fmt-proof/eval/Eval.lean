/- A finite evaluation model for Golem ADR 0351, invariant 5.
   The environment and step budget are explicit; source comments and layout
   are absent from the expression passed to evaluation. -/
namespace GolemEval

inductive Value where
  | boolean : Bool → Value
  | nat : Nat → Value
  | string : String → Value
  deriving DecidableEq, Repr

inductive Expr where
  | literal : Value → Expr
  | variable : String → Expr
  | add : Expr → Expr → Expr
  | quotient : Expr → Expr → Expr
  | ternary : Expr → Expr → Expr → Expr
  | append : Expr → Expr → Expr
  | external : String → Expr
  | call : String → Expr → Expr → Expr
  deriving DecidableEq, Repr

inductive Failure where
  | unknownName | missingFile | typeError | divisionByZero | overLimit
  deriving DecidableEq, Repr

structure Environment where
  variables : List (String × Value)
  files : List (String × String)
  deriving Repr

def lookup (bindings : List (String × α)) (name : String) : Option α :=
  (bindings.find? (fun entry => entry.1 == name)).map Prod.snd

def spend (cost budget : Nat) : Except Failure Nat :=
  if cost ≤ budget then .ok (budget - cost) else .error .overLimit

def run : Expr → Environment → Nat → Except Failure (Value × Nat)
  | .literal value, _, budget => .ok (value, budget)
  | .variable name, env, budget =>
      match lookup env.variables name with
      | some value => .ok (value, budget)
      | none => .error .unknownName
  | .external path, env, budget => do
      let left ← spend 1 budget
      match lookup env.files path with
      | some value => .ok (.string value, left)
      | none => .error .missingFile
  | .add a b, env, budget => do
      let (x, afterA) ← run a env budget
      let (y, afterB) ← run b env afterA
      match x, y with
      | .nat m, .nat n => return (.nat (m + n), ← spend 1 afterB)
      | _, _ => .error .typeError
  | .quotient a b, env, budget => do
      let (x, afterA) ← run a env budget
      let (y, afterB) ← run b env afterA
      let left ← spend 1 afterB
      match x, y with
      | .nat _, .nat 0 => .error .divisionByZero
      | .nat m, .nat (n + 1) => return (.nat (m / (n + 1)), left)
      | _, _ => .error .typeError
  | .ternary c a b, env, budget => do
      let (value, afterCondition) ← run c env budget
      let left ← spend 1 afterCondition
      match value with
      | .boolean true => run a env left
      | _ => run b env left
  | .append a b, env, budget => do
      let (x, afterA) ← run a env budget
      let (y, afterB) ← run b env afterA
      match x, y with
      | .string m, .string n => do
          let left ← spend (1 + m.length + n.length) afterB
          return (.string (m ++ n), left)
      | _, _ => .error .typeError
  | .call name arg body, env, budget => do
      let (value, afterArg) ← run arg env budget
      let left ← spend 1 afterArg
      run body { env with variables := (name, value) :: env.variables } left

def eval (budget : Nat) (env : Environment) (expression : Expr) : Except Failure Value := do
  let (value, _) ← run expression env budget
  return value

/- The resolved expression tree retains trivia at each subexpression.
   The grammar model separately checks how source text reaches this tree. -/
inductive SourceExpr where
  | literal : Value → SourceExpr
  | variable : String → SourceExpr
  | external : String → SourceExpr
  | add : SourceExpr → SourceExpr → SourceExpr
  | quotient : SourceExpr → SourceExpr → SourceExpr
  | ternary : SourceExpr → SourceExpr → SourceExpr → SourceExpr
  | append : SourceExpr → SourceExpr → SourceExpr
  | call : String → SourceExpr → SourceExpr → SourceExpr
  | whitespace : String → SourceExpr → SourceExpr
  | comment : String → SourceExpr → SourceExpr

def parsed : SourceExpr → Expr
  | .literal v => .literal v
  | .variable name => .variable name
  | .external path => .external path
  | .add a b => .add (parsed a) (parsed b)
  | .quotient a b => .quotient (parsed a) (parsed b)
  | .ternary c a b => .ternary (parsed c) (parsed a) (parsed b)
  | .append a b => .append (parsed a) (parsed b)
  | .call name arg body => .call name (parsed arg) (parsed body)
  | .whitespace _ x | .comment _ x => parsed x

-- At this abstraction level the printer's changes to whitespace are
-- represented by one canonical spelling. Comments retain their text.
def format : SourceExpr → SourceExpr
  | .literal v => .literal v
  | .variable name => .variable name
  | .external path => .external path
  | .add a b => .add (format a) (format b)
  | .quotient a b => .quotient (format a) (format b)
  | .ternary c a b => .ternary (format c) (format a) (format b)
  | .append a b => .append (format a) (format b)
  | .call name arg body => .call name (format arg) (format body)
  | .whitespace _ x => .whitespace " " (format x)
  | .comment text x => .comment text (format x)

@[simp] theorem parsed_format (source : SourceExpr) : parsed (format source) = parsed source := by
  induction source <;> simp_all [parsed, format]

/- A derivation records how a successful value is obtained, including
   argument evaluation and the body of a user function. -/
inductive Derives : Nat → Environment → Expr → Value → Nat → Prop where
  | literal : Derives n env (.literal value) value n
  | variable (found : lookup env.variables name = some value) :
      Derives n env (.variable name) value n
  | external (found : lookup env.files path = some value) :
      Derives (n + 1) env (.external path) (.string value) n
  | add (left : Derives n env a (.nat x) i)
        (right : Derives i env b (.nat y) (k + 1)) :
      Derives n env (.add a b) (.nat (x + y)) k
  | quotient (left : Derives n env a (.nat x) i)
             (right : Derives i env b (.nat (y + 1)) (k + 1)) :
      Derives n env (.quotient a b) (.nat (x / (y + 1))) k
  | ternaryTrue (condition : Derives n env c (.boolean true) (i + 1))
        (branch : Derives i env a value k) : Derives n env (.ternary c a b) value k
  | ternaryFalse (condition : Derives n env c (.boolean false) (i + 1))
        (branch : Derives i env b value k) : Derives n env (.ternary c a b) value k
  | append (left : Derives n env a (.string x) i)
        (right : Derives i env b (.string y) (k + (1 + x.length + y.length))) :
      Derives n env (.append a b) (.string (x ++ y)) k
  | call (argument : Derives n env a value (i + 1))
         (body : Derives i { env with variables := (name, value) :: env.variables } b result k) :
      Derives n env (.call name a b) result k

@[simp] theorem spend_exact (n cost : Nat) : spend cost (n + cost) = .ok n := by
  simp [spend, Nat.le_add_left]

theorem derives_sound (derivation : Derives n env expression value k) :
    run expression env n = .ok (value, k) := by
  induction derivation <;> simp_all [run, Bind.bind, Except.bind, Pure.pure, Except.pure]

theorem remaining_le_budget (derivation : Derives budget env expression value remaining) :
    remaining ≤ budget := by
  induction derivation <;> omega

theorem I5_eval_format (fuel : Nat) (env : Environment) (source : SourceExpr) :
    eval fuel env (parsed (format source)) = eval fuel env (parsed source) := by
  rw [parsed_format]

theorem I5_derivation_format (fuel : Nat) (env : Environment)
    (source : SourceExpr) (value : Value)
    (derivation : Derives fuel env (parsed source) value remaining) :
    Derives fuel env (parsed (format source)) value remaining := by
  simpa using derivation

example : eval 3 ⟨[("x", .nat 2)], []⟩ (.add (.variable "x") (.literal (.nat 3)))
    = .ok (.nat 5) := by rfl

example : eval 3 ⟨[("x", .string "a")], []⟩ (.add (.variable "x") (.literal (.nat 3)))
    = .error .typeError := by rfl

example : eval 3 ⟨[], []⟩ (.call "x" (.literal (.nat 2))
    (.add (.variable "x") (.literal (.nat 3)))) = .ok (.nat 5) := by rfl

example : eval 0 ⟨[], []⟩ (.add (.literal (.nat 2)) (.literal (.nat 3)))
    = .error .overLimit := by rfl

example : eval 2 ⟨[], []⟩ (.add (.literal (.nat 2)) (.literal (.nat 3)))
    = .ok (.nat 5) := by rfl

example : eval 4 ⟨[], [("data/a.tsv", "a")]⟩
    (.append (.external "data/a.tsv") (.literal (.string "b")))
    = .ok (.string "ab") := by rfl

example : eval 1 ⟨[], []⟩ (.external "data/a.tsv")
    = .error .missingFile := by rfl

-- Literal evaluation spends no reductions. Sibling operations share one budget.
example : eval 0 ⟨[], []⟩ (.literal (.nat 1)) = .ok (.nat 1) := by rfl
example : eval 2 ⟨[], []⟩ (.add (.add (.literal (.nat 1)) (.literal (.nat 1)))
    (.add (.literal (.nat 1)) (.literal (.nat 1)))) = .error .overLimit := by rfl
example : eval 2 ⟨[], []⟩ (.append (.literal (.string "鰍")) (.literal (.string "𠮷")))
    = .error .overLimit := by rfl

example : eval 3 ⟨[], []⟩ (.add (.add (.literal (.nat 1)) (.literal (.nat 1)))
    (.add (.literal (.nat 1)) (.literal (.nat 1)))) = .ok (.nat 4) := by rfl
example : eval 3 ⟨[], []⟩ (.append (.literal (.string "鰍")) (.literal (.string "𠮷")))
    = .ok (.string "鰍𠮷") := by rfl

example : eval 1 ⟨[], []⟩ (.quotient (.literal (.nat 3)) (.literal (.nat 0)))
    = .error .divisionByZero := by rfl
example : eval 0 ⟨[], []⟩ (.quotient (.literal (.nat 3)) (.literal (.nat 0)))
    = .error .overLimit := by rfl
example : eval 1 ⟨[], []⟩ (.quotient (.literal (.nat 3)) (.literal (.nat 2)))
    = .ok (.nat 1) := by rfl

-- Formatting spaces inside a nested expression must preserve its operands.
example (left right : SourceExpr) (spaces : String) :
    parsed (format (.add (.whitespace spaces left) right)) =
      .add (parsed left) (parsed right) := by rw [parsed_format]; rfl

-- A failing branch costs nothing when it is not selected.
example : eval 1 ⟨[], []⟩ (.ternary (.literal (.boolean true)) (.literal (.nat 7))
    (.quotient (.literal (.nat 1)) (.literal (.nat 0)))) = .ok (.nat 7) := by rfl
example : eval 0 ⟨[], []⟩ (.ternary (.literal (.boolean false))
    (.external "missing") (.literal (.nat 7))) = .error .overLimit := by rfl
example : eval 1 ⟨[], []⟩ (.ternary (.literal (.boolean false))
    (.external "missing") (.literal (.nat 7))) = .ok (.nat 7) := by rfl

end GolemEval
