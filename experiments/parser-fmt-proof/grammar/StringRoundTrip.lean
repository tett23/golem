import WordRoundTrip

namespace StringRoundTrip

def scanString (escapeFirst : Bool) : List Char → Option (List Char × List Char)
  | [] => none
  | '"' :: rest => some ([], rest)
  | '\\' :: next :: rest =>
      if escapeFirst then
        (scanString escapeFirst rest).map fun (value, suffix) => ('\\' :: next :: value, suffix)
      else
        (scanString escapeFirst (next :: rest)).map fun (value, suffix) => ('\\' :: value, suffix)
  | char :: rest =>
      if char == '\n' then none
      else (scanString escapeFirst rest).map fun (value, suffix) => (char :: value, suffix)

structure Plain where
  char : Char
  notSlash : char ≠ '\\'
  notQuote : char ≠ '"'
  notNewline : char ≠ '\n'

inductive Part where
  | plain (value : Plain)
  | escaped (value : Char)

def spell : List Part → List Char
  | [] => []
  | .plain value :: rest => value.char :: spell rest
  | .escaped value :: rest => '\\' :: value :: spell rest

theorem scan_spell (parts : List Part) (tail : List Char) :
    scanString Generated.stringLitEscapeFirst (spell parts ++ '"' :: tail) =
      some (spell parts, tail) := by
  induction parts with
  | nil => simp [spell, scanString]
  | cons part rest ih =>
      simp [Generated.stringLitEscapeFirst] at ih
      cases part with
      | plain value =>
          rcases value with ⟨c, slash, quote, newline⟩
          simp [spell, scanString, slash, quote, newline, ih,
            Generated.stringLitEscapeFirst]
      | escaped value =>
          simp [spell, scanString, ih, Generated.stringLitEscapeFirst]

def bodyChoices : List (List PegModel.Expr) :=
  [[.lit "\\" "'\\\\'", .any], [.notPred (.charClass [(34, 34), (10, 10)] "[\"\\n]"), .any]]

theorem generated_body_choices :
    ((Generated.pegGrammar.rules.find? (fun r => r.name == "StringLit")).bind
      (fun r => r.alts.head?.map (fun a => a.items))) =
      some [.lit "\"" "'\"'", .star (.choice bodyChoices), .lit "\"" "'\"'"] := by rfl

theorem escaped_step (env : PegModel.Params) (fuel : Nat) (c : Char) (tail : List Char) :
    PegModel.recognizeEnv Generated.pegGrammar env (fuel + 2)
      (.choice bodyChoices) ('\\' :: c :: tail) = .ok (some tail) := by
  have lit : PegModel.recognizeEnv Generated.pegGrammar env (fuel + 1)
    (.lit "\\" "'\\\\'") ('\\' :: c :: tail) = .ok (some (c :: tail)) := by rfl
  have any : PegModel.recognizeEnv Generated.pegGrammar env (fuel + 1)
    .any (c :: tail) = .ok (some tail) := by rfl
  change PegModel.runChoices (fun items => PegModel.runSequence
    (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 1) item rest)
    (fun _ _ _ => .ok none) env items ('\\' :: c :: tail)) bodyChoices = _
  simp [bodyChoices, PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, lit, any,
    List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]

theorem unescaped_step (env : PegModel.Params) (fuel : Nat) (c : Char) (tail : List Char)
    (notSlash : c ≠ '\\') :
    PegModel.recognizeEnv Generated.pegGrammar env (fuel + 4) (.choice bodyChoices) (c :: tail) =
      .ok (if [(34, 34), (10, 10)].any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
        then none else some tail) := by
  have lit := PegModelTest.literal_total Generated.pegGrammar env (fuel + 2) "\\" "'\\\\'" (c :: tail)
  have miss : "\\".toList.isPrefixOf (c :: tail) = false := by
    simp [show "\\".toList = ['\\'] by rfl, List.isPrefixOf, show ('\\' == c) = false by cases h : ('\\' == c) <;> simp_all <;> exact notSlash h.symm]
  simp [miss] at lit
  have ordinary := PegModelTest.nonclass_any Generated.pegGrammar env fuel
    [(34, 34), (10, 10)] "[\"\\n]" (c :: tail)
  change PegModel.runChoices (fun items => PegModel.runSequence
    (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 3) item rest)
    (fun _ _ _ => .ok none) env items (c :: tail)) bodyChoices = _
  change PegModel.runChoices (fun items => PegModel.runSequence
    (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 3) item rest)
    (fun _ _ _ => .ok none) env items (c :: tail))
      [[.notPred (.charClass [(34, 34), (10, 10)] "[\"\\n]"), .any]] = _ at ordinary
  simp [bodyChoices, PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, lit,
    List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map] at ordinary ⊢
  exact ordinary

