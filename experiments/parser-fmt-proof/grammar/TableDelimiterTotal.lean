import LineBoundaryTotal
import RuleRepetition
import IndentTotal

namespace TableDelimiterTotal

open PegModel PegModelTest

private def single (c : Char) : Expr := .lit (String.singleton c) ("'" ++ String.singleton c ++ "'")

def colon (input : List Char) : List Char :=
  match input with
  | ':' :: rest => rest
  | _ => input

def dashes (input : List Char) : Option (List Char) :=
  match input with
  | '-' :: rest => some (rest.dropWhile (· == '-'))
  | _ => none

def delimiter (input : List Char) : Option (List Char) := do
  let rest ← dashes (colon (input.dropWhile LineBoundaryTotal.whitespace))
  some ((colon rest).dropWhile LineBoundaryTotal.whitespace)

private theorem single_total (c : Char) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [] (fuel + 1) (single c) input =
      .ok (match input with | [] => none | x :: rest => if c = x then some rest else none) := by
  cases input with
  | nil => rfl
  | cons x rest =>
    simp [recognizeEnv, single, String.singleton, List.isPrefixOf, List.drop, Id.run]
    rfl

private theorem star_single (c : Char) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 2 + extra) (.star (single c)) input =
      .ok (some (input.dropWhile (· == c))) := by
  induction input with
  | nil =>
    rw [show ([] : List Char).length + 2 + extra = extra + 1 + 1 by simp; omega]
    rfl
  | cons x rest ih =>
    rw [show (x :: rest).length + 2 + extra = (rest.length + 2 + extra) + 1 by simp; omega]
    have atom := single_total c (rest.length + 1 + extra) (x :: rest)
    rw [show rest.length + 1 + extra + 1 = rest.length + 2 + extra by omega] at atom
    change (match recognizeEnv Generated.pegGrammar [] (rest.length + 2 + extra) (single c) (x :: rest) with
      | .error reason => Except.error reason
      | .ok none => .ok (some (x :: rest))
      | .ok (some tail) => if tail.length < (x :: rest).length then
          recognizeEnv Generated.pegGrammar [] (rest.length + 2 + extra) (.star (single c)) tail
        else .error "zero-width repetition") = _
    by_cases same : c = x
    · subst x
      have shorter : rest.length < (c :: rest).length := by simp
      simp [atom, shorter, ih, List.dropWhile]
    · have different : (x == c) = false := by
        cases hit : (x == c) with
        | false => rfl
        | true => exact False.elim (same ((beq_iff_eq _ _).mp hit).symm)
      simp [atom, same, different, List.dropWhile]

private theorem plus_dash (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 4 + extra) (.plus (single '-')) input =
      .ok (dashes input) := by
  rw [show input.length + 4 + extra = (input.length + 3 + extra) + 1 by omega]
  change (match recognizeEnv Generated.pegGrammar [] (input.length + 3 + extra) (single '-') input with
    | .error reason => Except.error reason
    | .ok none => .ok none
    | .ok (some rest) => if rest.length < input.length then
        recognizeEnv Generated.pegGrammar [] (input.length + 3 + extra) (.star (single '-')) rest
      else .error "zero-width repetition") = _
  have atom := single_total '-' (input.length + 2 + extra) input
  rw [show input.length + 2 + extra + 1 = input.length + 3 + extra by omega] at atom
  rw [atom]
  cases input with
  | nil => rfl
  | cons c rest =>
    by_cases same : c = '-'
    · subst c
      have tail := star_single '-' rest (2 + extra)
      rw [show rest.length + 2 + (2 + extra) = (('-' :: rest).length + 3 + extra) by simp; omega] at tail
      simp only [List.length_cons] at tail
      simpa [dashes] using tail
    · simp [same, Ne.symm same, dashes]

