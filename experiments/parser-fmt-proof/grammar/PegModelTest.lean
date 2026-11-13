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

private def firstResult {α β : Type} (parse : α → Except String (Option β)) :
    List α → Except String (Option β)
  | [] => .ok none
  | head :: tail =>
      match parse head with
      | .ok none => firstResult parse tail
      | result => result

theorem ordered_choice_preserves_error {α β : Type}
    (parse : α → Except String (Option β)) (alts : List α) :
    PegModel.foldChoice parse alts = firstResult parse alts := by
  induction alts with
  | nil => rfl
  | cons head tail ih =>
      cases hit : parse head with
      | error reason => simp [PegModel.foldChoice, firstResult, List.foldlM, hit]; rfl
      | ok result =>
          cases result with
          | none => simpa [PegModel.foldChoice, firstResult, List.foldlM, hit] using ih
          | some value =>
              simpa [PegModel.foldChoice, firstResult, List.foldlM, hit]
                using fold_keeps_hit_parse tail parse value

private theorem run_sequence_ref (parse : PegModel.Params → PegModel.Expr → List Char → PegModel.ParseResult)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (env : PegModel.Params) (name : String) (args : List String) (input : List Char) :
    PegModel.runSequence parse boundLength env [.ref name args] input =
      parse env (.ref name args) input := by
  cases hit : parse env (.ref name args) input with
  | error reason => simp [PegModel.runSequence, hit]; rfl
  | ok result =>
      cases result with
      | none => simp [PegModel.runSequence, hit]; rfl
      | some rest => simp [PegModel.runSequence, hit]; rfl

def refAlternatives (refs : List (String × List String)) : List (List PegModel.Expr) :=
  refs.map (fun (name, args) => [.ref name args])

theorem ordered_ref_choices (parse : PegModel.Params → PegModel.Expr → List Char → PegModel.ParseResult)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (env : PegModel.Params) (refs : List (String × List String)) (input : List Char) :
    PegModel.runChoices (fun items => PegModel.runSequence parse boundLength env items input)
      (refAlternatives refs) =
      firstResult (fun pair => parse env (.ref pair.1 pair.2) input) refs := by
  unfold PegModel.runChoices
  rw [ordered_choice_preserves_error]
  induction refs with
  | nil => rfl
  | cons pair tail ih =>
      cases pair with
      | mk name args =>
          simp only [refAlternatives, List.map, firstResult, run_sequence_ref]
          cases hit : parse env (.ref name args) input with
          | error _ => rfl
          | ok result =>
              cases result with
              | none => exact ih
              | some _ => rfl

theorem interpreted_ref_choices (grammar : PegModel.Grammar) (env : PegModel.Params)
    (refs : List (String × List String)) (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv grammar env (fuel + 1) (.choice (refAlternatives refs)) input =
      firstResult (fun pair => PegModel.recognizeEnv grammar env fuel
        (.ref pair.1 pair.2) input) refs := by
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope fuel item rest)
      _ env items input) (refAlternatives refs) = _
  exact ordered_ref_choices _ _ env refs input

private def leadingChoice (name : String) : Option PegModel.Expr := do
  let rule ← Generated.pegGrammar.rules.find? (fun r => r.name == name)
  let alt ← rule.alts.head?
  alt.items.head?

private def blockRefs : List (String × List String) :=
  ["Heading", "BulletList", "OrderedList", "DefList", "Table", "CodeBlock", "Paragraph"].map
    (fun name => (name, ["ind"]))

private def hashKeyRefs : List (String × List String) := [("ExprIdent", []), ("StringLit", [])]

/-- These are the exact nested choices to which interpreted_ref_choices applies.
    The enclosing label and each referenced rule retain their own obligations. -/
theorem generated_nested_ref_shapes :
    leadingChoice "AttributedBlock" = some (.choice (refAlternatives blockRefs)) ∧
    leadingChoice "HashEntry" = some (.choice (refAlternatives hashKeyRefs)) ∧
    leadingChoice "Block" = some (.label (.choice (refAlternatives
      ((["BadIndent", "OrphanDef", "ReservedBlock", "BlockGroup"].map
        (fun name => (name, ["ind"]))) ++ blockRefs))) "block") := by
  exact ⟨rfl, rfl, rfl⟩

theorem single_group (grammar : PegModel.Grammar) (env : PegModel.Params)
    (item : PegModel.Expr) (input : List Char) (fuel : Nat) (unbound : ∀ n e, item ≠ .bind (some n) e) :
    PegModel.recognizeEnv grammar env (fuel + 1) (.choice [[item]]) input =
      PegModel.recognizeEnv grammar env fuel item input := by
  change PegModel.runChoices (fun items => PegModel.runSequence
    (fun scope child rest => PegModel.recognizeEnv grammar scope fuel child rest)
    _ env items input) [[item]] = _
  cases hit : PegModel.recognizeEnv grammar env fuel item input with
  | error reason => simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, hit]; rfl
  | ok result =>
      cases result with
      | none => simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, hit]; rfl
      | some rest =>
          cases item <;> simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, hit] <;> try rfl

theorem attributed_block_dispatch (n : Nat) (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [("ind", n)] (fuel + 3)
      (.ref "AttributedBlock" ["ind"]) input =
      firstResult (fun pair => PegModel.recognizeEnv Generated.pegGrammar [("ind", n)] fuel
        (.ref pair.1 pair.2) input) blockRefs := by
  change PegModel.recognizeEnv Generated.pegGrammar [("ind", n)] (fuel + 2)
    (.choice [[.choice (refAlternatives blockRefs)]]) input = _
  rw [single_group _ _ _ _ (fuel + 1) (by simp)]
  exact interpreted_ref_choices _ _ _ _ _

private def allBlockRefs : List (String × List String) :=
  (["BadIndent", "OrphanDef", "ReservedBlock", "BlockGroup"].map
    (fun name => (name, ["ind"]))) ++ blockRefs

theorem block_dispatch (n : Nat) (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [("ind", n)] (fuel + 4)
      (.ref "Block" ["ind"]) input =
      match firstResult (fun pair => PegModel.recognizeEnv Generated.pegGrammar [("ind", n)] fuel
        (.ref pair.1 pair.2) input) allBlockRefs with
      | .ok none => .error "label: block"
      | result => result := by
  change PegModel.recognizeEnv Generated.pegGrammar [("ind", n)] (fuel + 3)
    (.choice [[.label (.choice (refAlternatives allBlockRefs)) "block"]]) input = _
  rw [single_group _ _ _ _ (fuel + 2) (by simp)]
  change (match PegModel.recognizeEnv Generated.pegGrammar [("ind", n)] (fuel + 1)
    (.choice (refAlternatives allBlockRefs)) input with
    | .ok none => Except.error "label: block"
    | result => result) = _
  rw [interpreted_ref_choices]
  rfl

example : PegModel.foldChoice
    (fun n : Nat => if n == 1 then (.error "label" : PegModel.ParseResult) else .ok none) [0, 1, 2] =
      .error "label" := by rfl

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

theorem single_literal_choice (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (value written : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 2) (.choice [[.lit value written]]) input =
      PegModel.recognizeEnv grammar env (fuel + 1) (.lit value written) input := by
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 1) item rest)
      _ env items input) [[.lit value written]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence]
  cases hit : PegModel.recognizeEnv grammar env (fuel + 1) (.lit value written) input with
  | error reason => simp [hit, Except.map]
  | ok result =>
      cases result with
      | none => simp [hit, Except.map]; rfl
      | some rest => simp [hit, Except.map]; rfl

