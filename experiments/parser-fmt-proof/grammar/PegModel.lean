namespace PegModel

-- The constructors match Peg.Grammar.Expr in the pinned peg-hs release.
-- Haskell actions remain source text. Numeric arguments, boolean predicates,
-- and the bound repetition length handled below have limited semantics;
-- recognition alone does not prove the action's AST or every value.
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

abbrev Params := List (String × Nat)

def atom (env : Params) (source : String) : Option Nat :=
  source.toNat?.orElse (fun _ => (env.find? (fun pair => pair.1 == source)).map Prod.snd)

def integer (env : Params) (source : String) : Option Nat :=
  match source.splitOn " + " with
  | [name, offset] => do
      let base ← atom env name
      let delta ← offset.toNat?
      some (base + delta)
  | _ =>
      match source.splitOn " - " with
      | [name, offset] => do
          let base ← atom env name
          let delta ← offset.toNat?
          if delta ≤ base then some (base - delta) else none
      | _ => atom env source

def predicate (env : Params) (source : String) : Option Bool :=
  match source.trim with
  | "True" => some true
  | "False" => some false
  | condition =>
      match condition.splitOn " == " with
      | [left, right] => do
          let a ← integer env left
          let b ← integer env right
          some (a == b)
      | _ => none

def directSuffix (name : String) (alt : Alt) : Option (List Expr) :=
  match alt.items with
  | .ref target [] :: suffix => if target == name then some suffix else none
  | _ => none

def runSequence (parse : Params → Expr → List Char → ParseResult)
    (boundLength : Params → Expr → List Char → Except String (Option Nat))
    (env : Params) (items : List Expr) (input : List Char) : ParseResult :=
  (items.foldlM (fun state item =>
    match state with
    | none => pure none
    | some (rest, scope) => do
        match parse scope item rest with
        | .error reason => Except.error reason
        | .ok none => pure none
        | .ok (some next) =>
            match item with
            | .bind (some name) _ =>
                match boundLength scope item rest with
                | .error reason => Except.error reason
                | .ok none => pure (some (next, scope))
                | .ok (some value) => pure (some (next, (name, value) :: scope))
            | _ => pure (some (next, scope))) (some (input, env)) :
      Except String (Option (List Char × Params))).map (Option.map Prod.fst)

def foldChoice {α β : Type} (parse : α → Except String (Option β))
    (alts : List α) : Except String (Option β) :=
  alts.foldlM (fun found items =>
    match found with
    | some _ => pure found
    | none => parse items) none

def runChoices (sequence : List Expr → ParseResult) (alts : List (List Expr)) : ParseResult :=
  foldChoice sequence alts