theorem repeated_spell (env : PegModel.Params) (parts : List Part) (tail : List Char) (extra : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar env (parts.length + 5 + extra)
      (.star (.choice bodyChoices)) (spell parts ++ '"' :: tail) = .ok (some ('"' :: tail)) := by
  induction parts generalizing extra with
  | nil =>
      have stop := unescaped_step env extra '"' tail (by decide)
      simp at stop
      rw [show ([] : List Part).length + 5 + extra = (extra + 4) + 1 by simp; omega]
      simp only [spell, List.nil_append]
      unfold PegModel.recognizeEnv
      simp [stop] <;> rfl
  | cons part parts ih =>
      have fuelEq : (part :: parts).length + 5 + extra = (parts.length + 5 + extra) + 1 := by
        simp; omega
      rw [fuelEq]
      cases part with
      | escaped c =>
          have step := escaped_step env (parts.length + 3 + extra) c (spell parts ++ '"' :: tail)
          rw [show parts.length + 3 + extra + 2 = parts.length + 5 + extra by omega] at step
          simp only [spell, List.cons_append]
          unfold PegModel.recognizeEnv
          simp [step, ih extra, Id.run, Nat.lt_succ_of_lt (Nat.lt_succ_self _)] <;> rfl
      | plain plain =>
          rcases plain with ⟨c, notSlash, notQuote, notNewline⟩
          have step := unescaped_step env (parts.length + 1 + extra) c (spell parts ++ '"' :: tail) notSlash
          rw [show parts.length + 1 + extra + 4 = parts.length + 5 + extra by omega] at step
          have ranges : ¬(34 ≤ c.toNat ∧ c.toNat ≤ 34 ∨ 10 ≤ c.toNat ∧ c.toNat ≤ 10) := by
            intro h
            rcases h with h | h
            · apply notQuote
              have he : c.toNat = '"'.toNat := by change c.toNat = 34; omega
              exact WordRoundTrip.char_nat_injective _ _ he
            · apply notNewline
              have he : c.toNat = '\n'.toNat := by change c.toNat = 10; omega
              exact WordRoundTrip.char_nat_injective _ _ he
          simp [ranges] at step
          simp only [spell, List.cons_append]
          unfold PegModel.recognizeEnv
          simp [step, ih extra, Id.run, Nat.lt_succ_of_lt (Nat.lt_succ_self _)] <;> rfl

-- Golem.Parser.Lower.unquote removes the quoting backslash from each pair.
def unescape : List Char → List Char
  | '\\' :: next :: rest => next :: unescape rest
  | c :: rest => c :: unescape rest
  | [] => []

def partValue : Part → Char
  | .plain p => p.char
  | .escaped c => c

theorem unescape_spell (parts : List Part) :
    unescape (spell parts) = parts.map partValue := by
  induction parts with
  | nil => rfl
  | cons p parts ih =>
      cases p with
      | escaped c => simp [spell, unescape, ih, partValue]
      | plain p =>
          rcases p with ⟨c, notSlash, _, _⟩
          simp [spell, unescape, notSlash, ih, partValue]

theorem I1_generated_quoted_round_trip (parts : List Part) (tail : List Char) (extra : Nat) :
    let input := '"' :: (spell parts ++ '"' :: tail)
    PegModel.recognizeEnv Generated.pegGrammar [] (parts.length + 7 + extra)
      (.ref "StringLit" []) input = .ok (some tail) ∧
    scanString Generated.stringLitEscapeFirst (spell parts ++ '"' :: tail) = some (spell parts, tail) ∧
    unescape (spell parts) = parts.map partValue := by
  dsimp only
  constructor
  · have fuelEq : parts.length + 7 + extra = (parts.length + 5 + extra) + 1 + 1 := by omega
    rw [fuelEq]
    change PegModel.recognizeEnv Generated.pegGrammar [] ((parts.length + 5 + extra) + 1)
      (.choice [[.lit "\"" "'\"'", .star (.choice bodyChoices), .lit "\"" "'\"'"]])
      ('"' :: (spell parts ++ '"' :: tail)) = _
    change PegModel.runChoices (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope
        (parts.length + 5 + extra) item rest) (fun _ _ _ => .ok none) [] items
      ('"' :: (spell parts ++ '"' :: tail))) [[.lit "\"" "'\"'", .star (.choice bodyChoices), .lit "\"" "'\"'"]] = _
    have quote (rest : List Char) : PegModel.recognizeEnv Generated.pegGrammar []
        (parts.length + 5 + extra) (.lit "\"" "'\"'") ('"' :: rest) = .ok (some rest) := by
      rw [show parts.length + 5 + extra = (parts.length + 4 + extra) + 1 by omega]
      rw [PegModelTest.literal_total]
      simp [show "\"".toList = ['"'] by rfl, List.isPrefixOf]
    simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, quote,
      repeated_spell [] parts tail extra, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]
  · exact ⟨scan_spell parts tail, unescape_spell parts⟩

