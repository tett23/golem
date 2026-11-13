import PegModelTest

namespace WordRoundTrip

def allowed (c : Char) : Bool := !(Generated.wordForbidden.contains c)

def ordinaryWordRanges : List (Nat × Nat) :=
  Generated.wordForbidden.map (fun c => (c.toNat, c.toNat))

theorem singleton_ranges_match (chars : List Char) (c : Char) :
    (chars.map (fun d => (d.toNat, d.toNat))).any
      (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = chars.contains c := by
  induction chars with
  | nil => rfl
  | cons d rest ih =>
    simp only [List.map_cons, List.any_cons, List.contains, List.elem, ih]
    by_cases h : d = c
    · subst d; simp
    · have ne : d.toNat ≠ c.toNat := by
        intro eq
        apply h
        cases d with
        | mk x hx =>
          cases c with
          | mk y hy =>
            cases x with
            | mk u =>
              cases y with
              | mk v =>
                have uv : u = v := Fin.ext eq
                subst v
                rfl
      have cd : (c == d) = false := by
        cases e : (c == d)
        · rfl
        · exact False.elim (h (eq_of_beq e).symm)
      rw [cd]
      rcases Nat.lt_or_gt_of_ne ne with lt | gt
      · simp [Nat.not_le_of_gt lt]
      · simp [Nat.not_le_of_gt gt]

theorem ordinary_ranges_allowed (c : Char) :
    ordinaryWordRanges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) = !allowed c := by
  rw [ordinaryWordRanges, singleton_ranges_match]
  simp [allowed]

private theorem space_forbidden : allowed ' ' = false := by decide
private theorem equals_forbidden : allowed '=' = false := by decide
private theorem newline_forbidden : allowed '\n' = false := by decide

private theorem first_misses (parse : PegModel.Params → PegModel.Expr → List Char → PegModel.ParseResult)
    (bound : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (env : PegModel.Params) (head : PegModel.Expr) (tail : List PegModel.Expr) (input : List Char)
    (miss : parse env head input = .ok none) :
    PegModel.runChoices (fun items => PegModel.runSequence parse bound env items input)
      [head :: tail] = .ok none := by
  suffices h : PegModel.runSequence parse bound env (head :: tail) input = .ok none by
    simp [PegModel.runChoices, PegModel.foldChoice, List.foldlM, h]
  simp [PegModel.runSequence, List.foldlM, miss]
  induction tail with
  | nil => rfl
  | cons _ rest ih => simpa [List.foldlM] using ih
private theorem literal_misses (fuel : Nat) (env : PegModel.Params) (value written : String)
    (input : List Char) (miss : value.toList.isPrefixOf input = false) :
    PegModel.recognizeEnv Generated.pegGrammar env (fuel+1) (.lit value written) input = .ok none := by
  simp [PegModel.recognizeEnv, miss]; rfl

set_option maxRecDepth 8192 in
theorem ordinary_value_precedence (fuel : Nat) (c : Char) (tail : List Char)
    (valid : allowed c = true) :
    let misses := fun name args => PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 8)
      (.ref name args) (c :: tail) = .ok none
    misses "StringLit" [] ∧ misses "ExprCtx" [] ∧ misses "ReservedBracket" [] ∧
      misses "InlineCommand" ["0"] := by
  have unequal (a : Char) (blocked : allowed a = false) : (a == c) = false := by
    cases h : (a == c) with
    | false => rfl
    | true => have he := eq_of_beq h; subst a; simp_all
  have q := unequal '"' (by decide)
  have b := unequal '[' (by decide)
  dsimp only
  constructor
  · apply first_misses (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+6) item s) _ [] (.lit "\"" "'\"'") _ (c :: tail)
    apply literal_misses
    change (['"'].isPrefixOf (c :: tail)) = false
    simp [List.isPrefixOf,q]
  · constructor
    · apply first_misses (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+6) item s) _ [] (.ref "ExprOpen" []) _ (c :: tail)
      apply first_misses (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+4) item s) _ [] (.lit "[=" "'[='") _ (c :: tail)
      apply literal_misses
      change ['[','='].isPrefixOf (c :: tail) = false
      simp [List.isPrefixOf,b]
    · constructor
      · apply first_misses (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+6) item s) _ [] (.andPred (.lit "[!" "'[!'")) _ (c :: tail)
        have mh := literal_misses (fuel+4) [] "[!" "'[!'" (c :: tail) (by
          change ['[','!'].isPrefixOf (c :: tail) = false
          simp [List.isPrefixOf,b])
        change (match PegModel.recognizeEnv Generated.pegGrammar [] (fuel+5) (.lit "[!" "'[!'") (c :: tail) with
          | .error e => if PegModel.isLabelFailure e then Except.ok none else Except.error e
          | .ok none => Except.ok none
          | .ok (some _) => Except.ok (some (c :: tail))) = _
        rw [mh]
      · apply first_misses (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+6) item s) _ [("ind",0)] (.ref "LBr" []) _ (c :: tail)
        apply first_misses (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+4) item s) _ [] (.lit "[" "'['") _ (c :: tail)
        apply literal_misses
        change ['['].isPrefixOf (c :: tail) = false
        simp [List.isPrefixOf,b]

