import Generated

namespace PegModelTest

private theorem prefix_self_append (xs ys : List Char) : xs.isPrefixOf (xs ++ ys) = true := by
  induction xs with
  | nil => simp [List.isPrefixOf]
  | cons _ rest ih => simp [List.isPrefixOf, ih]

private theorem drop_self_append (xs ys : List Char) : (xs ++ ys).drop xs.length = ys := by
  induction xs with
  | nil => simp
  | cons _ rest ih => simpa using ih

-- The interpretation of an arbitrary literal consumes exactly its printed
-- characters and leaves the following input unchanged.
theorem literal_roundtrip (grammar : PegModel.Grammar) (value written : String)
    (rest : List Char) (fuel : Nat) :
    PegModel.recognize grammar (fuel + 1) (.lit value written) (value.toList ++ rest) =
      .ok (some rest) := by
  simp [PegModel.recognize, PegModel.recognizeEnv, prefix_self_append, drop_self_append, Id.run]
  rfl

theorem literal_production_count : Generated.literalProductions.length = 23 := by rfl

theorem class_plus_production_count : Generated.classPlusProductions.length = 2 := by rfl

theorem optional_ref_production_count : Generated.optionalRefProductions.length = 1 := by rfl

theorem alias_production_count : Generated.aliasProductions.length = 1 := by rfl

theorem ordered_literal_production_count : Generated.orderedLiteralProductions.length = 4 := by rfl

theorem class_hit (grammar : PegModel.Grammar) (ranges : List (Nat × Nat))
    (written : String) (c : Char) (rest : List Char) (fuel : Nat)
    (hit : ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = true) :
    PegModel.recognizeEnv grammar [] (fuel + 1) (.charClass ranges written) (c :: rest) =
      .ok (some rest) := by
  simp [PegModel.recognizeEnv, hit, Id.run]
  rfl

theorem class_star_roundtrip (grammar : PegModel.Grammar) (ranges : List (Nat × Nat))
    (written : String) (xs : List Char)
    (all : ∀ c ∈ xs, ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = true) :
    PegModel.recognizeEnv grammar [] (xs.length + 2) (.star (.charClass ranges written))
      xs = .ok (some []) := by
  induction xs with
  | nil =>
      rfl
  | cons c tail ih =>
      rw [PegModel.recognizeEnv]
      simp only [List.length_cons]
      have hit := class_hit grammar ranges written c tail (tail.length + 1) (all c (by simp))
      rw [hit]
      have tailAll : ∀ x ∈ tail, ranges.any (fun (lo, hi) => lo ≤ x.toNat && x.toNat ≤ hi) = true := by
        intro x hx
        exact all x (by simp [hx])
      simp [ih tailAll, Id.run]

theorem class_plus_roundtrip (grammar : PegModel.Grammar) (ranges : List (Nat × Nat))
    (written : String) (first : Char) (tail : List Char)
    (firstHit : ranges.any (fun (lo, hi) => lo ≤ first.toNat && first.toNat ≤ hi) = true)
    (tailHit : ∀ c ∈ tail, ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = true) :
    PegModel.recognizeEnv grammar [] (tail.length + 3) (.plus (.charClass ranges written))
      (first :: tail) = .ok (some []) := by
  have hit : PegModel.recognizeEnv grammar [] (tail.length + 2) (.charClass ranges written)
      (first :: tail) = .ok (some tail) := by
    simpa [Nat.add_assoc] using class_hit grammar ranges written first tail (tail.length + 1) firstHit
  change (match PegModel.recognizeEnv grammar [] (tail.length + 2) (.charClass ranges written)
      (first :: tail) with
    | .error reason => Except.error reason
    | .ok none => Except.ok none
    | .ok (some rest) =>
        if rest.length < (first :: tail).length then
          PegModel.recognizeEnv grammar [] (tail.length + 2) (.star (.charClass ranges written)) rest
        else Except.error "zero-width repetition") = .ok (some [])
  rw [hit]
  simp [class_star_roundtrip grammar ranges written tail tailHit]

