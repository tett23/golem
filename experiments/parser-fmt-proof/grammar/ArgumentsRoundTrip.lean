import WordRoundTrip
import PegModelTest

namespace ArgumentsRoundTrip

private theorem generated_ordinary_ranges :
    WordRoundTrip.ordinaryWordRanges =
      [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58),
       (124, 124), (61, 61), (91, 91), (34, 34), (92, 92)] := by
  rfl

private theorem ordinary_permitted_is_allowed :
    PegModelTest.permitted WordRoundTrip.ordinaryWordRanges = WordRoundTrip.allowed := by
  funext c
  simp [PegModelTest.permitted, WordRoundTrip.ordinary_ranges_allowed]

-- A finite trace for the canonical recognizer's star operator.  Every hit is
-- checked at the fuel that recognizeEnv actually passes to its child; the
-- final miss leaves the caller's suffix untouched.
def CanonicalStarSteps (grammar : PegModel.Grammar) (env : PegModel.Params)
    (child : PegModel.Expr) (base : Nat) (suffix : List Char) :
    List (List Char) → Prop
  | [] => PegModel.recognizeEnv grammar env base child suffix = .ok none
  | chunk :: rest =>
      PegModel.recognizeEnv grammar env (base + rest.length + 1) child
        ((chunk :: rest).join ++ suffix) =
          .ok (some (rest.join ++ suffix)) ∧
      chunk ≠ [] ∧ CanonicalStarSteps grammar env child base suffix rest

theorem canonical_star_chunks (grammar : PegModel.Grammar) (env : PegModel.Params)
    (child : PegModel.Expr) (base : Nat) (suffix : List Char)
    (chunks : List (List Char))
    (steps : CanonicalStarSteps grammar env child base suffix chunks) :
    PegModel.recognizeEnv grammar env (base + chunks.length + 1)
      (.star child) (chunks.join ++ suffix) = .ok (some suffix) := by
  induction chunks with
  | nil =>
      simp only [List.join_nil, List.nil_append, List.length_nil,
        Nat.add_zero] at steps ⊢
      change (match PegModel.recognizeEnv grammar env base child suffix with
        | Except.error reason => Except.error reason
        | Except.ok none => Except.ok (some suffix)
        | Except.ok (some rest) =>
            if rest.length < suffix.length then
              PegModel.recognizeEnv grammar env base (.star child) rest
            else Except.error "zero-width repetition") = Except.ok (some suffix)
      rw [steps]
  | cons chunk rest ih =>
      obtain ⟨hit, nonempty, more⟩ := steps
      have strict : (rest.join ++ suffix).length <
          ((chunk :: rest).join ++ suffix).length := by
        simp only [List.join_cons, List.length_append]
        have positive : 0 < chunk.length := by
          cases chunk with
          | nil => exact False.elim (nonempty rfl)
          | cons _ _ => simp
        omega
      have fuelEq : base + (chunk :: rest).length + 1 =
          (base + rest.length + 1) + 1 := by simp; omega
      rw [fuelEq]
      change (match PegModel.recognizeEnv grammar env
        (base + rest.length + 1) child ((chunk :: rest).join ++ suffix) with
        | Except.error reason => Except.error reason
        | Except.ok none => Except.ok (some ((chunk :: rest).join ++ suffix))
        | Except.ok (some next) =>
            if next.length < ((chunk :: rest).join ++ suffix).length then
              PegModel.recognizeEnv grammar env (base + rest.length + 1) (.star child) next
            else Except.error "zero-width repetition") = Except.ok (some suffix)
      rw [hit]
      simp only [strict, ↓reduceIte]
      exact ih more

def printedKeywordChunks : List (WordRoundTrip.Word × WordRoundTrip.Word) →
    List (List Char)
  | [] => []
  | (name, value) :: rest =>
      (' ' :: name.chars ++ '=' :: value.chars) :: printedKeywordChunks rest

theorem printedKeywordChunks_join
    (args : List (WordRoundTrip.Word × WordRoundTrip.Word)) (suffix : List Char) :
    WordRoundTrip.printArgs args ++ suffix =
      (printedKeywordChunks args).join ++ '\n' :: suffix := by
  induction args with
  | nil => rfl
  | cons pair rest ih =>
      rcases pair with ⟨name, value⟩
      simp [WordRoundTrip.printArgs, printedKeywordChunks, List.join_cons,
        List.append_assoc, ih]

theorem printedKeywordChunks_length
    (args : List (WordRoundTrip.Word × WordRoundTrip.Word)) :
    (printedKeywordChunks args).length = args.length := by
  induction args with
  | nil => rfl
  | cons pair rest ih =>
      rcases pair with ⟨_, _⟩
      simp [printedKeywordChunks, ih]

def keywordRepetitionChild : PegModel.Expr :=
  .choice [[.ref "Sp" [], .ref "KwArg" [],
    .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])]]

theorem canonical_keyword_child_misses_newline (extra : Nat) (suffix : List Char) :
    PegModel.recognizeEnv Generated.pegGrammar [] (extra + 80)
      keywordRepetitionChild ('\n' :: suffix) = .ok none := by
  rfl

theorem canonical_arg_order_accepts_newline (extra : Nat) (suffix : List Char) :
    PegModel.recognizeEnv Generated.pegGrammar [] (extra + 80)
      (.label (.choice [[.notPred (.choice [[.ref "Sp" [], .ref "PosArg" []]])]])
        "arg_order") ('\n' :: suffix) = .ok (some ('\n' :: suffix)) := by
  rfl

def CanonicalKeywordHits (extra : Nat) (suffix : List Char) :
    List (List Char) → Prop
  | [] => True
  | chunk :: rest =>
      PegModel.recognizeEnv Generated.pegGrammar []
        (extra + 80 + rest.length + 1) keywordRepetitionChild
        ((chunk :: rest).join ++ '\n' :: suffix) =
          .ok (some (rest.join ++ '\n' :: suffix)) ∧
      chunk ≠ [] ∧ CanonicalKeywordHits extra suffix rest