theorem generated_nl_reference (env : PegModel.Params) (fuel : Nat) (input : List Char) :
    PegModel.recognizeEnv Generated.pegGrammar env (fuel + 4) (.ref "Nl" []) input =
      PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 2)
        (.lit "\n" "'\\n'") input := by
  calc
    _ = PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
      (.choice [[.lit "\n" "'\\n'"]]) input := by rfl
    _ = _ := single_literal_choice Generated.pegGrammar [] (fuel + 1) "\n" "'\\n'" input

theorem generated_nl_eval (env : PegModel.Params) (fuel : Nat) (input : List Char) :
    PegModel.recognizeEnv Generated.pegGrammar env (fuel + 4) (.ref "Nl" []) input =
      .ok (match input with
        | [] => none
        | '\n' :: rest => some rest
        | _ :: _ => none) := by
  rw [generated_nl_reference]
  cases input with
  | nil => rfl
  | cons c rest =>
      by_cases h : c = '\n'
      · subst c
        simp [PegModel.recognizeEnv, List.isPrefixOf, List.drop]
        rfl
      · have hc : '\n' ≠ c := Ne.symm h
        simp [PegModel.recognizeEnv, List.isPrefixOf, h, hc]
        rfl

theorem generated_newline_or_eof (env : PegModel.Params) (fuel : Nat) (input : List Char) :
    PegModel.recognizeEnv Generated.pegGrammar env (fuel + 6)
      (.choice [[.ref "Nl" []], [.notPred .any]]) input =
      .ok (match input with
        | [] => some []
        | '\n' :: rest => some rest
        | _ :: _ => none) := by
  have nl : PegModel.recognizeEnv Generated.pegGrammar env (fuel + 5)
      (.ref "Nl" []) input =
      .ok (match input with
        | [] => none
        | '\n' :: rest => some rest
        | _ :: _ => none) := by
    simpa [Nat.add_assoc] using generated_nl_eval env (fuel + 1) input
  have eof : PegModel.recognizeEnv Generated.pegGrammar env (fuel + 5)
      (.notPred .any) input =
      .ok (if input.isEmpty then some input else none) := by
    simpa [Nat.add_assoc] using eof_lookahead Generated.pegGrammar env (fuel + 3) input
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 5) item rest)
      _ env items input) [[.ref "Nl" []], [.notPred .any]] = _
  cases input with
  | nil => simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
      nl, eof, Except.map]; rfl
  | cons c rest =>
      by_cases h : c = '\n'
      · subst c
        simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
          nl, eof, Except.map]; rfl
      · simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
          nl, eof, h, Except.map]; rfl

theorem class_lookahead (grammar : PegModel.Grammar) (env : PegModel.Params) (fuel : Nat)
    (ranges : List (Nat × Nat)) (written : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 3) (.andPred (.charClass ranges written)) input =
      .ok (match input with
        | [] => none
        | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
            then some (c :: rest) else none) := by
  cases input with
  | nil => rfl
  | cons c rest =>
      change (match PegModel.recognizeEnv grammar env (fuel + 2) (.charClass ranges written) (c :: rest) with
        | Except.error reason => if PegModel.isLabelFailure reason then Except.ok none else Except.error reason
        | Except.ok none => Except.ok none
        | Except.ok (some _) => Except.ok (some (c :: rest))) = _
      rw [show PegModel.recognizeEnv grammar env (fuel + 2) (.charClass ranges written) (c :: rest) =
        .ok (if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) then some rest else none) from rfl]
      cases h : ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) <;> simp [h]

theorem class_lookahead_or_eof (grammar : PegModel.Grammar) (env : PegModel.Params) (fuel : Nat)
    (ranges : List (Nat × Nat)) (written : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 5)
      (.choice [[.andPred (.charClass ranges written)], [.notPred .any]]) input =
      .ok (match input with
        | [] => some []
        | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
            then some (c :: rest) else none) := by
  have classHit : PegModel.recognizeEnv grammar env (fuel + 4)
      (.andPred (.charClass ranges written)) input =
      .ok (match input with
        | [] => none
        | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
            then some (c :: rest) else none) := by
    simpa [Nat.add_assoc] using class_lookahead grammar env (fuel + 1) ranges written input
  have eof : PegModel.recognizeEnv grammar env (fuel + 4) (.notPred .any) input =
      .ok (if input.isEmpty then some input else none) := by
    cases input <;> rfl
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 4) item rest)
      _ env items input) [[.andPred (.charClass ranges written)], [.notPred .any]] = _
  cases input with
  | nil => simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
      classHit, eof, Except.map]; rfl
  | cons c rest =>
      cases h : ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) with
      | false => simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
          classHit, eof, h, Except.map]; rfl
      | true => simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
          classHit, eof, h, Except.map]; rfl

theorem not_class (grammar : PegModel.Grammar) (env : PegModel.Params) (fuel : Nat)
    (ranges : List (Nat × Nat)) (written : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 2) (.notPred (.charClass ranges written)) input =
      .ok (match input with
        | [] => some []
        | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
            then none else some (c :: rest)) := by
  cases input with
  | nil => rfl
  | cons c rest =>
      change (match PegModel.recognizeEnv grammar env (fuel + 1) (.charClass ranges written) (c :: rest) with
        | Except.error reason => if PegModel.isLabelFailure reason then Except.ok (some (c :: rest)) else Except.error reason
        | Except.ok none => Except.ok (some (c :: rest))
        | Except.ok (some _) => Except.ok none) = _
      rw [show PegModel.recognizeEnv grammar env (fuel + 1) (.charClass ranges written) (c :: rest) =
        .ok (if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) then some rest else none) from rfl]
      cases h : ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) <;> simp [h]

-- Word uses this exact PEG sequence as one character of its ordinary branch.
theorem nonclass_any (grammar : PegModel.Grammar) (env : PegModel.Params) (fuel : Nat)
    (ranges : List (Nat × Nat)) (written : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 4)
      (.choice [[.notPred (.charClass ranges written), .any]]) input =
      .ok (match input with
        | [] => none
        | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
            then none else some rest) := by
  have pred : PegModel.recognizeEnv grammar env (fuel + 3)
      (.notPred (.charClass ranges written)) input =
      .ok (match input with
        | [] => some []
        | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
            then none else some (c :: rest)) := by
    simpa [Nat.add_assoc] using not_class grammar env (fuel + 1) ranges written input
  have any : PegModel.recognizeEnv grammar env (fuel + 3) (.any) input =
      .ok (match input with | [] => none | _ :: rest => some rest) := by
    cases input <;> rfl
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 3) item rest)
      _ env items input) [[.notPred (.charClass ranges written), .any]] = _
  cases input with
  | nil =>
      simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, pred, any, Except.map]
      rfl
  | cons c rest =>
      cases h : ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) with
      | false =>
          simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, pred, any, h, Except.map]
          rfl
      | true =>
          simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, pred, any, h, Except.map]
          rfl

theorem generated_word_ordinary_shape :
    (Generated.pegGrammar.rules.find? (fun rule => rule.name == "Word")).bind
      (fun rule => (rule.alts.get? 1).map PegModel.Alt.items) =
      some [.plus (.choice [[.notPred (.charClass
        [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
          (61, 61), (91, 91), (34, 34), (92, 92)]
        "[ \\t\\n\\]:|=\\[\"\\\\]"), .any]])] := by rfl