structure Word where
  chars : List Char
  valid : ∀ c ∈ chars, allowed c = true
  nonempty : chars ≠ []

def startsComment : List Char → Bool
  | '%' :: '%' :: _ => true
  | _ => false

theorem safe_comment_prefixes (input : List Char) (safe : startsComment input = false) :
    "%%".toList.isPrefixOf input = false ∧ "%%=".toList.isPrefixOf input = false := by
  cases input with
  | nil => decide
  | cons c rest =>
    by_cases hc : c = '%'
    · subst c
      cases rest with
      | nil => decide
      | cons d tail =>
        have hd : d ≠ '%' := by intro h; subst d; contradiction
        have hb : ('%' == d) = false := by
          cases h : ('%' == d)
          · rfl
          · exact False.elim (hd (eq_of_beq h).symm)
        change ['%', '%'].isPrefixOf ('%' :: d :: tail) = false ∧
          ['%', '%', '='].isPrefixOf ('%' :: d :: tail) = false
        simp [List.isPrefixOf, hb]
    · have hb : ('%' == c) = false := by
        cases h : ('%' == c)
        · rfl
        · exact False.elim (hc (eq_of_beq h).symm)
      change ['%', '%'].isPrefixOf (c :: rest) = false ∧ ['%', '%', '='].isPrefixOf (c :: rest) = false
      simp [List.isPrefixOf, hb]

theorem ordinary_comment_misses (fuel : Nat) (input : List Char)
    (safe : startsComment input = false) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 8)
      (.ref "ArgComment" []) input = .ok none := by
  have prefixes := safe_comment_prefixes input safe
  have proofMiss : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 6)
      (.ref "ProofComment" []) input = .ok none := by
    apply first_misses (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+4) item s) _ [] (.lit "%%=" "'%%='") _ input
    exact literal_misses _ _ _ _ _ prefixes.2
  have ordinaryMiss : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 6)
      (.ref "Comment" []) input = .ok none := by
    apply first_misses (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+4) item s) _ [] (.lit "%%" "'%%'") _ input
    exact literal_misses _ _ _ _ _ prefixes.1
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+6) item s)
      _ [] items input) [[.ref "ProofComment" []], [.ref "Comment" []]] = .ok none
  simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, List.foldlM, proofMiss, ordinaryMiss, Except.map] <;> rfl

def containsDoublePercent : List Char → Bool
  | '%' :: '%' :: _ => true
  | _ :: tail => containsDoublePercent tail
  | [] => false

def safeNames (args : List (Word × Word)) : Prop :=
  ∀ pair ∈ args, startsComment pair.1.chars = false

def safeValues (args : List (Word × Word)) : Prop :=
  ∀ pair ∈ args, containsDoublePercent pair.2.chars = false

theorem safe_name_before_equals (name : Word) (tail : List Char)
    (safe : startsComment name.chars = false) :
    startsComment (name.chars ++ '=' :: tail) = false := by
  cases chars : name.chars with
  | nil => exact False.elim (name.nonempty chars)
  | cons c rest =>
      cases rest with
      | nil => simp [startsComment]
      | cons d more =>
          by_cases hc : c = '%'
          · subst c
            by_cases hd : d = '%'
            · subst d
              simp [startsComment, chars] at safe
            · simp [startsComment, hd]
          · simp [startsComment, hc]

def printArgs : List (Word × Word) → List Char
  | [] => ['\n']
  | (name, value) :: rest => ' ' :: name.chars ++ '=' :: value.chars ++ printArgs rest

def parseArgs : Nat → List Char → Option (List (List Char × List Char))
  | _, ['\n'] => some []
  | fuel + 1, ' ' :: rest =>
      if startsComment rest then none else
      let name := rest.takeWhile allowed
      let afterName := rest.dropWhile allowed
      if name.isEmpty then none
      else
        match afterName with
        | '=' :: valueStart =>
            let value := valueStart.takeWhile allowed
            let afterValue := valueStart.dropWhile allowed
            if value.isEmpty || containsDoublePercent value then none
            else (parseArgs fuel afterValue).map ((name, value) :: ·)
        | _ => none
  | _, _ => none

