/- A finite evaluation model for Golem ADR 0351, invariant 5.
   The environment and step budget are explicit; source comments and layout
   are absent from the expression passed to evaluation. -/
namespace GolemEval

inductive Value where
  | nat : Nat → Value
  | string : String → Value
  deriving DecidableEq, Repr

inductive Expr where
  | literal : Value → Expr
  | variable : String → Expr
  | add : Expr → Expr → Expr
  | append : Expr → Expr → Expr
  | external : String → Expr
  | call : String → Expr → Expr → Expr
  deriving DecidableEq, Repr

inductive Failure where
  | unknownName | missingFile | typeError | overLimit
  deriving DecidableEq, Repr

structure Environment where
  variables : List (String × Value)
  files : List (String × String)
  deriving Repr

def lookup (bindings : List (String × α)) (name : String) : Option α :=
  (bindings.find? (fun entry => entry.1 == name)).map Prod.snd

def eval : Nat → Environment → Expr → Except Failure Value
  | 0, _, _ => .error .overLimit
  | _ + 1, _, .literal value => .ok value
  | _ + 1, env, .variable name =>
      match lookup env.variables name with
      | some value => .ok value
      | none => .error .unknownName
  | _ + 1, env, .external path =>
      match lookup env.files path with
      | some value => .ok (.string value)
      | none => .error .missingFile
  | fuel + 1, env, .add left right => do
      let x ← eval fuel env left
      let y ← eval fuel env right
      match x, y with
      | .nat a, .nat b => .ok (.nat (a + b))
      | _, _ => .error .typeError
  | fuel + 1, env, .append left right => do
      let x ← eval fuel env left
      let y ← eval fuel env right
      match x, y with
      | .string a, .string b => .ok (.string (a ++ b))
      | _, _ => .error .typeError
  | fuel + 1, env, .call name argument body => do
      let value ← eval fuel env argument
      eval fuel { env with variables := (name, value) :: env.variables } body

/- Formatting changes only layout and comments. The parser erases those
   annotations before evaluation, as in the Haskell parser and checker. -/
structure SourceExpr where
  expression : Expr
  layout : String
  comments : List String

def parsed (source : SourceExpr) : Expr := source.expression

def format (source : SourceExpr) : SourceExpr :=
  { source with layout := "canonical" }

/- A derivation records how a successful value is obtained, including
   argument evaluation and the body of a user function. -/
inductive Derives : Nat → Environment → Expr → Value → Prop where
  | literal : Derives (fuel + 1) env (.literal value) value
  | variable (found : lookup env.variables name = some value) :
      Derives (fuel + 1) env (.variable name) value
  | external (found : lookup env.files path = some value) :
      Derives (fuel + 1) env (.external path) (.string value)
  | add (left : Derives fuel env a (.nat x))
        (right : Derives fuel env b (.nat y)) :
      Derives (fuel + 1) env (.add a b) (.nat (x + y))
  | append (left : Derives fuel env a (.string x))
        (right : Derives fuel env b (.string y)) :
      Derives (fuel + 1) env (.append a b) (.string (x ++ y))
  | call (argument : Derives fuel env a value)
         (body : Derives fuel { env with variables := (name, value) :: env.variables } b result) :
      Derives (fuel + 1) env (.call name a b) result

theorem derives_sound {fuel : Nat} {env : Environment} {expression : Expr}
    {value : Value} (derivation : Derives fuel env expression value) :
    eval fuel env expression = .ok value := by
  induction derivation <;> simp_all [eval, Except.bind] <;> try rfl
  case call _ _ argumentSound bodySound =>
    simpa only [Except.bind] using bodySound

theorem I5_eval_format (fuel : Nat) (env : Environment) (source : SourceExpr) :
    eval fuel env (parsed (format source)) = eval fuel env (parsed source) := by
  rfl

theorem I5_derivation_format (fuel : Nat) (env : Environment)
    (source : SourceExpr) (value : Value)
    (derivation : Derives fuel env (parsed source) value) :
    Derives fuel env (parsed (format source)) value := by
  simpa [parsed, format] using derivation

example : eval 3 ⟨[("x", .nat 2)], []⟩ (.add (.variable "x") (.literal (.nat 3)))
    = .ok (.nat 5) := by rfl

example : eval 3 ⟨[("x", .string "a")], []⟩ (.add (.variable "x") (.literal (.nat 3)))
    = .error .typeError := by rfl

example : eval 3 ⟨[], []⟩ (.call "x" (.literal (.nat 2))
    (.add (.variable "x") (.literal (.nat 3)))) = .ok (.nat 5) := by rfl

example : eval 1 ⟨[], []⟩ (.add (.literal (.nat 2)) (.literal (.nat 3)))
    = .error .overLimit := by rfl

example : eval 2 ⟨[], []⟩ (.add (.literal (.nat 2)) (.literal (.nat 3)))
    = .ok (.nat 5) := by rfl

example : eval 2 ⟨[], [("data/a.tsv", "a")]⟩
    (.append (.external "data/a.tsv") (.literal (.string "b")))
    = .ok (.string "ab") := by rfl

example : eval 1 ⟨[], []⟩ (.external "data/a.tsv")
    = .error .missingFile := by rfl

end GolemEval