theorem star_nonclass (grammar : PegModel.Grammar) (env : PegModel.Params)
    (ranges : List (Nat × Nat)) (written : String)
    (chars suffix : List Char)
    (allowed : ∀ c ∈ chars, ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = false)
    (boundary : match suffix with
      | [] => True
      | c :: _ => ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = true) :
    PegModel.recognizeEnv grammar env (chars.length + 5)
      (.star (.choice [[.notPred (.charClass ranges written), .any]]))
      (chars ++ suffix) = .ok (some suffix) := by
  induction chars with
  | nil =>
      cases suffix with
      | nil => rfl
      | cons c rest =>
          have hb : ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = true := boundary
          have stop : PegModel.recognizeEnv grammar env 4
              (.choice [[.notPred (.charClass ranges written), .any]]) (c :: rest) =
              .ok none := by simpa [hb] using nonclass_any grammar env 0 ranges written (c :: rest)
          change (match PegModel.recognizeEnv grammar env 4
              (.choice [[.notPred (.charClass ranges written), .any]]) (c :: rest) with
            | Except.error reason => Except.error reason
            | Except.ok none => Except.ok (some (c :: rest))
            | Except.ok (some next) =>
                if next.length < (c :: rest).length then
                  PegModel.recognizeEnv grammar env 4
                    (.star (.choice [[.notPred (.charClass ranges written), .any]])) next
                else Except.error "zero-width repetition") = _
          rw [stop]
  | cons c tail ih =>
      have hc := allowed c (by simp)
      have ht : ∀ x ∈ tail, ranges.any (fun (lo, hi) => lo ≤ x.toNat && x.toNat ≤ hi) = false := by
        intro x hx
        exact allowed x (by simp [hx])
      have hit := nonclass_any grammar env (tail.length + 1) ranges written (c :: tail ++ suffix)
      have childHit : PegModel.recognizeEnv grammar env (tail.length + 5)
          (.choice [[.notPred (.charClass ranges written), .any]]) (c :: tail ++ suffix) =
          .ok (some (tail ++ suffix)) := by simpa [hc, Nat.add_assoc] using hit
      have progress : (tail ++ suffix).length < (c :: tail ++ suffix).length := by simp
      have tailResult := ih ht
      change (match PegModel.recognizeEnv grammar env (tail.length + 5)
          (.choice [[.notPred (.charClass ranges written), .any]]) (c :: tail ++ suffix) with
        | Except.error reason => Except.error reason
        | Except.ok none => Except.ok (some (c :: tail ++ suffix))
        | Except.ok (some next) =>
            if next.length < (c :: tail ++ suffix).length then
              PegModel.recognizeEnv grammar env (tail.length + 5)
                (.star (.choice [[.notPred (.charClass ranges written), .any]])) next
            else Except.error "zero-width repetition") = _
      rw [childHit]
      simp [progress, tailResult]
theorem plus_nonclass (grammar : PegModel.Grammar) (env : PegModel.Params)
    (ranges : List (Nat × Nat)) (written : String)
    (first : Char) (tail suffix : List Char)
    (allowed : ∀ c ∈ first :: tail,
      ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = false)
    (boundary : match suffix with
      | [] => True
      | c :: _ => ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = true) :
    PegModel.recognizeEnv grammar env ((first :: tail).length + 5)
      (.plus (.choice [[.notPred (.charClass ranges written), .any]]))
      ((first :: tail) ++ suffix) = .ok (some suffix) := by
  have hf := allowed first (by simp)
  have ht : ∀ c ∈ tail, ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = false := by
    intro c hc
    exact allowed c (by simp [hc])
  have childHit : PegModel.recognizeEnv grammar env (tail.length + 5)
      (.choice [[.notPred (.charClass ranges written), .any]]) (first :: tail ++ suffix) =
      .ok (some (tail ++ suffix)) := by
    simpa [hf, Nat.add_assoc] using
      nonclass_any grammar env (tail.length + 1) ranges written (first :: tail ++ suffix)
  have progress : (tail ++ suffix).length < (first :: tail ++ suffix).length := by simp
  have tailResult := star_nonclass grammar env ranges written tail suffix ht boundary
  change (match PegModel.recognizeEnv grammar env (tail.length + 5)
      (.choice [[.notPred (.charClass ranges written), .any]]) (first :: tail ++ suffix) with
    | Except.error reason => Except.error reason
    | Except.ok none => Except.ok none
    | Except.ok (some next) =>
        if next.length < (first :: tail ++ suffix).length then
          PegModel.recognizeEnv grammar env (tail.length + 5)
            (.star (.choice [[.notPred (.charClass ranges written), .any]])) next
        else Except.error "zero-width repetition") = _
  rw [childHit]
  simp [progress, tailResult]

theorem sequence_head_miss (parse : PegModel.Params → PegModel.Expr → List Char → PegModel.ParseResult)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (env : PegModel.Params) (head : PegModel.Expr) (tail : List PegModel.Expr) (input : List Char)
    (miss : parse env head input = .ok none) :
    PegModel.runSequence parse boundLength env (head :: tail) input = .ok none := by
  simp [PegModel.runSequence, List.foldlM, miss]
  induction tail with
  | nil => rfl
  | cons _ rest ih => simpa [List.foldlM] using ih

private theorem run_sequence_plus (parse : PegModel.Params → PegModel.Expr → List Char → PegModel.ParseResult)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (env : PegModel.Params) (child : PegModel.Expr) (input : List Char) :
    PegModel.runSequence parse boundLength env [.plus child] input =
      parse env (.plus child) input := by
  cases hit : parse env (.plus child) input with
  | error reason => simp [PegModel.runSequence, hit]; rfl
  | ok result =>
      cases result with
      | none => simp [PegModel.runSequence, hit]; rfl
      | some rest => simp [PegModel.runSequence, hit]; rfl

