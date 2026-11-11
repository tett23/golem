namespace PegModel

-- The constructors match Peg.Grammar.Expr in the pinned peg-hs release.
-- Haskell actions and predicates remain source text until their semantics are
-- modeled. Recognition alone does not prove the action's AST or value.
inductive Expr where
  | lit (value written : String)
  | charClass (ranges : List (Nat × Nat)) (written : String)
  | any
  | ref (name : String) (args : List String)
  | choice (alts : List (List Expr))
  | star (child : Expr)
  | plus (child : Expr)
  | opt (child : Expr)
  | andPred (child : Expr)
  | notPred (child : Expr)
  | capture (child : Expr)
  | label (child : Expr) (name : String)
  | semanticPred (positive : Bool) (source : String)
  | template (name : String) (children : List Expr) (args : List String)
  | discard (child : Expr)
  | bind (name : Option String) (child : Expr)
  deriving Repr, Inhabited

structure Alt where
  line : Nat
  items : List Expr
  action : Option String
  constructor : Option String
  deriving Repr, Inhabited

structure Rule where
  name : String
  line : Nat
  params : List String
  templateParams : List String
  resultType : String
  alts : List Alt
  deriving Repr, Inhabited

structure Grammar where
  start : String
  tokens : List String
  trivia : List String
  inline : List String
  rules : List Rule
  deriving Repr, Inhabited

abbrev ParseResult := Except String (Option (List Char))

-- A bounded recognizer for the PEG operators.  An opaque Haskell predicate,
-- a template call or a parameterized rule is an error, never an accepted
-- input.  Fuel exhaustion is distinct from an ordinary PEG failure.
def recognize (grammar : Grammar) : Nat → Expr → List Char → ParseResult
  | 0, _, _ => .error "fuel exhausted"
  | fuel + 1, expr, input => Id.run do
      let sequence (items : List Expr) : ParseResult :=
        items.foldlM (fun state item =>
          match state with
          | none => pure none
          | some rest => recognize grammar fuel item rest) (some input)
      let alternatives (alts : List (List Expr)) : ParseResult :=
        alts.foldlM (fun found items =>
          match found with
          | some _ => pure found
          | none => sequence items) none
      match expr with
      | .lit value _ =>
          let chars := value.toList
          return pure (if chars.isPrefixOf input then some (input.drop chars.length) else none)
      | .charClass ranges _ =>
          return pure (match input with
            | [] => none
            | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) then some rest else none)
      | .any => return pure (match input with | [] => none | _ :: rest => some rest)
      | .ref name args =>
          if !args.isEmpty then return .error s!"parameterized reference {name}"
          match grammar.rules.find? (fun rule => rule.name == name) with
          | none => return .error s!"unknown rule {name}"
          | some rule =>
              if !rule.params.isEmpty || !rule.templateParams.isEmpty then
                return .error s!"parameterized rule {name}"
              return recognize grammar fuel (.choice (rule.alts.map Alt.items)) input
      | .choice alts => return alternatives alts
      | .star child =>
          match recognize grammar fuel child input with
          | .error reason => return .error reason
          | .ok none => return .ok (some input)
          | .ok (some rest) =>
              if rest.length < input.length then return recognize grammar fuel (.star child) rest
              return .error "zero-width repetition"
      | .plus child =>
          match recognize grammar fuel child input with
          | .error reason => return .error reason
          | .ok none => return .ok none
          | .ok (some rest) =>
              if rest.length < input.length then return recognize grammar fuel (.star child) rest
              return .error "zero-width repetition"
      | .opt child =>
          match recognize grammar fuel child input with
          | .error reason => return .error reason
          | .ok none => return .ok (some input)
          | .ok hit => return .ok hit
      | .andPred child =>
          match recognize grammar fuel child input with
          | .error reason => return .error reason
          | .ok none => return .ok none
          | .ok (some _) => return .ok (some input)
      | .notPred child =>
          match recognize grammar fuel child input with
          | .error reason => return .error reason
          | .ok none => return .ok (some input)
          | .ok (some _) => return .ok none
      | .capture child => return recognize grammar fuel child input
      | .label child _ => return recognize grammar fuel child input
      | .discard child => return recognize grammar fuel child input
      | .bind _ child => return recognize grammar fuel child input
      | .semanticPred _ _ => return .error "opaque semantic predicate"
      | .template name _ _ => return .error s!"opaque template {name}"

def recognizeStart (grammar : Grammar) (fuel : Nat) (input : List Char) : ParseResult :=
  recognize grammar fuel (.ref grammar.start []) input

end PegModel