example : parseArgs 1 [' ', '%', '%', '=', 'x', '\n'] = none := by rfl
example : parseArgs 1 [' ', '%', '%', 'f', 'o', 'o', '=', 'x', '\n'] = none := by rfl
example : parseArgs 1 [' ', 'f', 'o', 'o', '=', '%', '%', '\n'] = none := by rfl
example : parseArgs 1 [' ', 'f', 'o', 'o', '=', '%', 'x', '\n'] =
    some [(['f', 'o', 'o'], ['%', 'x'])] := by rfl

theorem take_append (word : List Char) (tail : List Char) (sep : Char)
    (valid : ∀ c ∈ word, allowed c = true) (blocked : allowed sep = false) :
    (word ++ sep :: tail).takeWhile allowed = word := by
  induction word with
  | nil => simp [List.takeWhile, blocked]
  | cons c rest ih =>
      have hc : allowed c = true := valid c (by simp)
      have hr : ∀ x ∈ rest, allowed x = true := by
        intro x hx
        exact valid x (by simp [hx])
      simp [List.takeWhile, hc, ih hr]

theorem drop_append (word : List Char) (tail : List Char) (sep : Char)
    (valid : ∀ c ∈ word, allowed c = true) (blocked : allowed sep = false) :
    (word ++ sep :: tail).dropWhile allowed = sep :: tail := by
  induction word with
  | nil => simp [List.dropWhile, blocked]
  | cons c rest ih =>
      have hc : allowed c = true := valid c (by simp)
      have hr : ∀ x ∈ rest, allowed x = true := by
        intro x hx
        exact valid x (by simp [hx])
      simp [List.dropWhile, hc, ih hr]

theorem printed_tail (args : List (Word × Word)) :
    ∃ sep tail, printArgs args = sep :: tail ∧ allowed sep = false := by
  cases args with
  | nil => exact ⟨'\n', [], rfl, newline_forbidden⟩
  | cons pair rest =>
      rcases pair with ⟨name, value⟩
      exact ⟨' ', name.chars ++ '=' :: value.chars ++ printArgs rest, rfl, space_forbidden⟩

private theorem not_empty (word : Word) : word.chars.isEmpty = false := by
  cases h : word.chars with
  | nil => exact False.elim (word.nonempty h)
  | cons _ _ => rfl

theorem parse_print_args (args : List (Word × Word))
    (namesSafe : safeNames args) (valuesSafe : safeValues args) :
    ∀ fuel, args.length ≤ fuel →
      parseArgs fuel (printArgs args) =
        some (args.map fun (name, value) => (name.chars, value.chars)) := by
  induction args with
  | nil =>
      intro fuel _
      cases fuel <;> rfl
  | cons pair rest ih =>
      intro fuel enough
      cases fuel with
      | zero => simp at enough
      | succ n =>
          have h : rest.length ≤ n := Nat.le_of_succ_le_succ enough
          rcases pair with ⟨name, value⟩
          obtain ⟨sep, tail, printed, blocked⟩ := printed_tail rest
          have vt : (value.chars ++ printArgs rest).takeWhile allowed = value.chars := by
            rw [printed]
            exact take_append value.chars tail sep value.valid blocked
          have vd : (value.chars ++ printArgs rest).dropWhile allowed = printArgs rest := by
            rw [printed]
            exact drop_append value.chars tail sep value.valid blocked
          have nameSafe : startsComment name.chars = false :=
            namesSafe (name, value) (by simp)
          have guarded : startsComment (name.chars ++ '=' :: (value.chars ++ printArgs rest)) = false :=
            safe_name_before_equals name (value.chars ++ printArgs rest) nameSafe
          have restSafe : safeNames rest := by
            intro pair member
            exact namesSafe pair (by simp [member])
          have valueSafe : containsDoublePercent value.chars = false :=
            valuesSafe (name, value) (by simp)
          have restValuesSafe : safeValues rest := by
            intro pair member
            exact valuesSafe pair (by simp [member])
          simp [printArgs, parseArgs,
            take_append name.chars (value.chars ++ printArgs rest) '=' name.valid equals_forbidden,
            drop_append name.chars (value.chars ++ printArgs rest) '=' name.valid equals_forbidden,
            not_empty name, not_empty value,
            guarded, valueSafe, vt, vd,
            ih restSafe restValuesSafe n h]

def renderRaw : List (List Char × List Char) → List Char
  | [] => ['\n']
  | (name, value) :: rest => ' ' :: name ++ '=' :: value ++ renderRaw rest