set_option maxHeartbeats 1000000 in
theorem word_choice_ordinary (grammar : PegModel.Grammar) (env : PegModel.Params)
    (ranges : List (Nat × Nat)) (written : String) (special : PegModel.Expr)
    (first : Char) (tail suffix : List Char)
    (allowed : ∀ c ∈ first :: tail,
      ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = false)
    (boundary : match suffix with
      | [] => True
      | c :: _ => ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = true)
    (missPrefix : ("%%=".toList).isPrefixOf ((first :: tail) ++ suffix) = false) :
    PegModel.recognizeEnv grammar env ((first :: tail).length + 6)
      (.choice [[.lit "%%=" "'%%='", special],
        [.plus (.choice [[.notPred (.charClass ranges written), .any]])]])
      ((first :: tail) ++ suffix) = .ok (some suffix) := by
  have miss : PegModel.recognizeEnv grammar env ((first :: tail).length + 5)
      (.lit "%%=" "'%%='") ((first :: tail) ++ suffix) = .ok none := by
    change (Except.ok (if ("%%=".toList).isPrefixOf ((first :: tail) ++ suffix) then
      some (((first :: tail) ++ suffix).drop "%%=".toList.length) else none) :
      PegModel.ParseResult) = .ok none
    rw [missPrefix]
    rfl
  have ordinary : PegModel.recognizeEnv grammar env ((first :: tail).length + 5)
      (.plus (.choice [[.notPred (.charClass ranges written), .any]]))
      ((first :: tail) ++ suffix) = .ok (some suffix) :=
    plus_nonclass grammar env ranges written first tail suffix allowed boundary
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope ((first :: tail).length + 5) item rest)
      _ env items ((first :: tail) ++ suffix))
    [[.lit "%%=" "'%%='", special],
      [.plus (.choice [[.notPred (.charClass ranges written), .any]])]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  rw [sequence_head_miss _ _ env (.lit "%%=" "'%%='") [special] _ miss]
  rw [run_sequence_plus]
  rw [ordinary]
  rfl

theorem generated_word_ordinary (first : Char) (tail suffix : List Char)
    (allowed : ∀ c ∈ first :: tail,
      ([(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
        (61, 61), (91, 91), (34, 34), (92, 92)] : List (Nat × Nat)).any
        (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = false)
    (boundary : match suffix with
      | [] => True
      | c :: _ => ([(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
          (61, 61), (91, 91), (34, 34), (92, 92)] : List (Nat × Nat)).any
          (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = true)
    (missPrefix : ("%%=".toList).isPrefixOf ((first :: tail) ++ suffix) = false) :
    PegModel.recognizeEnv Generated.pegGrammar [] ((first :: tail).length + 7)
      (.ref "Word" []) ((first :: tail) ++ suffix) = .ok (some suffix) := by
  change PegModel.recognizeEnv Generated.pegGrammar [] ((first :: tail).length + 6)
    (.choice [
      [.lit "%%=" "'%%='", .star (.choice [[.notPred (.charClass
        [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
          (91, 91), (34, 34), (92, 92)] "[ \\t\\n\\]:|\\[\"\\\\]"), .any]])],
      [.plus (.choice [[.notPred (.charClass
        [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
          (61, 61), (91, 91), (34, 34), (92, 92)] "[ \\t\\n\\]:|=\\[\"\\\\]"), .any]])]])
    ((first :: tail) ++ suffix) = _
  exact word_choice_ordinary Generated.pegGrammar []
    [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
      (61, 61), (91, 91), (34, 34), (92, 92)]
    "[ \\t\\n\\]:|=\\[\"\\\\]"
    (.star (.choice [[.notPred (.charClass
      [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
        (91, 91), (34, 34), (92, 92)] "[ \\t\\n\\]:|\\[\"\\\\]"), .any]]))
    first tail suffix allowed boundary missPrefix

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

def permitted (ranges : List (Nat × Nat)) (c : Char) : Bool :=
  !(ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi))

theorem star_nonclass_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (ranges : List (Nat × Nat)) (written : String) (input : List Char) (extra : Nat) :
    PegModel.recognizeEnv grammar env (input.length + 5 + extra)
      (.star (.choice [[.notPred (.charClass ranges written), .any]])) input =
      .ok (some (input.dropWhile (permitted ranges))) := by
  induction input with
  | nil =>
      have child := nonclass_any grammar env extra ranges written []
      have fuelEq : extra + 4 = 4 + extra := by omega
      rw [fuelEq] at child
      simp only [List.length_nil, Nat.zero_add]
      have outerEq : 5 + extra = (4 + extra) + 1 := by omega
      rw [outerEq]
      change (match PegModel.recognizeEnv grammar env (4 + extra)
          (.choice [[.notPred (.charClass ranges written), .any]]) [] with
        | Except.error reason => Except.error reason
        | Except.ok none => Except.ok (some [])
        | Except.ok (some next) =>
            if next.length < 0 then
              PegModel.recognizeEnv grammar env (4 + extra)
                (.star (.choice [[.notPred (.charClass ranges written), .any]])) next
            else Except.error "zero-width repetition") = _
      rw [child]
      rfl
  | cons c rest ih =>
      have child := nonclass_any grammar env (rest.length + 1 + extra)
        ranges written (c :: rest)
      cases h : ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) with
      | true =>
          have fuelEq : rest.length + 1 + extra + 4 = rest.length + 5 + extra := by omega
          rw [fuelEq] at child
          have childMiss : PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
              (.choice [[.notPred (.charClass ranges written), .any]]) (c :: rest) =
              .ok none := by simpa [h] using child
          have outerEq : (c :: rest).length + 5 + extra = rest.length + 5 + extra + 1 := by
            simp [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm]
          rw [outerEq]
          change (match PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
              (.choice [[.notPred (.charClass ranges written), .any]]) (c :: rest) with
            | Except.error reason => Except.error reason
            | Except.ok none => Except.ok (some (c :: rest))
            | Except.ok (some next) =>
                if next.length < (c :: rest).length then
                  PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
                    (.star (.choice [[.notPred (.charClass ranges written), .any]])) next
                else Except.error "zero-width repetition") = _
          rw [childMiss]
          simp [List.dropWhile, permitted, h]
      | false =>
          have fuelEq : rest.length + 1 + extra + 4 = rest.length + 5 + extra := by omega
          rw [fuelEq] at child
          have childHit : PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
              (.choice [[.notPred (.charClass ranges written), .any]]) (c :: rest) =
              .ok (some rest) := by simpa [h] using child
          have progress : rest.length < (c :: rest).length := by simp
          have outerEq : (c :: rest).length + 5 + extra = rest.length + 5 + extra + 1 := by
            simp [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm]
          rw [outerEq]
          change (match PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
              (.choice [[.notPred (.charClass ranges written), .any]]) (c :: rest) with
            | Except.error reason => Except.error reason
            | Except.ok none => Except.ok (some (c :: rest))
            | Except.ok (some next) =>
                if next.length < (c :: rest).length then
                  PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
                    (.star (.choice [[.notPred (.charClass ranges written), .any]])) next
                else Except.error "zero-width repetition") = _
          rw [childHit]
          simp [progress, ih, List.dropWhile, permitted, h]

theorem plus_nonclass_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (ranges : List (Nat × Nat)) (written : String) (input : List Char) (extra : Nat) :
    PegModel.recognizeEnv grammar env (input.length + 5 + extra)
      (.plus (.choice [[.notPred (.charClass ranges written), .any]])) input =
      .ok (match input with
        | [] => none
        | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
          then none else some (rest.dropWhile (permitted ranges))) := by
  cases input with
  | nil =>
      simp only [List.length_nil, Nat.zero_add]
      have outerEq : 5 + extra = (4 + extra) + 1 := by omega
      rw [outerEq]
      have child := nonclass_any grammar env extra ranges written []
      have fuelEq : extra + 4 = 4 + extra := by omega
      rw [fuelEq] at child
      change (match PegModel.recognizeEnv grammar env (4 + extra)
          (.choice [[.notPred (.charClass ranges written), .any]]) [] with
        | Except.error reason => Except.error reason
        | Except.ok none => Except.ok none
        | Except.ok (some next) =>
            if next.length < 0 then
              PegModel.recognizeEnv grammar env (4 + extra)
                (.star (.choice [[.notPred (.charClass ranges written), .any]])) next
            else Except.error "zero-width repetition") = _
      rw [child]
  | cons c rest =>
      have child := nonclass_any grammar env (rest.length + 1 + extra)
        ranges written (c :: rest)
      have fuelEq : rest.length + 1 + extra + 4 = rest.length + 5 + extra := by omega
      rw [fuelEq] at child
      have outerEq : (c :: rest).length + 5 + extra = rest.length + 5 + extra + 1 := by
        simp [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm]
      rw [outerEq]
      cases h : ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) with
      | true =>
          have childMiss : PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
              (.choice [[.notPred (.charClass ranges written), .any]]) (c :: rest) =
              .ok none := by simpa [h] using child
          change (match PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
              (.choice [[.notPred (.charClass ranges written), .any]]) (c :: rest) with
            | Except.error reason => Except.error reason
            | Except.ok none => Except.ok none
            | Except.ok (some next) =>
                if next.length < (c :: rest).length then
                  PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
                    (.star (.choice [[.notPred (.charClass ranges written), .any]])) next
                else Except.error "zero-width repetition") = _
          rw [childMiss]
          change _ = Except.ok (if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
            then none else some (rest.dropWhile (permitted ranges)))
          rw [h]
          rfl
      | false =>
          have childHit : PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
              (.choice [[.notPred (.charClass ranges written), .any]]) (c :: rest) =
              .ok (some rest) := by simpa [h] using child
          have progress : rest.length < (c :: rest).length := by simp
          have tailResult := star_nonclass_total grammar env ranges written rest extra
          change (match PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
              (.choice [[.notPred (.charClass ranges written), .any]]) (c :: rest) with
            | Except.error reason => Except.error reason
            | Except.ok none => Except.ok none
            | Except.ok (some next) =>
                if next.length < (c :: rest).length then
                  PegModel.recognizeEnv grammar env (rest.length + 5 + extra)
                    (.star (.choice [[.notPred (.charClass ranges written), .any]])) next
                else Except.error "zero-width repetition") = _
          rw [childHit]
          change _ = Except.ok (if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
            then none else some (rest.dropWhile (permitted ranges)))
          rw [h]
          simp [progress, tailResult]

private theorem run_lit_star_hit (parse : PegModel.Params → PegModel.Expr → List Char → PegModel.ParseResult)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (env : PegModel.Params) (value written : String) (child : PegModel.Expr)
    (input middle tail : List Char)
    (first : parse env (.lit value written) input = .ok (some middle))
    (second : parse env (.star child) middle = .ok (some tail)) :
    PegModel.runSequence parse boundLength env [.lit value written, .star child] input =
      .ok (some tail) := by
  simp [PegModel.runSequence, first, second, Except.map]
  rfl

theorem special_word_choice (grammar : PegModel.Grammar) (env : PegModel.Params)
    (ranges : List (Nat × Nat)) (written : String) (other : List PegModel.Expr)
    (suffix : List Char) (extra : Nat) :
    PegModel.recognizeEnv grammar env (suffix.length + 7 + extra)
      (.choice [[.lit "%%=" "'%%='",
        .star (.choice [[.notPred (.charClass ranges written), .any]])], other])
      ("%%=".toList ++ suffix) =
      .ok (some (suffix.dropWhile (permitted ranges))) := by
  have literal : PegModel.recognizeEnv grammar env (suffix.length + 6 + extra)
      (.lit "%%=" "'%%='") ("%%=".toList ++ suffix) = .ok (some suffix) := by
    have fuelEq : suffix.length + 6 + extra = (suffix.length + 5 + extra) + 1 := by omega
    rw [fuelEq]
    calc
      _ = PegModel.recognize grammar ((suffix.length + 5 + extra) + 1)
          (.lit "%%=" "'%%='") ("%%=".toList ++ suffix) := by rfl
      _ = .ok (some suffix) :=
        literal_roundtrip grammar "%%=" "'%%='" suffix (suffix.length + 5 + extra)
  have star : PegModel.recognizeEnv grammar env (suffix.length + 6 + extra)
      (.star (.choice [[.notPred (.charClass ranges written), .any]])) suffix =
      .ok (some (suffix.dropWhile (permitted ranges))) := by
    have eqFuel : suffix.length + 5 + (1 + extra) = suffix.length + 6 + extra := by omega
    rw [← eqFuel]
    exact star_nonclass_total grammar env ranges written suffix (1 + extra)
  have outerEq : suffix.length + 7 + extra = (suffix.length + 6 + extra) + 1 := by omega
  rw [outerEq]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (suffix.length + 6 + extra) item rest)
      _ env items ("%%=".toList ++ suffix))
    [[.lit "%%=" "'%%='",
      .star (.choice [[.notPred (.charClass ranges written), .any]])], other] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  rw [run_lit_star_hit _ _ env "%%=" "'%%='"
    (.choice [[.notPred (.charClass ranges written), .any]])
    ("%%=".toList ++ suffix) suffix (suffix.dropWhile (permitted ranges)) literal star]
  rfl