theorem keyword_hits_to_star_steps (extra : Nat) (suffix : List Char)
    (chunks : List (List Char))
    (hits : CanonicalKeywordHits extra suffix chunks) :
    CanonicalStarSteps Generated.pegGrammar [] keywordRepetitionChild
      (extra + 80) ('\n' :: suffix) chunks := by
  induction chunks with
  | nil => exact canonical_keyword_child_misses_newline extra suffix
  | cons chunk rest ih =>
      obtain ⟨hit, nonempty, more⟩ := hits
      exact ⟨hit, nonempty, ih more⟩

-- The actual Arguments keyword repetition has this result for any number of
-- printed arguments and any enclosing suffix once each canonical step and the
-- final miss are supplied.  canonical_star_chunks discharges all repetition,
-- strict-consumption and fuel bookkeeping obligations.
theorem canonical_keyword_repetition
    (args : List (WordRoundTrip.Word × WordRoundTrip.Word))
    (extra : Nat) (suffix : List Char)
    (hits : CanonicalKeywordHits extra suffix (printedKeywordChunks args)) :
    PegModel.recognizeEnv Generated.pegGrammar []
      (extra + 80 + args.length + 1) (.star keywordRepetitionChild)
      (WordRoundTrip.printArgs args ++ suffix) =
        .ok (some ('\n' :: suffix)) := by
  rw [printedKeywordChunks_join args suffix, ← printedKeywordChunks_length args]
  exact canonical_star_chunks Generated.pegGrammar [] keywordRepetitionChild
    (extra + 80) ('\n' :: suffix) (printedKeywordChunks args)
    (keyword_hits_to_star_steps extra suffix (printedKeywordChunks args) hits)

-- Stage 1 fixes the peg-hs AST of Golem.hpeg via Generated.  Stage 2 derives
-- how the Word-valued keyword path consumes each printed argument and leaves
-- an arbitrary suffix.  Stage 3 reuses WordRoundTrip's parse/format theorems.
-- The specialized derivation below is not an equivalence proof for the entire
-- PegModel.recognize interpreter or for the Haskell parser's AST actions.
def ruleItems (name : String) : Option (List (List PegModel.Expr)) :=
  (Generated.pegRules.find? fun rule => rule.name == name).map
    (fun rule => rule.alts.map PegModel.Alt.items)

private theorem arguments_rule :
    ruleItems "Arguments" = some [[
      .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]]),
      .star (.choice [[.ref "Sp" [], .ref "PosArg" [],
        .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])]]),
      .star (.choice [[.ref "Sp" [], .ref "KwArg" [],
        .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])]]),
      .label (.choice [[.notPred (.choice [[.ref "Sp" [], .ref "PosArg" []]])]])
        "arg_order"]] := by
  rfl

private theorem keyword_repetition_is_generated :
    ruleItems "Arguments" = some [[
      .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]]),
      .star (.choice [[.ref "Sp" [], .ref "PosArg" [],
        .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])]]),
      .star keywordRepetitionChild,
      .label (.choice [[.notPred (.choice [[.ref "Sp" [], .ref "PosArg" []]])]])
        "arg_order"]] := by
  rfl

private theorem keyword_argument_rule :
    ruleItems "KeywordArgument" =
      some [[.ref "Word" [], .ref "Eq" [], .ref "ArgValue" []]] := by
  rfl

private theorem argument_value_rule :
    ruleItems "ArgValue" = some [
      [.ref "StringLit" []], [.ref "ExprCtx" []],
      [.ref "ReservedBracket" []], [.ref "InlineCommand" ["0"]],
      [.ref "Word" []]] := by
  rfl

private theorem keyword_wrapper_rule :
    ruleItems "KwArg" = some [
      [.ref "KeywordArgument" []],
      [.andPred (.lit "**[" "'**['"), .ref "SplatArgument" []]] := by
  rfl

def wordShape : List (List PegModel.Expr) := [
  [.lit "%%=" "'%%='",
    .star (.choice [[.notPred (.charClass
      [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
       (91, 91), (34, 34), (92, 92)]
      "[ \\t\\n\\]:|\\[\"\\\\]"), .any]])],
  [.plus (.choice [[.notPred (.charClass
    [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
     (61, 61), (91, 91), (34, 34), (92, 92)]
    "[ \\t\\n\\]:|=\\[\"\\\\]"), .any]])]]

private theorem word_rule : ruleItems "Word" = some wordShape := by
  rfl

private theorem equals_rule : ruleItems "Eq" = some [[.lit "=" "'='"]] := by
  rfl

-- One keyword step of the Word-valued branch: Sp is printed as one space,
-- KeywordArgument is Word Eq ArgValue, and ArgValue chooses Word.  The result
-- includes the unconsumed suffix, unlike the whole-input parseArgs model.
def parseOneWordKeyword : List Char → Option ((List Char × List Char) × List Char)
  | ' ' :: rest =>
      if WordRoundTrip.startsComment rest then none else
      let name := rest.takeWhile WordRoundTrip.allowed
      let afterName := rest.dropWhile WordRoundTrip.allowed
      if name.isEmpty then none else
      match afterName with
      | '=' :: valueStart =>
          let value := valueStart.takeWhile WordRoundTrip.allowed
          let afterValue := valueStart.dropWhile WordRoundTrip.allowed
          if value.isEmpty || WordRoundTrip.containsDoublePercent value then none
          else some ((name, value), afterValue)
      | _ => none
  | _ => none

private theorem not_empty (word : WordRoundTrip.Word) :
    word.chars.isEmpty = false := by
  cases h : word.chars with
  | nil => exact False.elim (word.nonempty h)
  | cons _ _ => rfl

private theorem safe_name_before_equals (name : WordRoundTrip.Word) (tail : List Char)
    (safe : WordRoundTrip.startsComment name.chars = false) :
    WordRoundTrip.startsComment (name.chars ++ '=' :: tail) = false := by
  cases chars : name.chars with
  | nil => exact False.elim (name.nonempty chars)
  | cons c rest =>
      cases rest with
      | nil => simp [WordRoundTrip.startsComment]
      | cons d more =>
          by_cases hc : c = '%'
          · subst c
            by_cases hd : d = '%'
            · subst d
              simp [WordRoundTrip.startsComment, chars] at safe
            · simp [WordRoundTrip.startsComment, hd]
          · simp [WordRoundTrip.startsComment, hc]