theorem class_star_boundary (grammar : PegModel.Grammar) (ranges : List (Nat × Nat))
    (written : String) (xs rest : List Char)
    (all : ∀ c ∈ xs, ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = true)
    (boundary : PegModel.recognizeEnv grammar [] 1 (.charClass ranges written) rest = .ok none) :
    PegModel.recognizeEnv grammar [] (xs.length + 2) (.star (.charClass ranges written))
      (xs ++ rest) = .ok (some rest) := by
  induction xs with
  | nil =>
      simp only [List.length_nil, Nat.zero_add, List.nil_append]
      change (match PegModel.recognizeEnv grammar [] 1 (.charClass ranges written) rest with
        | .error reason => Except.error reason
        | .ok none => Except.ok (some rest)
        | .ok (some next) =>
            if next.length < rest.length then
              PegModel.recognizeEnv grammar [] 1 (.star (.charClass ranges written)) next
            else Except.error "zero-width repetition") = .ok (some rest)
      rw [boundary]
  | cons c tail ih =>
      have hit : PegModel.recognizeEnv grammar [] (tail.length + 2) (.charClass ranges written)
          (c :: tail ++ rest) = .ok (some (tail ++ rest)) := by
        simpa [Nat.add_assoc] using class_hit grammar ranges written c (tail ++ rest)
          (tail.length + 1) (all c (by simp))
      have tailAll : ∀ x ∈ tail, ranges.any (fun (lo, hi) => lo ≤ x.toNat && x.toNat ≤ hi) = true := by
        intro x hx
        exact all x (by simp [hx])
      simp only [List.length_cons, Nat.succ_eq_add_one, Nat.add_assoc]
      change (match PegModel.recognizeEnv grammar [] (tail.length + 2) (.charClass ranges written)
          (c :: tail ++ rest) with
        | .error reason => Except.error reason
        | .ok none => Except.ok (some (c :: tail ++ rest))
        | .ok (some next) =>
            if next.length < (c :: tail ++ rest).length then
              PegModel.recognizeEnv grammar [] (tail.length + 2) (.star (.charClass ranges written)) next
            else Except.error "zero-width repetition") = .ok (some rest)
      rw [hit]
      simp [ih tailAll, Id.run]

theorem class_plus_boundary (grammar : PegModel.Grammar) (ranges : List (Nat × Nat))
    (written : String) (first : Char) (tail rest : List Char)
    (firstHit : ranges.any (fun (lo, hi) => lo ≤ first.toNat && first.toNat ≤ hi) = true)
    (tailHit : ∀ c ∈ tail, ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = true)
    (boundary : PegModel.recognizeEnv grammar [] 1 (.charClass ranges written) rest = .ok none) :
    PegModel.recognizeEnv grammar [] (tail.length + 3) (.plus (.charClass ranges written))
      (first :: tail ++ rest) = .ok (some rest) := by
  have hit : PegModel.recognizeEnv grammar [] (tail.length + 2) (.charClass ranges written)
      (first :: tail ++ rest) = .ok (some (tail ++ rest)) := by
    simpa [Nat.add_assoc] using class_hit grammar ranges written first (tail ++ rest)
      (tail.length + 1) firstHit
  change (match PegModel.recognizeEnv grammar [] (tail.length + 2) (.charClass ranges written)
      (first :: tail ++ rest) with
    | .error reason => Except.error reason
    | .ok none => Except.ok none
    | .ok (some next) =>
        if next.length < (first :: tail ++ rest).length then
          PegModel.recognizeEnv grammar [] (tail.length + 2) (.star (.charClass ranges written)) next
        else Except.error "zero-width repetition") = .ok (some rest)
  rw [hit]
  simp [class_star_boundary grammar ranges written tail rest tailHit boundary]

example : PegModel.recognize Generated.pegGrammar 12 (.ref "Ws" []) " \t!".toList =
    .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 12 (.ref "Sp" []) "!".toList =
    .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 12 (.ref "Sp" []) " \t!".toList =
    .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 12 (.ref "Lang" []) "en-US!".toList =
    .ok (some "!".toList) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 300 "```en-US\nx\n```\n".toList =
    .ok (some []) := by rfl