theorem generated_word_special (suffix : List Char) (extra : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (suffix.length + 8 + extra)
      (.ref "Word" []) ("%%=".toList ++ suffix) =
      .ok (some (suffix.dropWhile (permitted
        [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
          (91, 91), (34, 34), (92, 92)]))) := by
  have fuelEq : suffix.length + 8 + extra = (suffix.length + 7 + extra) + 1 := by omega
  rw [fuelEq]
  change PegModel.recognizeEnv Generated.pegGrammar [] (suffix.length + 7 + extra)
    (.choice [
      [.lit "%%=" "'%%='", .star (.choice [[.notPred (.charClass
        [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
          (91, 91), (34, 34), (92, 92)] "[ \\t\\n\\]:|\\[\"\\\\]"), .any]])],
      [.plus (.choice [[.notPred (.charClass
        [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
          (61, 61), (91, 91), (34, 34), (92, 92)] "[ \\t\\n\\]:|=\\[\"\\\\]"), .any]])]])
    ("%%=".toList ++ suffix) = _
  exact special_word_choice Generated.pegGrammar []
    [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
      (91, 91), (34, 34), (92, 92)]
    "[ \\t\\n\\]:|\\[\"\\\\]"
    [.plus (.choice [[.notPred (.charClass
      [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
        (61, 61), (91, 91), (34, 34), (92, 92)] "[ \\t\\n\\]:|=\\[\"\\\\]"), .any]])]
    suffix extra

theorem ordinary_word_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (ranges : List (Nat × Nat)) (written : String) (special : PegModel.Expr)
    (input : List Char) (extra : Nat)
    (missPrefix : ("%%=".toList).isPrefixOf input = false) :
    PegModel.recognizeEnv grammar env (input.length + 7 + extra)
      (.choice [[.lit "%%=" "'%%='", special],
        [.plus (.choice [[.notPred (.charClass ranges written), .any]])]])
      input = .ok (match input with
        | [] => none
        | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
          then none else some (rest.dropWhile (permitted ranges))) := by
  have miss : PegModel.recognizeEnv grammar env (input.length + 6 + extra)
      (.lit "%%=" "'%%='") input = .ok none := by
    have missFuel : input.length + 6 + extra = (input.length + 5 + extra) + 1 := by omega
    rw [missFuel]
    change (Except.ok (if ("%%=".toList).isPrefixOf input then
      some (input.drop "%%=".toList.length) else none) : PegModel.ParseResult) = .ok none
    rw [missPrefix]
    rfl
  have ordinary := plus_nonclass_total grammar env ranges written input (1 + extra)
  have fuelEq : input.length + 5 + (1 + extra) = input.length + 6 + extra := by omega
  rw [fuelEq] at ordinary
  have outerEq : input.length + 7 + extra = (input.length + 6 + extra) + 1 := by omega
  rw [outerEq]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (input.length + 6 + extra) item rest)
      _ env items input)
    [[.lit "%%=" "'%%='", special],
      [.plus (.choice [[.notPred (.charClass ranges written), .any]])]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  rw [sequence_head_miss _ _ env (.lit "%%=" "'%%='") [special] _ miss]
  rw [run_sequence_plus]
  rw [ordinary]
  cases input with
  | nil => rfl
  | cons c rest => rfl

theorem generated_word_ordinary_total (input : List Char) (extra : Nat)
    (missPrefix : ("%%=".toList).isPrefixOf input = false) :
    PegModel.recognizeEnv Generated.pegGrammar [] (input.length + 8 + extra)
      (.ref "Word" []) input =
      .ok (match input with
        | [] => none
        | c :: rest => if ([(32, 32), (9, 9), (10, 10), (93, 93), (58, 58),
          (124, 124), (61, 61), (91, 91), (34, 34), (92, 92)] : List (Nat × Nat)).any
            (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
          then none else some (rest.dropWhile (permitted
            [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58),
             (124, 124), (61, 61), (91, 91), (34, 34), (92, 92)]))) := by
  have fuelEq : input.length + 8 + extra = (input.length + 7 + extra) + 1 := by omega
  rw [fuelEq]
  change PegModel.recognizeEnv Generated.pegGrammar [] (input.length + 7 + extra)
    (.choice [
      [.lit "%%=" "'%%='", .star (.choice [[.notPred (.charClass
        [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
          (91, 91), (34, 34), (92, 92)] "[ \\t\\n\\]:|\\[\"\\\\]"), .any]])],
      [.plus (.choice [[.notPred (.charClass
        [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
          (61, 61), (91, 91), (34, 34), (92, 92)] "[ \\t\\n\\]:|=\\[\"\\\\]"), .any]])]])
    input = _
  exact ordinary_word_total Generated.pegGrammar []
    [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
      (61, 61), (91, 91), (34, 34), (92, 92)]
    "[ \\t\\n\\]:|=\\[\"\\\\]"
    (.star (.choice [[.notPred (.charClass
      [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
        (91, 91), (34, 34), (92, 92)] "[ \\t\\n\\]:|\\[\"\\\\]"), .any]]))
    input extra missPrefix

theorem literal_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (value written : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 1) (.lit value written) input =
      .ok (if value.toList.isPrefixOf input then some (input.drop value.toList.length) else none) := by
  rfl

theorem not_literal_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (value written : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 2) (.notPred (.lit value written)) input =
      .ok (if value.toList.isPrefixOf input then none else some input) := by
  have fuelEq : fuel + 2 = (fuel + 1) + 1 := by omega
  rw [fuelEq]
  change (match PegModel.recognizeEnv grammar env (fuel + 1) (.lit value written) input with
    | Except.error reason => if PegModel.isLabelFailure reason then Except.ok (some input) else Except.error reason
    | Except.ok none => Except.ok (some input)
    | Except.ok (some _) => Except.ok none) = _
  rw [literal_total]
  cases h : value.toList.isPrefixOf input <;> simp [h]

theorem sequence_literal_guard (grammar : PegModel.Grammar) (env : PegModel.Params)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (fuel : Nat) (value valueWritten guard guardWritten : String) (input : List Char) :
    PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 3) item rest)
      boundLength env [.lit value valueWritten, .notPred (.lit guard guardWritten)] input =
      .ok (if value.toList.isPrefixOf input then
        let rest := input.drop value.toList.length
        if guard.toList.isPrefixOf rest then none else some rest
        else none) := by
  have literal := literal_total grammar env (fuel + 2) value valueWritten input
  have fuelEq : fuel + 2 + 1 = fuel + 3 := by omega
  rw [fuelEq] at literal
  cases hv : value.toList.isPrefixOf input with
  | false =>
      simp [PegModel.runSequence, literal, hv] <;> rfl
  | true =>
      have guardProof := not_literal_total grammar env (fuel + 1) guard guardWritten
        (input.drop value.toList.length)
      have fuelEq2 : fuel + 1 + 2 = fuel + 3 := by omega
      rw [fuelEq2] at guardProof
      cases hg : guard.toList.isPrefixOf (input.drop value.toList.length) with
      | false => simp [PegModel.runSequence, literal, guardProof, hv, hg] <;> rfl
      | true => simp [PegModel.runSequence, literal, guardProof, hv, hg] <;> rfl