private theorem special_prefix_implies_comment (input : List Char)
    (hasPrefix : ("%%=".toList).isPrefixOf input = true) :
    WordRoundTrip.startsComment input = true := by
  cases input with
  | nil => simp [List.isPrefixOf] at hasPrefix
  | cons a rest =>
      cases rest with
      | nil => simp [List.isPrefixOf] at hasPrefix
      | cons b more =>
          simp [List.isPrefixOf] at hasPrefix
          rcases hasPrefix with ⟨ha, hb, _⟩
          subst a
          subst b
          rfl

private theorem safe_name_misses_special (name : WordRoundTrip.Word)
    (tail : List Char)
    (safe : WordRoundTrip.startsComment name.chars = false) :
    ("%%=".toList).isPrefixOf (name.chars ++ '=' :: tail) = false := by
  have guarded := safe_name_before_equals name tail safe
  cases hasPrefix : ("%%=".toList).isPrefixOf (name.chars ++ '=' :: tail) with
  | false => rfl
  | true =>
      have comment := special_prefix_implies_comment _ hasPrefix
      simp [guarded] at comment

theorem canonical_word_before_equals (name : WordRoundTrip.Word)
    (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment name.chars = false) :
    PegModel.recognizeEnv Generated.pegGrammar []
      ((name.chars ++ '=' :: tail).length + 8 + extra)
      (.ref "Word" []) (name.chars ++ '=' :: tail) =
        .ok (some ('=' :: tail)) := by
  have miss := safe_name_misses_special name tail safe
  have dropped : (name.chars ++ '=' :: tail).dropWhile WordRoundTrip.allowed =
      '=' :: tail :=
    WordRoundTrip.drop_append name.chars tail '=' name.valid (by decide)
  cases chars : name.chars with
  | nil => exact False.elim (name.nonempty chars)
  | cons c rest =>
      have miss' : ("%%=".toList).isPrefixOf ((c :: rest) ++ '=' :: tail) = false := by
        simpa only [← chars] using miss
      have model := PegModelTest.generated_word_ordinary_total
        ((c :: rest) ++ '=' :: tail) extra miss'
      rw [← generated_ordinary_ranges] at model
      rw [ordinary_permitted_is_allowed] at model
      have allowed : WordRoundTrip.allowed c = true := name.valid c (by simp [chars])
      have rangeMiss : WordRoundTrip.ordinaryWordRanges.any
          (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = false := by
        rw [WordRoundTrip.ordinary_ranges_allowed, allowed]
        rfl
      have droppedRest : (rest ++ '=' :: tail).dropWhile WordRoundTrip.allowed =
          '=' :: tail := by
        simpa [chars, List.dropWhile, allowed] using dropped
      simpa [chars, rangeMiss, droppedRest] using model

private theorem safe_word_before_separator (word : WordRoundTrip.Word)
    (sep : Char) (tail : List Char)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed sep = false) :
    WordRoundTrip.startsComment (word.chars ++ sep :: tail) = false := by
  have notPercent : sep ≠ '%' := by
    intro equal
    subst sep
    have percentAllowed : WordRoundTrip.allowed '%' = true := by decide
    rw [percentAllowed] at blocked
    cases blocked
  cases chars : word.chars with
  | nil => exact False.elim (word.nonempty chars)
  | cons c rest =>
      cases rest with
      | nil =>
          by_cases hc : c = '%'
          · subst c
            simp [WordRoundTrip.startsComment, notPercent]
          · simp [WordRoundTrip.startsComment, hc]
      | cons d more =>
          by_cases hc : c = '%'
          · subst c
            by_cases hd : d = '%'
            · subst d
              simp [WordRoundTrip.startsComment, chars] at safe
            · simp [WordRoundTrip.startsComment, hd]
          · simp [WordRoundTrip.startsComment, hc]

private theorem safe_word_misses_special (word : WordRoundTrip.Word)
    (sep : Char) (tail : List Char)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed sep = false) :
    ("%%=".toList).isPrefixOf (word.chars ++ sep :: tail) = false := by
  have guarded := safe_word_before_separator word sep tail safe blocked
  cases hasPrefix : ("%%=".toList).isPrefixOf (word.chars ++ sep :: tail) with
  | false => rfl
  | true =>
      have comment := special_prefix_implies_comment _ hasPrefix
      simp [guarded] at comment