private theorem optional_colon (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar [] (fuel + 2) (.opt (single ':')) input =
      .ok (some (colon input)) := by
  change (match recognizeEnv Generated.pegGrammar [] (fuel + 1) (single ':') input with
    | .error reason => Except.error reason
    | .ok none => .ok (some input)
    | .ok result => .ok result) = _
  rw [single_total]
  cases input with
  | nil => rfl
  | cons c rest => by_cases same : c = ':' <;> simp [same, Ne.symm, colon, Id.run]

private theorem drop_le (p : Char → Bool) (input : List Char) :
    (input.dropWhile p).length ≤ input.length := by
  induction input with
  | nil => simp
  | cons c rest ih => cases hit : p c <;> simp [List.dropWhile, hit] <;> omega

private theorem colon_le (input : List Char) : (colon input).length ≤ input.length := by
  cases input with
  | nil => simp [colon]
  | cons c rest => by_cases same : c = ':' <;> simp [colon, same] <;> omega

private theorem dashes_le (input rest : List Char) (hit : dashes input = some rest) :
    rest.length ≤ input.length := by
  cases input with
  | nil => simp [dashes] at hit
  | cons c tail =>
    by_cases same : c = '-'
    · subst c
      simp [dashes] at hit
      subst rest
      have := drop_le (· == '-') tail
      change (tail.dropWhile (· == '-')).length ≤ tail.length + 1
      omega
    · simp [dashes, same] at hit

private theorem sp_at (input : List Char) (fuel : Nat) (bound : input.length + 7 ≤ fuel) :
    recognizeEnv Generated.pegGrammar [] fuel (.ref "Sp" []) input =
      .ok (some (input.dropWhile LineBoundaryTotal.whitespace)) := by
  have := LineBoundaryTotal.generated_sp [] input (fuel - (input.length + 7))
  rwa [show input.length + 7 + (fuel - (input.length + 7)) = fuel by omega] at this

private theorem dash_at (input : List Char) (fuel : Nat) (bound : input.length + 4 ≤ fuel) :
    recognizeEnv Generated.pegGrammar [] fuel (.plus (single '-')) input = .ok (dashes input) := by
  have := plus_dash input (fuel - (input.length + 4))
  rwa [show input.length + 4 + (fuel - (input.length + 4)) = fuel by omega] at this

/-- Recognition of the canonical rule for every input, with a sufficient fuel
    budget derived from its length. This states no Haskell action/AST property. -/
theorem I1_I2_generated_delimiter (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 10 + extra) (.ref "Delim" []) input =
      .ok (delimiter input) := by
  let fuel := input.length + 8 + extra
  let a := input.dropWhile LineBoundaryTotal.whitespace
  let b := colon a
  have alen : a.length ≤ input.length := drop_le _ _
  have blen : b.length ≤ input.length := Nat.le_trans (colon_le a) alen
  have spaces := sp_at input fuel (by dsimp [fuel]; omega)
  have optionalA := optional_colon a (input.length + 6 + extra)
  have hyphens := dash_at b fuel (by dsimp [fuel]; omega)
  rw [show input.length + 10 + extra = fuel + 1 + 1 by dsimp [fuel]; omega]
  change recognizeEnv _ [] (fuel + 1) (.choice [[.ref "Sp" [], .opt (single ':'),
    .plus (single '-'), .opt (single ':'), .ref "Sp" []]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    fuel item rest) _ [] xs input) [[.ref "Sp" [], .opt (single ':'),
      .plus (single '-'), .opt (single ':'), .ref "Sp" []]] = _
  rw [show input.length + 6 + extra + 2 = fuel by dsimp [fuel]; omega] at optionalA
  cases hit : dashes b with
  | none =>
    simp [runChoices, foldChoice, runSequence, List.foldlM, spaces, optionalA, hyphens,
      hit, delimiter, a, b, Bind.bind, Except.bind, pure, Except.pure, Except.map]
  | some rest =>
    have rlen : rest.length ≤ input.length := Nat.le_trans (dashes_le b rest hit) blen
    have clen : (colon rest).length ≤ input.length := Nat.le_trans (colon_le rest) rlen
    have optionalB := optional_colon rest (input.length + 6 + extra)
    rw [show input.length + 6 + extra + 2 = fuel by dsimp [fuel]; omega] at optionalB
    have finalSp := sp_at (colon rest) fuel (by dsimp [fuel]; omega)
    simp [runChoices, foldChoice, runSequence, List.foldlM, spaces, optionalA, hyphens,
      hit, optionalB, finalSp, delimiter, a, b, Bind.bind, Except.bind, pure, Except.pure, Except.map]

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

private def cell : Expr := .choice [[.ref "Pipe" [], .ref "Delim" []]]

private theorem pipe_total (env : Params) (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "Pipe" []) input =
      .ok (match input with | '|' :: rest => some rest | _ => none) := by
  change recognizeEnv _ [] (fuel + 2) (.choice [[single '|']]) input = _
  rw [single_group _ _ _ _ (fuel + 1) (by simp [single])]
  rw [single_total]
  cases input with
  | nil => rfl
  | cons c rest => by_cases same : c = '|' <;> simp [same, Ne.symm]

/-- The repeated cell itself recognizes precisely a pipe followed by the pure
    delimiter recognizer, for every input; it does not rely on a child-success premise. -/
theorem I1_I2_generated_cell (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 13 + extra) cell input =
      .ok (match input with | '|' :: rest => delimiter rest | _ => none) := by
  let fuel := input.length + 12 + extra
  rw [show input.length + 13 + extra = fuel + 1 by dsimp [fuel]; omega]
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    fuel item rest) _ env xs input) [[.ref "Pipe" [], .ref "Delim" []]] = _
  have pipe := pipe_total env input (input.length + 9 + extra)
  rw [show input.length + 9 + extra + 3 = fuel by dsimp [fuel]; omega] at pipe
  cases input with
  | nil => simp [runChoices, foldChoice, runSequence, pipe]; rfl
  | cons c rest =>
    by_cases same : c = '|'
    · subst c
      have body := I1_I2_generated_delimiter env rest (3 + extra)
      rw [show rest.length + 10 + (3 + extra) = fuel by dsimp [fuel]; omega] at body
      cases result : delimiter rest <;>
        simp [runChoices, foldChoice, runSequence, pipe, body, result] <;> rfl
    · simp [runChoices, foldChoice, runSequence, pipe, same]; rfl