theorem sequence_literal_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (fuel : Nat) (value written : String) (input : List Char) :
    PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 1) item rest)
      boundLength env [.lit value written] input =
      .ok (if value.toList.isPrefixOf input then some (input.drop value.toList.length) else none) := by
  have literal := literal_total grammar env fuel value written input
  cases h : value.toList.isPrefixOf input <;>
    simp [PegModel.runSequence, literal, h] <;> rfl

theorem mul_choice_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv grammar env (fuel + 4)
      (.choice [
        [.lit "*" "'*'", .notPred (.lit "*" "'*'")],
        [.lit "/" "'/'"],
        [.lit "%" "'%'", .notPred (.lit "%" "'%'")]]) input =
      .ok (let star := if ("*".toList).isPrefixOf input then
          let rest := input.drop 1
          if ("*".toList).isPrefixOf rest then none else some rest else none
        let slash := if ("/".toList).isPrefixOf input then some (input.drop 1) else none
        let percent := if ("%".toList).isPrefixOf input then
          let rest := input.drop 1
          if ("%".toList).isPrefixOf rest then none else some rest else none
        match star with
        | some x => some x
        | none => match slash with
          | some x => some x
          | none => percent) := by
  have fuelEq : fuel + 4 = (fuel + 3) + 1 := by omega
  rw [fuelEq]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 3) item rest)
      _ env items input)
    [[.lit "*" "'*'", .notPred (.lit "*" "'*'")],
     [.lit "/" "'/'"],
     [.lit "%" "'%'", .notPred (.lit "%" "'%'")]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  rw [sequence_literal_guard grammar env _ fuel "*" "'*'" "*" "'*'" input]
  have slashFuel : fuel + 3 = (fuel + 2) + 1 := by omega
  rw [slashFuel]
  rw [sequence_literal_total grammar env _ (fuel + 2) "/" "'/'" input]
  rw [sequence_literal_guard grammar env _ fuel "%" "'%'" "%" "'%'" input]
  have starLength : ("*".toList).length = 1 := by decide
  have slashLength : ("/".toList).length = 1 := by decide
  have percentLength : ("%".toList).length = 1 := by decide
  simp only [starLength, slashLength, percentLength]
  cases hs : ("*".toList).isPrefixOf input <;>
    cases hss : ("*".toList).isPrefixOf (input.drop 1) <;>
    cases hl : ("/".toList).isPrefixOf input <;>
    cases hp : ("%".toList).isPrefixOf input <;>
    cases hpp : ("%".toList).isPrefixOf (input.drop 1) <;>
    simp [hs, hss, hl, hp, hpp, Except.bind, Except.pure] <;> rfl

theorem generated_mul_choice_total (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 5) (.ref "MulOp" []) input =
      .ok (let star := if ("*".toList).isPrefixOf input then
          let rest := input.drop 1
          if ("*".toList).isPrefixOf rest then none else some rest else none
        let slash := if ("/".toList).isPrefixOf input then some (input.drop 1) else none
        let percent := if ("%".toList).isPrefixOf input then
          let rest := input.drop 1
          if ("%".toList).isPrefixOf rest then none else some rest else none
        match star with
        | some x => some x
        | none => match slash with
          | some x => some x
          | none => percent) := by
  have fuelEq : fuel + 5 = (fuel + 4) + 1 := by omega
  rw [fuelEq]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 4)
    (.choice [[.lit "*" "'*'", .notPred (.lit "*" "'*'")],
      [.lit "/" "'/'"], [.lit "%" "'%'", .notPred (.lit "%" "'%'")]]) input = _
  exact mul_choice_total Generated.pegGrammar [] input fuel