example : PegModel.recognize Generated.pegGrammar 4 (.ref "Nl" []) "\nx".toList =
    .ok (some "x".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 4 (.ref "Fence" []) "```x".toList =
    .ok (some "x".toList) := by rfl

theorem ordered_choice_first (grammar : PegModel.Grammar) (value written : String)
    (later : List PegModel.Expr) (input rest : List Char) (fuel : Nat)
    (hit : PegModel.recognize grammar fuel (.lit value written) input = .ok (some rest)) :
    PegModel.recognize grammar (fuel + 1) (.choice [[.lit value written], later]) input =
      .ok (some rest) := by
  simp only [PegModel.recognize] at hit ⊢
  simp [PegModel.recognizeEnv, PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, hit, Id.run]
  rfl

theorem ordered_choice_fallback (grammar : PegModel.Grammar)
    (firstValue firstWritten secondValue secondWritten : String) (input rest : List Char) (fuel : Nat)
    (miss : PegModel.recognize grammar fuel (.lit firstValue firstWritten) input = .ok none)
    (hit : PegModel.recognize grammar fuel (.lit secondValue secondWritten) input = .ok (some rest)) :
    PegModel.recognize grammar (fuel + 1)
      (.choice [[.lit firstValue firstWritten], [.lit secondValue secondWritten]]) input =
      .ok (some rest) := by
  simp only [PegModel.recognize] at miss hit ⊢
  simp [PegModel.recognizeEnv, PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, miss, hit, Id.run]
  rfl

theorem optional_hit (grammar : PegModel.Grammar) (child : PegModel.Expr)
    (input rest : List Char) (fuel : Nat)
    (hit : PegModel.recognizeEnv grammar [] fuel child input = .ok (some rest)) :
    PegModel.recognizeEnv grammar [] (fuel + 1) (.opt child) input =
      .ok (some rest) := by
  change (match PegModel.recognizeEnv grammar [] fuel child input with
    | .error reason => Except.error reason
    | .ok none => Except.ok (some input)
    | .ok found => Except.ok found) = .ok (some rest)
  rw [hit]

theorem optional_miss (grammar : PegModel.Grammar) (child : PegModel.Expr)
    (input : List Char) (fuel : Nat)
    (miss : PegModel.recognizeEnv grammar [] fuel child input = .ok none) :
    PegModel.recognizeEnv grammar [] (fuel + 1) (.opt child) input =
      .ok (some input) := by
  change (match PegModel.recognizeEnv grammar [] fuel child input with
    | .error reason => Except.error reason
    | .ok none => Except.ok (some input)
    | .ok found => Except.ok found) = .ok (some input)
  rw [miss]

theorem single_ref_hit (grammar : PegModel.Grammar) (name : String)
    (input rest : List Char) (fuel : Nat)
    (hit : PegModel.recognizeEnv grammar [] fuel (.ref name []) input = .ok (some rest)) :
    PegModel.recognizeEnv grammar [] (fuel + 1) (.choice [[.ref name []]]) input =
      .ok (some rest) := by
  simp [PegModel.recognizeEnv, PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, hit, Id.run]
  rfl

theorem single_ref_miss (grammar : PegModel.Grammar) (name : String)
    (input : List Char) (fuel : Nat)
    (miss : PegModel.recognizeEnv grammar [] fuel (.ref name []) input = .ok none) :
    PegModel.recognizeEnv grammar [] (fuel + 1) (.choice [[.ref name []]]) input =
      .ok none := by
  simp [PegModel.recognizeEnv, PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, miss, Id.run]
  rfl

private theorem fold_keeps_hit {α β : Type} (xs : List α) (f : α → Option β)
    (value : β) :
    xs.foldlM (fun found item =>
      match found with
      | some _ => pure found
      | none => pure (f item)) (some value) =
        (Except.ok (some value) : Except String (Option β)) := by
  induction xs with
  | nil => rfl
  | cons _ tail ih => simpa [List.foldlM] using ih

private theorem fold_keeps_hit_parse {α β : Type} (xs : List α)
    (parse : α → Except String (Option β)) (value : β) :
    xs.foldlM (fun found item =>
      match found with
      | some _ => pure found
      | none => parse item) (some value) =
        (Except.ok (some value) : Except String (Option β)) := by
  induction xs with
  | nil => rfl
  | cons _ tail ih => simpa [List.foldlM] using ih

private theorem first_success {α β : Type} (xs : List α) (f : α → Option β) :
    xs.foldlM (fun found item =>
      match found with
      | some _ => pure found
      | none => pure (f item)) none =
        (Except.ok (xs.findSome? f) : Except String (Option β)) := by
  induction xs with
  | nil => rfl
  | cons head tail ih =>
      cases hit : f head with
      | none => simpa [List.foldlM, List.findSome?, hit] using ih
      | some value =>
          simpa [List.foldlM, List.findSome?, hit] using fold_keeps_hit tail f value

private theorem fold_choice_spec {α β : Type} (xs : List α)
    (parse : α → Except String (Option β)) (f : α → Option β)
    (matchesAll : ∀ x ∈ xs, parse x = .ok (f x)) :
    PegModel.foldChoice parse xs =
        (Except.ok (xs.findSome? f) : Except String (Option β)) := by
  unfold PegModel.foldChoice
  induction xs with
  | nil => rfl
  | cons head tail ih =>
      have headMatch := matchesAll head (by simp)
      have tailMatch : ∀ x ∈ tail, parse x = .ok (f x) := by
        intro x hx
        exact matchesAll x (by simp [hx])
      cases hit : f head with
      | none => simpa [List.foldlM, List.findSome?, headMatch, hit] using ih tailMatch
      | some value =>
          have keep := fold_keeps_hit_parse tail parse value
          simpa [List.foldlM, List.findSome?, headMatch, hit] using keep

private theorem run_sequence_literal (parse : PegModel.Params → PegModel.Expr → List Char → PegModel.ParseResult)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (env : PegModel.Params) (value written : String) (input : List Char) :
    PegModel.runSequence parse boundLength env [.lit value written] input =
      parse env (.lit value written) input := by
  cases hit : parse env (.lit value written) input with
  | error reason => simp [PegModel.runSequence, hit]; rfl
  | ok result =>
      cases result with
      | none => simp [PegModel.runSequence, hit]; rfl
      | some rest => simp [PegModel.runSequence, hit]; rfl

def literalItems (items : List PegModel.Expr) (input : List Char) : Option (List Char) :=
  match items with
  | [.lit value _] => if value.toList.isPrefixOf input then some (input.drop value.toList.length) else none
  | _ => none

def literalAlternatives (alts : List (String × String)) : List (List PegModel.Expr) :=
  alts.map (fun (value, written) => [.lit value written])

def firstLiteral (alts : List (String × String)) (input : List Char) : Option (List Char) :=
  (literalAlternatives alts).findSome? (literalItems · input)

theorem run_literal_choices (parse : PegModel.Params → PegModel.Expr → List Char → PegModel.ParseResult)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (env : PegModel.Params) (alts : List (String × String)) (input : List Char)
    (literalHit : ∀ value written,
      parse env (.lit value written) input = .ok (literalItems [.lit value written] input)) :
    PegModel.runChoices (fun items => PegModel.runSequence parse boundLength env items input)
      (literalAlternatives alts) = .ok (firstLiteral alts input) := by
  have allItems : ∀ items ∈ literalAlternatives alts,
      PegModel.runSequence parse boundLength env items input = .ok (literalItems items input) := by
    intro items member
    rcases List.mem_map.mp member with ⟨pair, _, rfl⟩
    cases pair with
    | mk value written => simpa [literalAlternatives] using
        (run_sequence_literal parse boundLength env value written input).trans (literalHit value written)
  unfold PegModel.runChoices firstLiteral
  exact fold_choice_spec (literalAlternatives alts)
    (fun items => PegModel.runSequence parse boundLength env items input)
    (fun items => literalItems items input) allItems

theorem interpreted_literal_choices (grammar : PegModel.Grammar) (env : PegModel.Params)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (alts : List (String × String)) (input : List Char) (fuel : Nat) :
    PegModel.runChoices
      (fun items => PegModel.runSequence
        (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 1) item rest)
        boundLength env items input)
      (literalAlternatives alts) = .ok (firstLiteral alts input) := by
  apply run_literal_choices
  intro value written
  simp [PegModel.recognizeEnv, literalItems, Id.run]
  rfl