theorem render_raw_print (args : List (Word × Word)) :
    renderRaw (args.map fun (name, value) => (name.chars, value.chars)) = printArgs args := by
  induction args with
  | nil => rfl
  | cons pair rest ih =>
      rcases pair with ⟨name, value⟩
      simp [renderRaw, printArgs, ih]

def format (fuel : Nat) (input : List Char) : Option (List Char) :=
  (parseArgs fuel input).map renderRaw

theorem format_print (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (valuesSafe : safeValues args)
    (enough : args.length ≤ fuel) :
    format fuel (printArgs args) = some (printArgs args) := by
  simp [format, parse_print_args args namesSafe valuesSafe fuel enough, render_raw_print]

theorem parse_after_format (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (valuesSafe : safeValues args)
    (enough : args.length ≤ fuel) :
    (format fuel (printArgs args)).bind (parseArgs fuel) =
      some (args.map fun (name, value) => (name.chars, value.chars)) := by
  simp [format_print args fuel namesSafe valuesSafe enough,
    parse_print_args args namesSafe valuesSafe fuel enough]

theorem format_twice (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (valuesSafe : safeValues args)
    (enough : args.length ≤ fuel) :
    (format fuel (printArgs args)).bind (format fuel) = some (printArgs args) := by
  simp [format_print args fuel namesSafe valuesSafe enough]

theorem I1_word_keyword_arguments (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (valuesSafe : safeValues args)
    (enough : args.length ≤ fuel) :
    parseArgs fuel (printArgs args) =
      some (args.map fun (name, value) => (name.chars, value.chars)) :=
  parse_print_args args namesSafe valuesSafe fuel enough

theorem I2_word_keyword_ast (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (valuesSafe : safeValues args)
    (enough : args.length ≤ fuel) :
    (format fuel (printArgs args)).bind (parseArgs fuel) =
      some (args.map fun (name, value) => (name.chars, value.chars)) :=
  parse_after_format args fuel namesSafe valuesSafe enough

theorem I3_word_keyword_idempotence (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (valuesSafe : safeValues args)
    (enough : args.length ≤ fuel) :
    (format fuel (printArgs args)).bind (format fuel) = some (printArgs args) :=
  format_twice args fuel namesSafe valuesSafe enough

-- Any order, omission and repetition is still a list of arbitrary length.
theorem I4_word_keyword_sequences (args : List (Word × Word)) (fuel : Nat)
    (namesSafe : safeNames args) (valuesSafe : safeValues args)
    (enough : args.length ≤ fuel) :
    parseArgs fuel (printArgs args) =
      some (args.map fun (name, value) => (name.chars, value.chars)) ∧
    (format fuel (printArgs args)).bind (parseArgs fuel) =
      some (args.map fun (name, value) => (name.chars, value.chars)) :=
  ⟨I1_word_keyword_arguments args fuel namesSafe valuesSafe enough,
    I2_word_keyword_ast args fuel namesSafe valuesSafe enough⟩

-- The generated forbidden-character list and canonical PEG class agree for every Char.
open PegModelTest

theorem char_nat_injective (a b : Char) (h : a.toNat = b.toNat) : a = b := by
  cases a with
  | mk av ah =>
    cases b with
    | mk bv bh =>
      cases av with
      | mk an =>
        cases bv with
        | mk bn =>
          simp [Char.toNat, UInt32.toNat] at h
          congr
          omega

theorem word_allowed_is_peg_allowed (c : Char) :
    WordRoundTrip.allowed c = permitted
      [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58), (124, 124),
        (61, 61), (91, 91), (34, 34), (92, 92)] c := by
  change allowed c = !(ordinaryWordRanges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi))
  rw [ordinary_ranges_allowed]
  simp

theorem canonical_space_before_word (fuel : Nat) (c : Char) (tail : List Char)
    (valid : allowed c = true) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 10) (.ref "Sp" [])
      (' ' :: c :: tail) = .ok (some (c :: tail)) := by
  let cls := PegModel.Expr.charClass [(32, 32), (9, 9)] "[ \\t]"
  have excluded (d : Char) (invalid : allowed d = false) : c.toNat ≠ d.toNat := by
    intro eq
    have same := char_nat_injective c d eq
    subst c
    simp_all
  have ns : c.toNat ≠ 32 := excluded ' ' (by decide)
  have nt : c.toNat ≠ 9 := excluded '\t' (by decide)
  have miss : PegModel.recognizeEnv Generated.pegGrammar [] (fuel+3) cls (c :: tail) = .ok none := by
    have guard (n : Nat) (h : c.toNat ≠ n) : (decide (n ≤ c.toNat) && decide (c.toNat ≤ n)) = false := by
      by_cases a : n ≤ c.toNat
      · have b : ¬ c.toNat ≤ n := by omega
        simp [b]
      · simp [a]
    change (Except.ok (if ((decide (32 ≤ c.toNat) && decide (c.toNat ≤ 32)) ||
      ((decide (9 ≤ c.toNat) && decide (c.toNat ≤ 9)) || false)) then some tail else none)) = _
    rw [guard _ ns, guard _ nt]
    rfl
  have stop : PegModel.recognizeEnv Generated.pegGrammar [] (fuel+4) (.star cls) (c :: tail) =
      .ok (some (c :: tail)) := by
    change (match PegModel.recognizeEnv Generated.pegGrammar [] (fuel+3) cls (c :: tail) with
      | .error e => Except.error e
      | .ok none => Except.ok (some (c :: tail))
      | .ok (some rest) => if rest.length < (c :: tail).length then
          PegModel.recognizeEnv Generated.pegGrammar [] (fuel+3) (.star cls) rest
        else Except.error "zero-width repetition") = _
    rw [miss]
  have hit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel+4) cls (' ' :: c :: tail) =
      .ok (some (c :: tail)) := by rfl
  have plus : PegModel.recognizeEnv Generated.pegGrammar [] (fuel+5) (.plus cls)
      (' ' :: c :: tail) = .ok (some (c :: tail)) := by
    change (match PegModel.recognizeEnv Generated.pegGrammar [] (fuel+4) cls (' ' :: c :: tail) with
      | .error e => Except.error e
      | .ok none => Except.ok none
      | .ok (some rest) => if rest.length < (' ' :: c :: tail).length then
          PegModel.recognizeEnv Generated.pegGrammar [] (fuel+4) (.star cls) rest
        else Except.error "zero-width repetition") = _
    rw [hit]
    simpa using stop
  have ws : PegModel.recognizeEnv Generated.pegGrammar [] (fuel+7) (.ref "Ws" [])
      (' ' :: c :: tail) = .ok (some (c :: tail)) := by
    change PegModel.runChoices (fun items => PegModel.runSequence
      (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+5) item s)
      _ [] items (' ' :: c :: tail)) [[.plus cls]] = _
    simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, List.foldlM, plus, Except.map] <;> rfl
  have optional := PegModelTest.optional_hit Generated.pegGrammar _ _ _ _ ws
  change PegModel.runChoices (fun items => PegModel.runSequence
    (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+8) item s)
    _ [] items (' ' :: c :: tail)) [[.opt (.ref "Ws" [])]] = _
  simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, List.foldlM, optional, Except.map] <;> rfl