theorem canonical_word_before_separator (word : WordRoundTrip.Word)
    (sep : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed sep = false) :
    PegModel.recognizeEnv Generated.pegGrammar []
      ((word.chars ++ sep :: tail).length + 8 + extra)
      (.ref "Word" []) (word.chars ++ sep :: tail) =
        .ok (some (sep :: tail)) := by
  have miss := safe_word_misses_special word sep tail safe blocked
  have dropped : (word.chars ++ sep :: tail).dropWhile WordRoundTrip.allowed =
      sep :: tail := WordRoundTrip.drop_append word.chars tail sep word.valid blocked
  cases chars : word.chars with
  | nil => exact False.elim (word.nonempty chars)
  | cons c rest =>
      have miss' : ("%%=".toList).isPrefixOf ((c :: rest) ++ sep :: tail) = false := by
        simpa only [← chars] using miss
      have model := PegModelTest.generated_word_ordinary_total
        ((c :: rest) ++ sep :: tail) extra miss'
      rw [← generated_ordinary_ranges] at model
      rw [ordinary_permitted_is_allowed] at model
      have allowed : WordRoundTrip.allowed c = true := word.valid c (by simp [chars])
      have rangeMiss : WordRoundTrip.ordinaryWordRanges.any
          (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = false := by
        rw [WordRoundTrip.ordinary_ranges_allowed, allowed]
        rfl
      have droppedRest : (rest ++ sep :: tail).dropWhile WordRoundTrip.allowed =
          sep :: tail := by
        simpa [chars, List.dropWhile, allowed] using dropped
      simpa [chars, rangeMiss, droppedRest] using model

theorem canonical_word_at_budget (word : WordRoundTrip.Word)
    (sep : Char) (tail : List Char) (budget : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed sep = false)
    (enough : (word.chars ++ sep :: tail).length + 8 ≤ budget) :
    PegModel.recognizeEnv Generated.pegGrammar [] budget
      (.ref "Word" []) (word.chars ++ sep :: tail) =
        .ok (some (sep :: tail)) := by
  let extra := budget - ((word.chars ++ sep :: tail).length + 8)
  have eq : (word.chars ++ sep :: tail).length + 8 + extra = budget := by
    dsimp [extra]
    omega
  have result := canonical_word_before_separator word sep tail extra safe blocked
  rw [eq] at result
  exact result

private theorem safe_value_starts_comment (xs : List Char)
    (safe : WordRoundTrip.containsDoublePercent xs = false) :
    WordRoundTrip.startsComment xs = false := by
  cases xs with
  | nil => simp [WordRoundTrip.startsComment]
  | cons c tail =>
      cases tail with
      | nil => simp [WordRoundTrip.startsComment]
      | cons d more =>
          by_cases hc : c = '%'
          · subst c
            by_cases hd : d = '%'
            · subst d
              simp [WordRoundTrip.containsDoublePercent] at safe
            · simp [WordRoundTrip.startsComment, hd]
          · simp [WordRoundTrip.startsComment, hc]

private theorem parse_one_printed
    (name value : WordRoundTrip.Word) (rest suffix : List Char)
    (nameSafe : WordRoundTrip.startsComment name.chars = false)
    (valueSafe : WordRoundTrip.containsDoublePercent value.chars = false)
    (boundary : ∃ sep tail, rest = sep :: tail ∧ WordRoundTrip.allowed sep = false) :
    parseOneWordKeyword (' ' :: name.chars ++ '=' :: value.chars ++ (rest ++ suffix)) =
      some ((name.chars, value.chars), rest ++ suffix) := by
  obtain ⟨sep, tail, printed, blocked⟩ := boundary
  have taken : (value.chars ++ (rest ++ suffix)).takeWhile WordRoundTrip.allowed =
      value.chars := by
    rw [printed]
    exact WordRoundTrip.take_append value.chars (tail ++ suffix) sep value.valid blocked
  have dropped : (value.chars ++ (rest ++ suffix)).dropWhile WordRoundTrip.allowed =
      rest ++ suffix := by
    rw [printed]
    exact WordRoundTrip.drop_append value.chars (tail ++ suffix) sep value.valid blocked
  have guarded := safe_name_before_equals name (value.chars ++ (rest ++ suffix)) nameSafe
  simp [parseOneWordKeyword,
    WordRoundTrip.take_append name.chars (value.chars ++ (rest ++ suffix)) '='
      name.valid (by decide : WordRoundTrip.allowed '=' = false),
    WordRoundTrip.drop_append name.chars (value.chars ++ (rest ++ suffix)) '='
      name.valid (by decide : WordRoundTrip.allowed '=' = false),
    not_empty name, not_empty value, guarded, valueSafe, taken, dropped]

-- A derivation in the generated PEG's restricted Word-valued keyword path.
-- Each step checks the actual extracted rule shapes and consumes one keyword
-- with parseOneWordKeyword.  Arguments stops before the newline; the newline
-- belongs to its enclosing command production.
inductive PegWordKeywordDerives : List Char → List Char → List (List Char × List Char) → Prop where
  | done (suffix : List Char)
      (arguments : ruleItems "Arguments" = some [[
        .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]]),
        .star (.choice [[.ref "Sp" [], .ref "PosArg" [],
          .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])]]),
        .star (.choice [[.ref "Sp" [], .ref "KwArg" [],
          .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])]]),
        .label (.choice [[.notPred (.choice [[.ref "Sp" [], .ref "PosArg" []]])]])
          "arg_order"]]) :
      PegWordKeywordDerives suffix suffix []
  | step (input remaining suffix : List Char) (name value : List Char)
      (rest : List (List Char × List Char))
      (wrapper : ruleItems "KwArg" = some [
        [.ref "KeywordArgument" []],
        [.andPred (.lit "**[" "'**['"), .ref "SplatArgument" []]])
      (keyword : ruleItems "KeywordArgument" =
        some [[.ref "Word" [], .ref "Eq" [], .ref "ArgValue" []]])
      (word : ruleItems "Word" = some wordShape)
      (equals : ruleItems "Eq" = some [[.lit "=" "'='"]])
      (valueRule : ruleItems "ArgValue" = some [
        [.ref "StringLit" []], [.ref "ExprCtx" []],
        [.ref "ReservedBracket" []], [.ref "InlineCommand" ["0"]],
        [.ref "Word" []]])
      (one : parseOneWordKeyword input = some ((name, value), remaining))
      (more : PegWordKeywordDerives remaining suffix rest) :
      PegWordKeywordDerives input suffix ((name, value) :: rest)

theorem derived_printed_sequence (args : List (WordRoundTrip.Word × WordRoundTrip.Word))
    (suffix : List Char) (namesSafe : WordRoundTrip.safeNames args)
    (valuesSafe : WordRoundTrip.safeValues args) :
    PegWordKeywordDerives (WordRoundTrip.printArgs args ++ suffix) ('\n' :: suffix)
      (args.map fun (name, value) => (name.chars, value.chars)) := by
  induction args with
  | nil =>
      simpa [WordRoundTrip.printArgs] using
        PegWordKeywordDerives.done ('\n' :: suffix) arguments_rule
  | cons pair rest ih =>
      rcases pair with ⟨name, value⟩
      have nameSafe : WordRoundTrip.startsComment name.chars = false :=
        namesSafe (name, value) (by simp)
      have valueSafe : WordRoundTrip.containsDoublePercent value.chars = false :=
        valuesSafe (name, value) (by simp)
      have restNames : WordRoundTrip.safeNames rest := by
        intro pair member
        exact namesSafe pair (by simp [member])
      have restValues : WordRoundTrip.safeValues rest := by
        intro pair member
        exact valuesSafe pair (by simp [member])
      have one := parse_one_printed name value (WordRoundTrip.printArgs rest) suffix
        nameSafe valueSafe (WordRoundTrip.printed_tail rest)
      have more := ih restNames restValues
      simpa [WordRoundTrip.printArgs, List.cons_append, List.append_assoc] using
        PegWordKeywordDerives.step
          (' ' :: name.chars ++ '=' :: value.chars ++
            (WordRoundTrip.printArgs rest ++ suffix))
          (WordRoundTrip.printArgs rest ++ suffix) ('\n' :: suffix) name.chars value.chars
          (rest.map fun (name, value) => (name.chars, value.chars))
          keyword_wrapper_rule keyword_argument_rule word_rule equals_rule
          argument_value_rule one more