def stopsBody (c : Char) : Bool :=
  [(34, 34), (10, 10)].any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)

def bodySuffix : List Char → List Char
  | [] => []
  | '\\' :: _ :: rest => bodySuffix rest
  | c :: rest => if stopsBody c then c :: rest else bodySuffix rest

private theorem starStop (env : PegModel.Params) (fuel : Nat) (input : List Char)
    (stop : PegModel.recognizeEnv Generated.pegGrammar env fuel (.choice bodyChoices) input = .ok none) :
    PegModel.recognizeEnv Generated.pegGrammar env (fuel + 1) (.star (.choice bodyChoices)) input =
      .ok (some input) := by unfold PegModel.recognizeEnv; simp [stop]; rfl

private theorem starNext (env : PegModel.Params) (fuel : Nat) (input rest : List Char)
    (step : PegModel.recognizeEnv Generated.pegGrammar env fuel (.choice bodyChoices) input = .ok (some rest))
    (shrinks : rest.length < input.length) :
    PegModel.recognizeEnv Generated.pegGrammar env (fuel + 1) (.star (.choice bodyChoices)) input =
      PegModel.recognizeEnv Generated.pegGrammar env fuel (.star (.choice bodyChoices)) rest := by
  conv => lhs; unfold PegModel.recognizeEnv
  simp [step, shrinks]; rfl