theorem keyword_literal_choice (grammar : PegModel.Grammar) (env : PegModel.Params)
    (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv grammar env (fuel + 3)
      (.choice [[.lit "true" "'true'"], [.lit "false" "'false'"], [.lit "nil" "'nil'"]]) input =
      .ok (firstLiteral [("true", "'true'"), ("false", "'false'"), ("nil", "'nil'")] input) := by
  have fuelEq : fuel + 3 = (fuel + 2) + 1 := by omega
  rw [fuelEq]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 2) item rest)
      _ env items input)
    (literalAlternatives [("true", "'true'"), ("false", "'false'"), ("nil", "'nil'")]) = _
  exact interpreted_literal_choices grammar env _
    [("true", "'true'"), ("false", "'false'"), ("nil", "'nil'")] input (fuel + 1)

def keywordExpected (input : List Char) : Option (List Char) :=
  (firstLiteral [("true", "'true'"), ("false", "'false'"), ("nil", "'nil'")] input).bind fun rest =>
    match rest with
    | [] => some []
    | c :: tail => if ([(97, 122), (48, 57), (95, 95)] : List (Nat × Nat)).any
        (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) then none else some (c :: tail)

theorem keyword_sequence_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (input : List Char) (fuel : Nat) :
    PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 3) item rest)
      boundLength env
      [.choice [[.lit "true" "'true'"], [.lit "false" "'false'"], [.lit "nil" "'nil'"]],
        .notPred (.charClass [(97, 122), (48, 57), (95, 95)] "[a-z0-9_]")]
      input = .ok (keywordExpected input) := by
  have first := keyword_literal_choice grammar env input fuel
  cases h : firstLiteral [("true", "'true'"), ("false", "'false'"), ("nil", "'nil'")] input with
  | none => simp [PegModel.runSequence, first, h, keywordExpected] <;> rfl
  | some rest =>
      have second := not_class grammar env (fuel + 1)
        [(97, 122), (48, 57), (95, 95)] "[a-z0-9_]" rest
      have fuelEq : fuel + 1 + 2 = fuel + 3 := by omega
      rw [fuelEq] at second
      cases rest with
      | nil => simp [PegModel.runSequence, first, h, second, keywordExpected] <;> rfl
      | cons c tail =>
          by_cases h1 : 97 ≤ c.toNat ∧ c.toNat ≤ 122
          · simp [PegModel.runSequence, first, h, second, keywordExpected, h1] <;> rfl
          · by_cases h2 : 48 ≤ c.toNat ∧ c.toNat ≤ 57
            · simp [PegModel.runSequence, first, h, second, keywordExpected, h1, h2] <;> rfl
            · by_cases h3 : 95 ≤ c.toNat ∧ c.toNat ≤ 95
              · simp [PegModel.runSequence, first, h, second, keywordExpected, h1, h2, h3] <;> rfl
              · simp [PegModel.runSequence, first, h, second, keywordExpected, h1, h2, h3] <;> rfl

theorem generated_keyword_total (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 5) (.ref "Keyword" []) input =
      .ok (keywordExpected input) := by
  have fuelEq : fuel + 5 = (fuel + 4) + 1 := by omega
  rw [fuelEq]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 4)
    (.choice [[.choice [[.lit "true" "'true'"], [.lit "false" "'false'"], [.lit "nil" "'nil'"]],
      .notPred (.charClass [(97, 122), (48, 57), (95, 95)] "[a-z0-9_]")]]) input = _
  have innerEq : fuel + 4 = (fuel + 3) + 1 := by omega
  rw [innerEq]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 3) item rest)
      _ [] items input)
    [[.choice [[.lit "true" "'true'"], [.lit "false" "'false'"], [.lit "nil" "'nil'"]],
      .notPred (.charClass [(97, 122), (48, 57), (95, 95)] "[a-z0-9_]")]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  rw [keyword_sequence_total Generated.pegGrammar [] _ input fuel]
  rfl

example : keywordExpected "true!".toList = some "!".toList := by rfl
example : keywordExpected "truex".toList = none := by rfl
example : keywordExpected "nil_".toList = none := by rfl
example : keywordExpected "false".toList = some [] := by rfl

theorem lit_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (value written : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 1) (.lit value written) input =
      .ok (if value.toList.isPrefixOf input then some (input.drop value.toList.length) else none) := by
  rfl

theorem class_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (fuel : Nat) (ranges : List (Nat × Nat)) (written : String) (input : List Char) :
    PegModel.recognizeEnv grammar env (fuel + 1) (.charClass ranges written) input =
      .ok (match input with
        | [] => none
        | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
          then some rest else none) := by
  rfl

def prefixClassExpected (input : List Char) : Option (List Char) :=
  if ("@".toList).isPrefixOf input then
    match input.drop 1 with
    | [] => none
    | c :: rest => if ([(97, 122)] : List (Nat × Nat)).any
        (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) then some rest else none
  else none

theorem prefix_class_sequence (grammar : PegModel.Grammar) (env : PegModel.Params)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (input : List Char) (fuel : Nat) :
    PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 1) item rest)
      boundLength env [.lit "@" "'@'", .charClass [(97, 122)] "[a-z]"] input =
      .ok (prefixClassExpected input) := by
  have literal := lit_total grammar env fuel "@" "'@'" input
  cases hp : ("@".toList).isPrefixOf input with
  | false => simp [PegModel.runSequence, literal, hp, prefixClassExpected] <;> rfl
  | true =>
      have classHit :=  class_total grammar env fuel [(97, 122)] "[a-z]" (input.drop 1)
      have one : ("@".toList).length = 1 := by decide
      rw [one] at literal
      cases rest : input.drop 1 with
      | nil =>
          rw [rest] at classHit
          simp [PegModel.runSequence, literal, classHit, hp, prefixClassExpected, rest] <;> rfl
      | cons c tail =>
          rw [rest] at classHit
          by_cases hc : 97 ≤ c.toNat ∧ c.toNat ≤ 122
          · simp [PegModel.runSequence, literal, classHit, hp, prefixClassExpected, rest, hc] <;> rfl
          · simp [PegModel.runSequence, literal, classHit, hp, prefixClassExpected, rest, hc] <;> rfl

private theorem single_ref_sequence (parse : PegModel.Params → PegModel.Expr → List Char → PegModel.ParseResult)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (env : PegModel.Params) (name : String) (args : List String) (input : List Char) :
    PegModel.runSequence parse boundLength env [.ref name args] input =
      parse env (.ref name args) input := by
  cases hit : parse env (.ref name args) input with
  | error reason => simp [PegModel.runSequence, hit]; rfl
  | ok result =>
      cases result with
      | none => simp [PegModel.runSequence, hit]; rfl
      | some rest => simp [PegModel.runSequence, hit]; rfl