-- I1 and I4 for arbitrary finite sequences in the actual PEG's Word-valued
-- keyword branch.  The WordRoundTrip hypotheses exclude comment-like names
-- and proof-comment text inside values; the theorem does not claim that PEG
-- actions, positional arguments, splats or quoted values share this model.
theorem I1_I4_peg_word_keyword_sequences
    (args : List (WordRoundTrip.Word × WordRoundTrip.Word)) (fuel : Nat)
    (namesSafe : WordRoundTrip.safeNames args)
    (valuesSafe : WordRoundTrip.safeValues args)
    (enough : args.length ≤ fuel) :
    ruleItems "Arguments" = some [[
      .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]]),
      .star (.choice [[.ref "Sp" [], .ref "PosArg" [],
        .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])]]),
      .star (.choice [[.ref "Sp" [], .ref "KwArg" [],
        .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])]]),
      .label (.choice [[.notPred (.choice [[.ref "Sp" [], .ref "PosArg" []]])]])
        "arg_order"]] ∧
    ruleItems "KwArg" = some [
      [.ref "KeywordArgument" []],
      [.andPred (.lit "**[" "'**['"), .ref "SplatArgument" []]] ∧
    ruleItems "KeywordArgument" =
      some [[.ref "Word" [], .ref "Eq" [], .ref "ArgValue" []]] ∧
    ruleItems "Word" = some wordShape ∧
    ruleItems "Eq" = some [[.lit "=" "'='"]] ∧
    ruleItems "ArgValue" = some [
      [.ref "StringLit" []], [.ref "ExprCtx" []],
      [.ref "ReservedBracket" []], [.ref "InlineCommand" ["0"]],
      [.ref "Word" []]] ∧
    WordRoundTrip.parseArgs fuel (WordRoundTrip.printArgs args) =
      some (args.map fun (name, value) => (name.chars, value.chars)) ∧
    (WordRoundTrip.format fuel (WordRoundTrip.printArgs args)).bind
      (WordRoundTrip.parseArgs fuel) =
      some (args.map fun (name, value) => (name.chars, value.chars)) ∧
    ∀ suffix, PegWordKeywordDerives (WordRoundTrip.printArgs args ++ suffix) ('\n' :: suffix)
      (args.map fun (name, value) => (name.chars, value.chars)) := by
  obtain ⟨parsed, reformatted⟩ :=
    WordRoundTrip.I4_word_keyword_sequences args fuel namesSafe valuesSafe enough
  exact ⟨arguments_rule, keyword_wrapper_rule, keyword_argument_rule,
    word_rule, equals_rule, argument_value_rule, parsed, reformatted,
    fun suffix => derived_printed_sequence args suffix namesSafe valuesSafe⟩

-- Canonical PegModel ref: a successful KeywordArgument chooses the first
-- KwArg branch, without evaluating its splat fallback.
theorem canonical_kwarg_of_keyword (fuel : Nat) (input rest : List Char)
    (hit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "KeywordArgument" []) input = .ok (some rest)) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
      (.ref "KwArg" []) input = .ok (some rest) := by
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 1) item source)
      _ [] items input)
    [[.ref "KeywordArgument" []],
      [.andPred (.lit "**[" "'**['"), .ref "SplatArgument" []]] = .ok (some rest)
  simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
    hit, Except.map] <;> rfl

-- Canonical PegModel ref: once Word Eq succeeds, both PosArg alternatives
-- fail their ordered negative lookahead.
theorem canonical_posarg_rejects_keyword (fuel : Nat) (input afterEq : List Char)
    (noProofPrefix : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.lit "%%" "'%%'") input = .ok none)
    (wordEq : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.choice [[.ref "Word" [], .ref "Eq" []]]) input = .ok (some afterEq)) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 4)
      (.ref "PosArg" []) input = .ok none := by
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 2) item source)
      _ [] items input)
    [[.notPred (.lit "%%" "'%%'"),
      .notPred (.choice [[.ref "Word" [], .ref "Eq" []]]),
      .notPred (.lit "**[" "'**['"), .ref "SplatArgument" []],
     [.notPred (.lit "%%" "'%%'"),
      .notPred (.choice [[.ref "Word" [], .ref "Eq" []]]),
      .notPred (.ref "Splat" []), .ref "Argument" []]] = .ok none
  have noPrefix : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 2)
      (.notPred (.lit "%%" "'%%'")) input = .ok (some input) := by
    change (match PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.lit "%%" "'%%'") input with
      | .error reason => Except.error reason
      | .ok none => Except.ok (some input)
      | .ok (some _) => Except.ok none) = Except.ok (some input)
    rw [noProofPrefix]
  have noPos : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 2)
      (.notPred (.choice [[.ref "Word" [], .ref "Eq" []]])) input = .ok none := by
    change (match PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.choice [[.ref "Word" [], .ref "Eq" []]]) input with
      | .error reason => Except.error reason
      | .ok none => Except.ok (some input)
      | .ok (some _) => Except.ok none) = Except.ok none
    rw [wordEq]
  simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
    noPrefix, noPos, Except.map] <;> rfl