-- A bounded recognizer for the PEG operators. Unsupported Haskell expressions
-- and template calls are errors, never accepted input. Fuel exhaustion is
-- distinct from an ordinary PEG failure.
def recognizeEnv (grammar : Grammar) (env : Params) : Nat → Expr → List Char → ParseResult
  | 0, _, _ => .error "fuel exhausted"
  | fuel + 1, expr, input => Id.run do
      let boundLength (scope : Params) (item : Expr) (before : List Char) : Except String (Option Nat) := Id.run do
        match item with
        | .bind (some _) (.ref target args) =>
            match grammar.rules.find? (fun rule => rule.name == target) with
            | none => return .ok none
            | some rule =>
                match args.mapM (integer scope), rule.alts with
                | some values, [alt] =>
                    match alt.items with
                    | leading :: .bind (some captured) (.plus child) :: _ =>
                        if alt.action.map String.trim != some ("length " ++ captured) then return .ok none
                        let params := List.zip rule.params values
                        match recognizeEnv grammar params fuel leading before with
                        | .error reason => return .error reason
                        | .ok none => return .error "bound length prefix failed"
                        | .ok (some start) =>
                            let counted := (List.range fuel).foldl (fun (state : Except String (List Char × Nat × Bool)) _ =>
                              match state with
                              | .error reason => .error reason
                              | .ok (rest, count, true) => .ok (rest, count, true)
                              | .ok (rest, count, false) =>
                                  match recognizeEnv grammar params fuel child rest with
                                  | .error reason => .error reason
                                  | .ok none => .ok (rest, count, true)
                                  | .ok (some next) =>
                                      if next.length < rest.length then .ok (next, count + 1, false)
                                      else .error "zero-width repetition") (.ok (start, 0, false))
                            match counted with
                            | .error reason => return .error reason
                            | .ok (_, count, true) => return .ok (some count)
                            | .ok _ => return .error "fuel exhausted"
                    | _ => return .ok none
                | _, _ => return .ok none
        | _ => return .ok none
      let parseItem : Params → Expr → List Char → ParseResult :=
        fun scope item rest => recognizeEnv grammar scope fuel item rest
      let sequence : List Expr → ParseResult :=
        fun items => runSequence parseItem boundLength env items input
      let alternatives : List (List Expr) → ParseResult := runChoices sequence
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
          match grammar.rules.find? (fun rule => rule.name == name) with
          | none => return .error s!"unknown rule {name}"
          | some rule =>
              if !rule.templateParams.isEmpty then return .error s!"template rule {name}"
              if args.length != rule.params.length then return .error s!"argument count for {name}"
              match args.mapM (integer env) with
              | none => return .error s!"opaque argument for {name}"
              | some values =>
                  let bindings := List.zip rule.params values
                  let recursive := rule.alts.filterMap (directSuffix name)
                  if recursive.isEmpty then
                    return recognizeEnv grammar bindings fuel (.choice (rule.alts.map Alt.items)) input
                  let bases := rule.alts.filter (fun alt => (directSuffix name alt).isNone)
                  let seed := recognizeEnv grammar bindings fuel (.choice (bases.map Alt.items)) input
                  let grown := (List.range fuel).foldl (fun (state : ParseResult × Bool) _ =>
                    if state.2 then state else
                      match state.1 with
                      | .error _ => (state.1, true)
                      | .ok none => (state.1, true)
                      | .ok (some rest) =>
                          match recognizeEnv grammar bindings fuel (.choice recursive) rest with
                          | .error reason => (.error reason, true)
                          | .ok none => (state.1, true)
                          | .ok (some next) =>
                              if next.length < rest.length then (.ok (some next), false)
                              else (.error "zero-width left recursion", true)) (seed, false)
                  return if grown.2 then grown.1 else .error "fuel exhausted"
      | .choice alts => return alternatives alts
      | .star child =>
          match recognizeEnv grammar env fuel child input with
          | .error reason => return .error reason
          | .ok none => return .ok (some input)
          | .ok (some rest) =>
              if rest.length < input.length then return recognizeEnv grammar env fuel (.star child) rest
              return .error "zero-width repetition"
      | .plus child =>
          match recognizeEnv grammar env fuel child input with
          | .error reason => return .error reason
          | .ok none => return .ok none
          | .ok (some rest) =>
              if rest.length < input.length then return recognizeEnv grammar env fuel (.star child) rest
              return .error "zero-width repetition"
      | .opt child =>
          match recognizeEnv grammar env fuel child input with
          | .error reason => return .error reason
          | .ok none => return .ok (some input)
          | .ok hit => return .ok hit
      | .andPred child =>
          match recognizeEnv grammar env fuel child input with
          | .error reason => return .error reason
          | .ok none => return .ok none
          | .ok (some _) => return .ok (some input)
      | .notPred child =>
          match recognizeEnv grammar env fuel child input with
          | .error reason => return .error reason
          | .ok none => return .ok (some input)
          | .ok (some _) => return .ok none
      | .capture child => return recognizeEnv grammar env fuel child input
      | .label child _ => return recognizeEnv grammar env fuel child input
      | .discard child => return recognizeEnv grammar env fuel child input
      | .bind _ child => return recognizeEnv grammar env fuel child input
      | .semanticPred positive source =>
          match predicate env source with
          | none => return .error "opaque semantic predicate"
          | some hit => return .ok (if hit == positive then some input else none)
      | .template name _ _ => return .error s!"opaque template {name}"

def recognize (grammar : Grammar) (fuel : Nat) (expr : Expr) (input : List Char) : ParseResult :=
  recognizeEnv grammar [] fuel expr input

def recognizeStart (grammar : Grammar) (fuel : Nat) (input : List Char) : ParseResult :=
  recognize grammar fuel (.ref grammar.start []) input

end PegModel