theorem block_command_start_choice (grammar : PegModel.Grammar) (env : PegModel.Params)
    (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv grammar env (fuel + 2)
      (.choice [[.lit "@" "'@'", .charClass [(97, 122)] "[a-z]"],
        [.ref "SetDeclarationStart" []]]) input =
      (match prefixClassExpected input with
      | some rest => .ok (some rest)
      | none => PegModel.recognizeEnv grammar env (fuel + 1)
          (.ref "SetDeclarationStart" []) input) := by
  have fuelEq : fuel + 2 = (fuel + 1) + 1 := by omega
  rw [fuelEq]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 1) item rest)
      _ env items input)
    [[.lit "@" "'@'", .charClass [(97, 122)] "[a-z]"],
      [.ref "SetDeclarationStart" []]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  rw [prefix_class_sequence grammar env _ input fuel]
  rw [single_ref_sequence]
  cases h : prefixClassExpected input <;> simp [h] <;> rfl

theorem generated_block_command_start (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
      (.ref "BlockCommandStart" []) input =
      (match prefixClassExpected input with
      | some rest => .ok (some rest)
      | none => PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
          (.ref "SetDeclarationStart" []) input) := by
  have fuelEq : fuel + 3 = (fuel + 2) + 1 := by omega
  rw [fuelEq]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 2)
    (.choice [[.lit "@" "'@'", .charClass [(97, 122)] "[a-z]"],
      [.ref "SetDeclarationStart" []]]) input = _
  exact block_command_start_choice Generated.pegGrammar [] input fuel

theorem star_any_total (grammar : PegModel.Grammar) (env : PegModel.Params)
    (input : List Char) (extra : Nat) :
    PegModel.recognizeEnv grammar env (input.length + 2 + extra) (.star .any) input =
      .ok (some []) := by
  induction input with
  | nil =>
      have fuelEq : 2 + extra = (1 + extra) + 1 := by omega
      simp only [List.length_nil, Nat.zero_add]
      rw [fuelEq]
      change (match PegModel.recognizeEnv grammar env (1 + extra) .any [] with
        | Except.error reason => Except.error reason
        | Except.ok none => Except.ok (some [])
        | Except.ok (some next) =>
            if next.length < 0 then PegModel.recognizeEnv grammar env (1 + extra) (.star .any) next
            else Except.error "zero-width repetition") = _
      have child : PegModel.recognizeEnv grammar env (1 + extra) .any [] = .ok none := by
        have step : 1 + extra = extra + 1 := by omega
        rw [step]
        rfl
      rw [child]
  | cons c rest ih =>
      have fuelEq : (c :: rest).length + 2 + extra = (rest.length + 2 + extra) + 1 := by
        simp only [List.length_cons]
        omega
      rw [fuelEq]
      change (match PegModel.recognizeEnv grammar env (rest.length + 2 + extra) .any (c :: rest) with
        | Except.error reason => Except.error reason
        | Except.ok none => Except.ok (some (c :: rest))
        | Except.ok (some next) =>
            if next.length < (c :: rest).length then
              PegModel.recognizeEnv grammar env (rest.length + 2 + extra) (.star .any) next
            else Except.error "zero-width repetition") = _
      have child : PegModel.recognizeEnv grammar env (rest.length + 2 + extra) .any (c :: rest) = .ok (some rest) := by
        have step : rest.length + 2 + extra = (rest.length + 1 + extra) + 1 := by omega
        rw [step]
        rfl
      rw [child]
      simp [ih]

theorem generated_skip_all (input : List Char) (extra : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (input.length + 4 + extra)
      (.ref "SkipAll" []) input = .ok (some []) := by
  have refFuel : input.length + 4 + extra = (input.length + 3 + extra) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (input.length + 3 + extra)
    (.choice [[.star .any]]) input = _
  have choiceFuel : input.length + 3 + extra = (input.length + 2 + extra) + 1 := by omega
  rw [choiceFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (input.length + 2 + extra) item rest)
      _ [] items input) [[.star .any]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  have star := star_any_total Generated.pegGrammar [] input extra
  simp [PegModel.runSequence, star]
  rfl

theorem generated_skip_line (input : List Char) (extra : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (input.length + 7 + extra)
      (.ref "SkipLine" []) input =
      .ok (some (input.dropWhile (permitted [(10, 10)]))) := by
  have refFuel : input.length + 7 + extra = (input.length + 6 + extra) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (input.length + 6 + extra)
    (.choice [[.star (.choice [[.notPred (.charClass [(10, 10)] "[\\n]"), .any]])]]) input = _
  have choiceFuel : input.length + 6 + extra = (input.length + 5 + extra) + 1 := by omega
  rw [choiceFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (input.length + 5 + extra) item rest)
      _ [] items input)
    [[.star (.choice [[.notPred (.charClass [(10, 10)] "[\\n]"), .any]])]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  have star := star_nonclass_total Generated.pegGrammar [] [(10, 10)] "[\\n]" input extra
  simp [PegModel.runSequence, star]
  rfl

def codeLineExpected (input : List Char) : Option (List Char) :=
  match input.dropWhile (permitted [(10, 10)]) with
  | '\n' :: rest => some rest
  | _ => none

theorem code_line_sequence (input : List Char) (extra : Nat)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat)) :
    PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (input.length + 5 + extra) item rest)
      boundLength []
      [.star (.choice [[.notPred (.charClass [(10, 10)] "[\\n]"), .any]]), .ref "Nl" []]
      input = .ok (codeLineExpected input) := by
  let suffix := input.dropWhile (permitted [(10, 10)])
  have star := star_nonclass_total Generated.pegGrammar [] [(10, 10)] "[\\n]" input extra
  have suffixEq : input.dropWhile (permitted [(10, 10)]) = suffix := rfl
  rw [suffixEq] at star
  have nl := generated_nl_eval [] (input.length + 1 + extra) suffix
  have fuelEq : input.length + 1 + extra + 4 = input.length + 5 + extra := by omega
  rw [fuelEq] at nl
  unfold codeLineExpected
  rw [suffixEq]
  cases hs : suffix with
  | nil =>
      rw [hs] at nl
      simp [PegModel.runSequence, star, nl, hs] <;> rfl
  | cons c rest =>
      rw [hs] at nl
      by_cases hc : c = '\n'
      · subst c
        simp [PegModel.runSequence, star, nl, hs] <;> rfl
      · simp [PegModel.runSequence, star, nl, hs, hc] <;> rfl

theorem generated_code_line (input : List Char) (extra : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (input.length + 7 + extra)
      (.ref "CodeLine" []) input = .ok (codeLineExpected input) := by
  have refFuel : input.length + 7 + extra = (input.length + 6 + extra) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (input.length + 6 + extra)
    (.choice [[.star (.choice [[.notPred (.charClass [(10, 10)] "[\\n]"), .any]]),
      .ref "Nl" []]]) input = _
  have choiceFuel : input.length + 6 + extra = (input.length + 5 + extra) + 1 := by omega
  rw [choiceFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (input.length + 5 + extra) item rest)
      _ [] items input)
    [[.star (.choice [[.notPred (.charClass [(10, 10)] "[\\n]"), .any]]), .ref "Nl" []]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  rw [code_line_sequence input extra]
  rfl

example : codeLineExpected "abc\nnext".toList = some "next".toList := by rfl
example : codeLineExpected "abc".toList = none := by rfl

theorem seventhHashFails (extra : Nat) (tail : List Char) :
    PegModel.recognize Generated.pegGrammar (extra + 40) (.ref "Heading" ["0"])
      ("#######".toList ++ tail) = .error "label: heading_level" := by
  cases tail <;> rfl

theorem allowedHashRun (level : Fin 6) (extra : Nat) (tail : List Char) :
    PegModel.recognize Generated.pegGrammar (extra + 12) (.ref "HashMark" [])
      (List.replicate (level.val + 1) '#' ++ ' ' :: tail) = .ok (some (' ' :: tail)) := by
  obtain ⟨n, h⟩ := level
  iterate 6 (cases n <;> first | rfl | rename_i n)
  omega

end PegModelTest