-- The optional comments after a keyword must leave the separating space
-- available to the next keyword when no comment follows it.
theorem comments_before_keyword (fuel : Nat) (name : Word) (suffix : List Char)
    (safe : startsComment name.chars = false) :
    let input := ' ' :: name.chars ++ '=' :: suffix
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 12)
      (.star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])) input = .ok (some input) := by
  have guarded := safe_name_before_equals name suffix safe
  cases chars : name.chars with
  | nil => exact False.elim (name.nonempty chars)
  | cons c rest =>
    have valid := name.valid c (by simp [chars])
    let afterSpace := c :: rest ++ '=' :: suffix
    have space := canonical_space_before_word fuel c (rest ++ '=' :: suffix) valid
    have comment := ordinary_comment_misses (fuel + 2) afterSpace (by simpa [afterSpace, chars] using guarded)
    have stop : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 11)
        (.choice [[.ref "Sp" [], .ref "ArgComment" []]]) (' ' :: afterSpace) = .ok none := by
      change PegModel.runChoices (fun items => PegModel.runSequence
        (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 10) item s)
        _ [] items (' ' :: afterSpace)) [[.ref "Sp" [], .ref "ArgComment" []]] = _
      change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 10) (.ref "Sp" [])
        (' ' :: afterSpace) = .ok (some afterSpace) at space
      simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, List.foldlM,
        space, comment, Except.map] <;> rfl
    change (match PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 11)
          (.choice [[.ref "Sp" [], .ref "ArgComment" []]]) (' ' :: afterSpace) with
      | .error e => Except.error e
      | .ok none => Except.ok (some (' ' :: afterSpace))
      | .ok (some remaining) => if remaining.length < (' ' :: afterSpace).length then
          PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 11)
            (.star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])) remaining
        else Except.error "zero-width repetition") = _
    rw [stop]
    rfl

end WordRoundTrip