-- The terminal branch of EOL is a negative lookahead for any character.
-- It succeeds exactly at EOF and consumes nothing, regardless of the grammar.
theorem eof_lookahead (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 2) (.notPred .any) input =
      .ok (if input.isEmpty then some input else none) := by
  cases input with
  | nil => rfl
  | cons _ _ => rfl

-- This proves the literal/EOF choice in isolation. EOL uses a reference to
-- Nl, so this theorem does not yet discharge EOL's generated AST choice.
set_option maxHeartbeats 1000000 in
theorem newline_or_eof (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 3)
      (.choice [[.lit "\n" "'\\n'"], [.notPred .any]]) input =
      .ok (match input with
        | [] => some []
        | '\n' :: rest => some rest
        | _ :: _ => none) := by
  cases input with
  | nil => rfl
  | cons c rest =>
      by_cases h : c = '\n'
      · subst c
        simp [PegModel.recognizeEnv, PegModel.runChoices, PegModel.foldChoice,
          PegModel.runSequence, Id.run, List.isPrefixOf, List.drop, Except.map, Except.bind]
        rfl
      · have hc : '\n' ≠ c := Ne.symm h
        simp [PegModel.recognizeEnv, PegModel.runChoices, PegModel.foldChoice,
          PegModel.runSequence, Id.run, List.isPrefixOf, h, hc, Except.map, Except.bind]
        rfl

theorem generated_nl_ast :
    (Generated.pegGrammar.rules.find? (fun rule => rule.name == "Nl")).map
      (fun rule => rule.alts.map PegModel.Alt.items) =
      some [[.lit "\n" "'\\n'"]] := by rfl

theorem generated_eol_ast :
    (Generated.pegGrammar.rules.find? (fun rule => rule.name == "EOL")).map
      (fun rule => rule.alts.map PegModel.Alt.items) =
      some [[.ref "Sp" [], .choice [[.ref "Nl" []], [.notPred .any]]]] := by rfl

