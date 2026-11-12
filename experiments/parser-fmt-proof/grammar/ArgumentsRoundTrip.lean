import WordRoundTrip

namespace ArgumentsRoundTrip

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