-- Canonical PegModel ref: ArgValue reaches Word only after its four earlier
-- alternatives fail.  Their failure is an explicit premise, not inferred
-- from the WordRoundTrip validity predicate.
theorem canonical_argvalue_word (fuel : Nat) (input rest : List Char)
    (notString : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "StringLit" []) input = .ok none)
    (notExpr : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "ExprCtx" []) input = .ok none)
    (notReserved : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "ReservedBracket" []) input = .ok none)
    (notInline : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "InlineCommand" ["0"]) input = .ok none)
    (word : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "Word" []) input = .ok (some rest)) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
      (.ref "ArgValue" []) input = .ok (some rest) := by
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 1) item source)
      _ [] items input)
    [[.ref "StringLit" []], [.ref "ExprCtx" []], [.ref "ReservedBracket" []],
     [.ref "InlineCommand" ["0"]], [.ref "Word" []]] = .ok (some rest)
  simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
    notString, notExpr, notReserved, notInline, word, Except.map] <;> rfl

set_option maxHeartbeats 1000000 in
theorem canonical_argvalue_of_safe_word (value : WordRoundTrip.Word)
    (sep : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.containsDoublePercent value.chars = false)
    (blocked : WordRoundTrip.allowed sep = false) :
    let input := value.chars ++ sep :: tail
    PegModel.recognizeEnv Generated.pegGrammar []
      (input.length + extra + 10) (.ref "ArgValue" []) input =
        .ok (some (sep :: tail)) := by
  dsimp only
  have safeStart := safe_value_starts_comment value.chars safe
  have word := canonical_word_before_separator value sep tail extra safeStart blocked
  cases chars : value.chars with
  | nil => exact False.elim (value.nonempty chars)
  | cons c rest =>
      have allowed : WordRoundTrip.allowed c = true := value.valid c (by simp [chars])
      have misses := WordRoundTrip.ordinary_value_precedence
        ((value.chars ++ sep :: tail).length + extra) c (rest ++ sep :: tail) allowed
      rcases misses with ⟨notString, notExpr, notReserved, notInline⟩
      have inputEq : value.chars ++ sep :: tail = c :: (rest ++ sep :: tail) := by
        simp [chars]
      rw [← inputEq] at notString notExpr notReserved notInline
      have fuelWord : (value.chars ++ sep :: tail).length + 8 + extra =
          ((value.chars ++ sep :: tail).length + extra + 7) + 1 := by omega
      have fuelMiss : (value.chars ++ sep :: tail).length + extra + 8 =
          ((value.chars ++ sep :: tail).length + extra + 7) + 1 := by omega
      rw [fuelWord] at word
      rw [fuelMiss] at notString notExpr notReserved notInline
      have result := canonical_argvalue_word
        ((value.chars ++ sep :: tail).length + extra + 7)
        (value.chars ++ sep :: tail) (sep :: tail)
        notString notExpr notReserved notInline word
      have fuelResult : ((value.chars ++ sep :: tail).length + extra + 7) + 3 =
          (value.chars ++ sep :: tail).length + extra + 10 := by omega
      rw [fuelResult] at result
      simpa only [chars] using result

theorem canonical_argvalue_at_budget (value : WordRoundTrip.Word)
    (sep : Char) (tail : List Char) (budget : Nat)
    (safe : WordRoundTrip.containsDoublePercent value.chars = false)
    (blocked : WordRoundTrip.allowed sep = false)
    (enough : (value.chars ++ sep :: tail).length + 10 ≤ budget) :
    PegModel.recognizeEnv Generated.pegGrammar [] budget
      (.ref "ArgValue" []) (value.chars ++ sep :: tail) =
        .ok (some (sep :: tail)) := by
  let extra := budget - ((value.chars ++ sep :: tail).length + 10)
  have eq : (value.chars ++ sep :: tail).length + extra + 10 = budget := by
    dsimp [extra]
    omega
  have result := canonical_argvalue_of_safe_word value sep tail extra safe blocked
  dsimp only at result
  rw [eq] at result
  exact result

-- Canonical PegModel ref: the three recognized pieces compose in the only
-- KeywordArgument branch, with the suffix returned by ArgValue.
theorem canonical_keyword_of_parts (fuel : Nat)
    (input afterName afterEq rest : List Char)
    (nameHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "Word" []) input = .ok (some afterName))
    (eqHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "Eq" []) afterName = .ok (some afterEq))
    (valueHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "ArgValue" []) afterEq = .ok (some rest)) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
      (.ref "KeywordArgument" []) input = .ok (some rest) := by
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 1) item source)
      _ [] items input)
    [[.ref "Word" [], .ref "Eq" [], .ref "ArgValue" []]] = .ok (some rest)
  simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
    nameHit, eqHit, valueHit, Except.map] <;> rfl

-- Conditional refinement of parseOneWordKeyword to the actual canonical
-- KwArg ref.  The separate Word/Eq/ArgValue recognition premises still need
-- to be discharged for every valid Word pair before this is a general bridge.
theorem canonical_kwarg_matches_parseOne_given_parts (fuel : Nat)
    (input afterName afterEq rest name value : List Char)
    (_one : parseOneWordKeyword (' ' :: input) = some ((name, value), rest))
    (nameHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "Word" []) input = .ok (some afterName))
    (eqHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "Eq" []) afterName = .ok (some afterEq))
    (valueHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "ArgValue" []) afterEq = .ok (some rest)) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 5)
      (.ref "KwArg" []) input = .ok (some rest) := by
  have keyword := canonical_keyword_of_parts fuel input afterName afterEq rest
    nameHit eqHit valueHit
  simpa [Nat.add_assoc] using canonical_kwarg_of_keyword (fuel + 2) input rest keyword

-- The actual PEG sequence for a keyword step composes its Sp and KwArg refs.
-- The caller still has to establish both recognizer results at this fuel.
theorem canonical_sp_kwarg_step (fuel : Nat) (input afterSpace rest : List Char)
    (spaceHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "Sp" []) input = .ok (some afterSpace))
    (keywordHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "KwArg" []) afterSpace = .ok (some rest)) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 2)
      (.choice [[.ref "Sp" [], .ref "KwArg" []]]) input = .ok (some rest) := by
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 1) item source)
      _ [] items input)
    [[.ref "Sp" [], .ref "KwArg" []]] = .ok (some rest)
  simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
    spaceHit, keywordHit, Except.map] <;> rfl