example : PegModel.recognize Generated.pegGrammar 8 (.ref "HashMark" []) "######!".toList =
    .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 8 (.ref "HashMark" []) "##!".toList =
    .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 8 (.ref "Splat" []) "**[!".toList =
    .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 8 (.ref "CmpOp" []) ">=!".toList =
    .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 8 (.ref "AddOp" []) "+!".toList =
    .ok (some "!".toList) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 300 "@set x = 1+2\n".toList =
    .ok (some []) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 300 "[= 1>=0]\n".toList =
    .ok (some []) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 300 "[foo *[1]]\n".toList =
    .ok (some []) := by rfl

theorem repeated_a_roundtrip (grammar : PegModel.Grammar) (count : Nat) :
    PegModel.recognizeEnv grammar [] (count + 2) (.star (.lit "a" "'a'"))
      (List.replicate count 'a') = .ok (some []) := by
  induction count with
  | zero => rfl
  | succ n ih =>
      rw [PegModel.recognizeEnv]
      simp only [List.replicate]
      have hit : PegModel.recognizeEnv grammar [] (n + 2) (.lit "a" "'a'")
          ('a' :: List.replicate n 'a') = .ok (some (List.replicate n 'a')) := by
        simp [PegModel.recognizeEnv, List.isPrefixOf, List.drop, Id.run]
        rfl
      rw [hit]
      simp [ih, Id.run]

-- These use the rule and ordered escape choice exported from Golem.hpeg.
example : PegModel.recognize Generated.pegGrammar 40 (.ref "StringLit" [])
    "\"a\\\"b\"!".toList = .ok (some ['!']) := by rfl

example : PegModel.recognize Generated.pegGrammar 44 (.ref "StringLiteral" [])
    "\"a\\\"b\"!".toList = .ok (some ['!']) := by rfl

example : PegModel.recognize Generated.pegGrammar 40 (.ref "StringLit" [])
    "\"a".toList = .ok none := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 50 [] = .ok (some []) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 100 "abc\n".toList =
    .ok (some []) := by rfl

-- The source PEG has direct left recursion in AddExpr and MulExpr.
example : PegModel.recognize Generated.pegGrammar 200 (.ref "AddExpr" [])
    "1!".toList = .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 200 (.ref "AddExpr" [])
    "1+2!".toList = .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 200 (.ref "AddExpr" [])
    "1+2*3!".toList = .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 200 (.ref "AddExpr" [])
    "1+!".toList = .ok (some "+!".toList) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 300 "@set x = 1\n".toList =
    .ok (some []) := by rfl

-- TableRow returns length cs, which the table passes as h to body rows.
example : PegModel.recognizeStart Generated.pegGrammar 300
    "| a |\n|---|\n".toList = .ok (some []) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 300
    "| a |\n|---|\n| b |\n".toList = .ok (some []) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 300
    "| a | b |\n|---|---|\n| c | d |\n".toList = .ok (some []) := by rfl

-- Ind(n) consumes exactly n spaces; these are the parameter boundary cases.
example : PegModel.integer [("ind", 1)] "ind + 2" = some 3 := by rfl

example : PegModel.integer [("n", 0)] "n - 1" = none := by rfl

example : PegModel.predicate [("ordered", 1)] " ordered == 1 " = some true := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" ["0"])
    "x".toList = .ok (some "x".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" ["1"])
    " x".toList = .ok (some "x".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" ["2"])
    " x".toList = .ok none := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" ["2"])
    "  x".toList = .ok (some "x".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" [])
    "x".toList = .error "argument count for Ind" := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" ["unknown"])
    "x".toList = .error "opaque argument for Ind" := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "ListMark" ["0"])
    "-x".toList = .ok (some "x".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "ListMark" ["1"])
    "+x".toList = .ok (some "x".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "ListMark" ["1"])
    "-x".toList = .ok none := by rfl

-- Supported Haskell boolean predicates preserve positive and negative tests.
example : PegModel.recognize Generated.pegGrammar 2
    (.semanticPred true " True ") [] = .ok (some []) := by rfl

example : PegModel.recognize Generated.pegGrammar 2
    (.semanticPred false " False ") [] = .ok (some []) := by rfl

example : PegModel.recognize Generated.pegGrammar 2
    (.semanticPred true " False ") [] = .ok none := by rfl

example : PegModel.recognize Generated.pegGrammar 2
    (.semanticPred true " r == h ") [] = .error "opaque semantic predicate" := by rfl

end PegModelTest