/-- The row's repetition stops on an ordinary miss, propagates an error, and
    never accepts a zero-width item. Each item is the canonical Pipe/Delim pair. -/
def cells (env : Params) (fuel : Nat) (input : List Char) : ParseResult :=
  match recognizeEnv Generated.pegGrammar env fuel cell input with
  | .error reason => .error reason
  | .ok none => .ok none
  | .ok (some rest) => if rest.length < input.length then
      RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar env n cell) fuel rest
    else .error "zero-width repetition"

private theorem cells_plus (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 1) (.plus cell) input =
      cells env fuel input := by
  change (match recognizeEnv Generated.pegGrammar env fuel cell input with
    | .error reason => Except.error reason
    | .ok none => .ok none
    | .ok (some rest) => if rest.length < input.length then
        recognizeEnv Generated.pegGrammar env fuel (.star cell) rest
      else .error "zero-width repetition") = _
  unfold cells
  cases read : recognizeEnv Generated.pegGrammar env fuel cell input with
  | error reason => rfl
  | ok value => cases value with
    | none => rfl
    | some rest => simp [RuleRepetition.star]

/-- All indentation values and input suffixes are quantified. The body combines
    the proved delimiter with the error-preserving canonical repetition, rather
    than assuming successful parsing of any child. -/
theorem I1_I2_generated_row (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 4) (.ref "TableDelimiter" ["ind"]) input =
      next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2) (.ref "Ind" ["ind"]) input) (fun start =>
        next (cells [("ind", ind)] (fuel + 1) start) (fun rest =>
          next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2) (.ref "Pipe" []) rest)
            (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2) (.ref "Sp" [])))) := by
  change recognizeEnv _ [("ind", ind)] (fuel + 3)
    (.choice [[.ref "Ind" ["ind"], .plus cell, .ref "Pipe" [], .ref "Sp" []]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 2) item rest) _ [("ind", ind)] xs input)
    [[.ref "Ind" ["ind"], .plus cell, .ref "Pipe" [], .ref "Sp" []]] = _
  have repeated := cells_plus [("ind", ind)] (fuel + 1)
  have seq : ∀ start, recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2) (.plus cell) start =
      cells [("ind", ind)] (fuel + 1) start := repeated
  cases first : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2) (.ref "Ind" ["ind"]) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, first]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, first]; rfl
    | some start =>
      cases body : cells [("ind", ind)] (fuel + 1) start with
      | error reason => simp [runChoices, foldChoice, runSequence, next, first, seq, body]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, first, seq, body]; rfl
        | some rest =>
          cases lastPipe : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2) (.ref "Pipe" []) rest with
          | error reason => simp [runChoices, foldChoice, runSequence, next, first, seq, body, lastPipe]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, first, seq, body, lastPipe]; rfl
            | some tail =>
              cases spaces : recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2) (.ref "Sp" []) tail with
              | error reason => simp [runChoices, foldChoice, runSequence, next, first, seq, body, lastPipe, spaces]; rfl
              | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, first, seq, body, lastPipe, spaces] <;> rfl

/-- Resolve every indentation count using the already proved Ind recognizer;
    no success premise about the input or delimiter cells is introduced. -/
theorem I1_I2_generated_row_indent (ind extra : Nat) (input : List Char) :
    let fuel := 2 * ind + 3 + extra
    recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 4) (.ref "TableDelimiter" ["ind"]) input =
      match IndentTotal.expected ind input with
      | none => .ok none
      | some start => next (cells [("ind", ind)] (fuel + 1) start) (fun rest =>
          next (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2) (.ref "Pipe" []) rest)
            (recognizeEnv Generated.pegGrammar [("ind", ind)] (fuel + 2) (.ref "Sp" []))) := by
  dsimp only
  rw [I1_I2_generated_row]
  have indentation := IndentTotal.generated_indent ind input [("ind", ind)] "ind" (2 + extra) (by rfl)
  rw [show 2 * ind + 3 + (2 + extra) = 2 * ind + 3 + extra + 2 by omega] at indentation
  rw [indentation]
  cases IndentTotal.expected ind input <;> rfl

end TableDelimiterTotal