theorem canonical_keyword_child_of_parts (fuel : Nat)
    (input afterSpace afterKeyword rest : List Char)
    (spaceHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "Sp" []) input = .ok (some afterSpace))
    (keywordHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.ref "KwArg" []) afterSpace = .ok (some afterKeyword))
    (commentsHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])) afterKeyword =
        .ok (some rest)) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 2)
      keywordRepetitionChild input = .ok (some rest) := by
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 1) item source)
      _ [] items input)
    [[.ref "Sp" [], .ref "KwArg" [],
      .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])]] = .ok (some rest)
  simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
    spaceHit, keywordHit, commentsHit, Except.map] <;> rfl

private theorem canonical_eq_any (fuel : Nat) (tail : List Char) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
      (.ref "Eq" []) ('=' :: tail) = .ok (some tail) := by
  have literal : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 1)
      (.lit "=" "'='") ('=' :: tail) = .ok (some tail) := by
    have total := PegModelTest.literal_total Generated.pegGrammar []
      fuel "=" "'='" ('=' :: tail)
    simpa [List.isPrefixOf] using total
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 1) item source)
      _ [] items ('=' :: tail)) [[.lit "=" "'='"]] = .ok (some tail)
  simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence,
    literal, Except.map] <;> rfl

theorem canonical_printed_keyword_step
    (name value : WordRoundTrip.Word) (sep : Char) (tail : List Char)
    (budget : Nat)
    (nameSafe : WordRoundTrip.startsComment name.chars = false)
    (valueSafe : WordRoundTrip.containsDoublePercent value.chars = false)
    (blocked : WordRoundTrip.allowed sep = false)
    (enough : (' ' :: name.chars ++ '=' :: value.chars ++ sep :: tail).length + 20 ≤ budget)
    (comments : PegModel.recognizeEnv Generated.pegGrammar [] (budget - 1)
      (.star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])) (sep :: tail) =
        .ok (some (sep :: tail))) :
    PegModel.recognizeEnv Generated.pegGrammar [] budget keywordRepetitionChild
      (' ' :: name.chars ++ '=' :: value.chars ++ sep :: tail) =
        .ok (some (sep :: tail)) := by
  have nameEnough : (name.chars ++ '=' :: value.chars ++ sep :: tail).length + 8 ≤
      budget - 5 := by
    simp only [List.length_append, List.length_cons] at enough ⊢
    omega
  have valueEnough : (value.chars ++ sep :: tail).length + 10 ≤ budget - 5 := by
    simp only [List.length_append, List.length_cons] at enough ⊢
    omega
  have nameHit := canonical_word_at_budget name '=' (value.chars ++ sep :: tail)
    (budget - 5) nameSafe (by decide) (by
      simpa only [List.append_assoc] using nameEnough)
  have valueHit := canonical_argvalue_at_budget value sep tail (budget - 5)
    valueSafe blocked valueEnough
  have eqHit : PegModel.recognizeEnv Generated.pegGrammar [] (budget - 5)
      (.ref "Eq" []) ('=' :: value.chars ++ sep :: tail) =
        .ok (some (value.chars ++ sep :: tail)) := by
    have fuelEq : budget - 5 = (budget - 8) + 3 := by omega
    rw [fuelEq]
    exact canonical_eq_any (budget - 8) (value.chars ++ sep :: tail)
  cases chars : name.chars with
  | nil => exact False.elim (name.nonempty chars)
  | cons c rest =>
      have valid : WordRoundTrip.allowed c = true := name.valid c (by simp [chars])
      have space := WordRoundTrip.canonical_space_before_word
        (budget - 11) c (rest ++ '=' :: value.chars ++ sep :: tail) valid
      have fSpace : budget - 11 + 10 = budget - 1 := by omega
      rw [fSpace] at space
      have fParts : budget - 6 + 1 = budget - 5 := by omega
      rw [← fParts] at nameHit eqHit valueHit
      have nameHit' : PegModel.recognizeEnv Generated.pegGrammar [] (budget - 6 + 1)
          (.ref "Word" []) (name.chars ++ '=' :: value.chars ++ sep :: tail) =
            .ok (some ('=' :: value.chars ++ sep :: tail)) := by
        simpa only [List.append_assoc] using nameHit
      have keyword := canonical_keyword_of_parts (budget - 6)
        (name.chars ++ '=' :: value.chars ++ sep :: tail)
        ('=' :: value.chars ++ sep :: tail)
        (value.chars ++ sep :: tail) (sep :: tail)
        nameHit' eqHit valueHit
      have fKeyword : budget - 6 + 3 = budget - 3 := by omega
      rw [fKeyword] at keyword
      have fKwInput : budget - 4 + 1 = budget - 3 := by omega
      rw [← fKwInput] at keyword
      have kw := canonical_kwarg_of_keyword (budget - 4)
        (name.chars ++ '=' :: value.chars ++ sep :: tail) (sep :: tail) keyword
      have fKw : budget - 4 + 3 = budget - 1 := by omega
      rw [fKw] at kw
      have fChild : budget - 2 + 1 = budget - 1 := by omega
      rw [← fChild] at space kw comments
      have space' : PegModel.recognizeEnv Generated.pegGrammar [] (budget - 2 + 1)
          (.ref "Sp" []) (' ' :: name.chars ++ '=' :: value.chars ++ sep :: tail) =
            .ok (some (name.chars ++ '=' :: value.chars ++ sep :: tail)) := by
        simpa only [chars, List.append_assoc] using space
      have child := canonical_keyword_child_of_parts (budget - 2)
        (' ' :: name.chars ++ '=' :: value.chars ++ sep :: tail)
        (name.chars ++ '=' :: value.chars ++ sep :: tail)
        (sep :: tail) (sep :: tail) space' kw comments
      have fDone : budget - 2 + 2 = budget := by omega
      rw [fDone] at child
      simpa only [chars] using child