theorem body_total (env : PegModel.Params) (input : List Char) (extra : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar env (input.length + 5 + extra)
      (.star (.choice bodyChoices)) input = .ok (some (bodySuffix input)) := by
  cases input with
  | nil =>
      rw [show ([] : List Char).length + 5 + extra = (extra + 4) + 1 by simp; omega]
      apply starStop
      rfl
  | cons c rest =>
      rw [show (c :: rest).length + 5 + extra = (rest.length + 5 + extra) + 1 by simp; omega]
      by_cases slash : c = '\\'
      · subst c
        cases rest with
        | nil =>
            rw [show ([] : List Char).length + 5 + extra = (extra + 4) + 1 by simp; omega]
            have step : PegModel.recognizeEnv Generated.pegGrammar env (extra + 4 + 1)
                (.choice bodyChoices) ['\\'] = .ok (some []) := by rfl
            rw [starNext env _ _ [] step (by decide)]
            rw [show extra + 4 + 1 = ([] : List Char).length + 5 + extra by simp; omega]
            exact body_total env [] extra
        | cons next tail =>
            have step := escaped_step env (tail.length + 4 + extra) next tail
            have eqFuel : (next :: tail).length + 5 + extra = tail.length + 4 + extra + 2 := by simp; omega
            rw [← eqFuel] at step
            rw [starNext env _ _ tail step (by simp; omega)]
            rw [show (next :: tail).length + 5 + extra = tail.length + 5 + (extra + 1) by simp; omega]
            exact body_total env tail (extra + 1)
      · have step := unescaped_step env (rest.length + 1 + extra) c rest slash
        rw [show rest.length + 1 + extra + 4 = rest.length + 5 + extra by omega] at step
        change _ = .ok (if stopsBody c then none else some rest) at step
        cases stop : stopsBody c with
        | true =>
            simp [stop] at step
            rw [starStop env _ _ step]
            simp [bodySuffix, slash, stop]
        | false =>
            simp [stop] at step
            rw [starNext env _ _ rest step (by simp), body_total env rest extra]
            simp [bodySuffix, slash, stop]
termination_by input.length
decreasing_by all_goals simp_wf; all_goals omega

def afterQuote : List Char → Option (List Char)
  | '"' :: rest => some rest
  | _ => none

theorem quote_total (env : PegModel.Params) (fuel : Nat) (input : List Char) :
    PegModel.recognizeEnv Generated.pegGrammar env (fuel + 1) (.lit "\"" "'\"'") input =
      .ok (afterQuote input) := by
  rw [PegModelTest.literal_total]
  cases input with
  | nil => rfl
  | cons c rest =>
      by_cases quoted : c = '"'
      · subst c; simp [afterQuote, show "\"".toList = ['"'] by rfl, List.isPrefixOf]
      · have miss : ('"' == c) = false := by
          cases h : ('"' == c) <;> simp_all <;> exact quoted h.symm
        simp [afterQuote, quoted, show "\"".toList = ['"'] by rfl, List.isPrefixOf, miss]

theorem generated_string_total (env : PegModel.Params) (input : List Char) (extra : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar env (input.length + 7 + extra)
      (.ref "StringLit" []) input =
      .ok ((afterQuote input).bind fun rest => afterQuote (bodySuffix rest)) := by
  have fuelEq : input.length + 7 + extra = (input.length + 5 + extra) + 1 + 1 := by omega
  rw [fuelEq]
  change PegModel.recognizeEnv Generated.pegGrammar [] ((input.length + 5 + extra) + 1)
    (.choice [[.lit "\"" "'\"'", .star (.choice bodyChoices), .lit "\"" "'\"'"]]) input = _
  change PegModel.runChoices (fun items => PegModel.runSequence
    (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope
      (input.length + 5 + extra) item rest) (fun _ _ _ => .ok none) [] items input)
    [[.lit "\"" "'\"'", .star (.choice bodyChoices), .lit "\"" "'\"'"]] = _
  have quote (remaining : List Char) := quote_total [] (input.length + 4 + extra) remaining
  simp only [show input.length + 4 + extra + 1 = input.length + 5 + extra by omega] at quote
  cases h : afterQuote input with
  | none =>
      simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, List.foldlM, Bind.bind,
        Except.bind, pure, Except.pure, Except.map, quote, h]
  | some rest =>
      have lengthEq : input.length = rest.length + 1 := by
        cases input with
        | nil => contradiction
        | cons c cs =>
            by_cases quoted : c = '"'
            · subst c; simp [afterQuote] at h; subst rest; rfl
            · simp [afterQuote, quoted] at h
      have body := body_total [] rest (extra + 1)
      rw [show rest.length + 5 + (extra + 1) = input.length + 5 + extra by omega] at body
      cases trailing : afterQuote (bodySuffix rest) <;>
        simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, List.foldlM, Bind.bind,
          Except.bind, pure, Except.pure, Except.map, quote, h, body, trailing]

end StringRoundTrip