theorem canonical_comments_on_printed_tail
    (args : List (WordRoundTrip.Word × WordRoundTrip.Word))
    (suffix : List Char) (budget : Nat)
    (safe : WordRoundTrip.safeNames args)
    (enough : 80 ≤ budget) :
    PegModel.recognizeEnv Generated.pegGrammar [] budget
      (.star (.choice [[.ref "Sp" [], .ref "ArgComment" []]]))
      (WordRoundTrip.printArgs args ++ suffix) =
        .ok (some (WordRoundTrip.printArgs args ++ suffix)) := by
  cases args with
  | nil =>
      have budgetEq : budget = (budget - 80) + 80 := by omega
      rw [budgetEq]
      simp only [WordRoundTrip.printArgs, List.singleton_append]
      rfl
  | cons pair rest =>
      rcases pair with ⟨name, value⟩
      have nameSafe : WordRoundTrip.startsComment name.chars = false :=
        safe (name, value) (by simp)
      have result := WordRoundTrip.comments_before_keyword
        (budget - 12) name (value.chars ++ WordRoundTrip.printArgs rest ++ suffix)
        nameSafe
      have budgetEq : budget - 12 + 12 = budget := by omega
      rw [budgetEq] at result
      simpa [WordRoundTrip.printArgs, List.append_assoc] using result

theorem canonical_keyword_hits_of_printed
    (args : List (WordRoundTrip.Word × WordRoundTrip.Word))
    (suffix : List Char) :
    ∀ extra, (WordRoundTrip.printArgs args ++ suffix).length ≤ extra →
      WordRoundTrip.safeNames args → WordRoundTrip.safeValues args →
      CanonicalKeywordHits extra suffix (printedKeywordChunks args) := by
  induction args with
  | nil =>
      intro _ _ _ _
      trivial
  | cons pair rest ih =>
      intro extra bound namesSafe valuesSafe
      rcases pair with ⟨name, value⟩
      have nameSafe : WordRoundTrip.startsComment name.chars = false :=
        namesSafe (name, value) (by simp)
      have valueSafe : WordRoundTrip.containsDoublePercent value.chars = false :=
        valuesSafe (name, value) (by simp)
      have restNames : WordRoundTrip.safeNames rest := by
        intro pair member
        exact namesSafe pair (by simp [member])
      have restValues : WordRoundTrip.safeValues rest := by
        intro pair member
        exact valuesSafe pair (by simp [member])
      have restBound : (WordRoundTrip.printArgs rest ++ suffix).length ≤ extra := by
        simp only [WordRoundTrip.printArgs, List.length_append, List.length_cons] at bound
        simp only [List.length_append]
        omega
      have more := ih extra restBound restNames restValues
      obtain ⟨sep, tail, printed, blocked⟩ := WordRoundTrip.printed_tail rest
      let budget := extra + 80 + (printedKeywordChunks rest).length + 1
      have commentBudget : 80 ≤ budget - 1 := by
        dsimp [budget]
        omega
      have comments := canonical_comments_on_printed_tail rest suffix
        (budget - 1) restNames commentBudget
      have comments' : PegModel.recognizeEnv Generated.pegGrammar [] (budget - 1)
          (.star (.choice [[.ref "Sp" [], .ref "ArgComment" []]]))
          (sep :: (tail ++ suffix)) = .ok (some (sep :: (tail ++ suffix))) := by
        simpa [printed, List.cons_append, List.append_assoc] using comments
      have enough : (' ' :: name.chars ++ '=' :: value.chars ++ sep :: (tail ++ suffix)).length +
          20 ≤ budget := by
        have same : ' ' :: name.chars ++ '=' :: value.chars ++ sep :: (tail ++ suffix) =
            WordRoundTrip.printArgs ((name, value) :: rest) ++ suffix := by
          simp [WordRoundTrip.printArgs, printed, List.append_assoc]
        rw [same]
        dsimp [budget]
        omega
      have step := canonical_printed_keyword_step name value sep (tail ++ suffix)
        budget nameSafe valueSafe blocked enough comments'
      have normalized : PegModel.recognizeEnv Generated.pegGrammar [] budget
          keywordRepetitionChild (WordRoundTrip.printArgs ((name, value) :: rest) ++ suffix) =
            .ok (some (WordRoundTrip.printArgs rest ++ suffix)) := by
        simpa [WordRoundTrip.printArgs, printed, List.append_assoc] using step
      have wholeJoin := printedKeywordChunks_join ((name, value) :: rest) suffix
      have restJoin := printedKeywordChunks_join rest suffix
      rw [wholeJoin, restJoin] at normalized
      change PegModel.recognizeEnv Generated.pegGrammar [] budget keywordRepetitionChild
        ((printedKeywordChunks ((name, value) :: rest)).join ++ '\n' :: suffix) =
          .ok (some ((printedKeywordChunks rest).join ++ '\n' :: suffix)) ∧
        (' ' :: name.chars ++ '=' :: value.chars) ≠ [] ∧
        CanonicalKeywordHits extra suffix (printedKeywordChunks rest)
      exact ⟨normalized, by simp, more⟩

-- Concrete checks of the canonical PegModel ref, including Sp, ordered
-- PosArg rejection, KwArg selection and the newline left for the command.
-- The arbitrary-length theorem above is for the restricted derivation; these
-- checks do not establish its equivalence with PegModel.recognize for all input.
example : PegModel.recognize Generated.pegGrammar 80 (.ref "Sp" [])
    " a=x\n".toList = .ok (some "a=x\n".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 80 (.ref "PosArg" [])
    "a=x\n".toList = .ok none := by rfl

example : PegModel.recognize Generated.pegGrammar 80 (.ref "KwArg" [])
    "a=x\n".toList = .ok (some "\n".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 80 (.ref "ArgComment" [])
    "\n".toList = .ok none := by rfl

example : PegModel.recognize Generated.pegGrammar 80 (.ref "Arguments" [])
    "\n".toList = .ok (some "\n".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 80 (.ref "Arguments" [])
    " a=x\n".toList = .ok (some "\n".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 120 (.ref "Arguments" [])
    " a=x b=y c=z\n".toList = .ok (some "\n".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 80 (.ref "Arguments" [])
    " a=x q\n".toList = .ok none := by rfl

end ArgumentsRoundTrip
