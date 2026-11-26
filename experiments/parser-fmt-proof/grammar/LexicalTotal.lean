import LineBoundaryTotal
import RuleRepetition

namespace LexicalTotal

open PegModel PegModelTest

private def next (result : ParseResult) (read : List Char → ParseResult) : ParseResult :=
  match result with
  | .ok (some rest) => read rest
  | other => other

private def inClass (ranges : List (Nat × Nat)) (c : Char) : Bool :=
  ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)

private def runClass (ranges : List (Nat × Nat)) (input : List Char) : Option (List Char) :=
  match input with
  | [] => none
  | c :: rest => if inClass ranges c then some (rest.dropWhile (inClass ranges)) else none

private theorem plus_class (ranges : List (Nat × Nat)) (written : String)
    (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 4 + extra)
      (.plus (.charClass ranges written)) input = .ok (runClass ranges input) := by
  let fuel := input.length + 3 + extra
  rw [show input.length + 4 + extra = fuel + 1 by dsimp [fuel]; omega]
  change (match recognizeEnv Generated.pegGrammar [] fuel (.charClass ranges written) input with
    | .error reason => Except.error reason
    | .ok none => .ok none
    | .ok (some rest) => if rest.length < input.length then
        recognizeEnv Generated.pegGrammar [] fuel (.star (.charClass ranges written)) rest
      else .error "zero-width repetition") = _
  have atom := class_total Generated.pegGrammar [] (input.length + 2 + extra) ranges written input
  rw [show input.length + 2 + extra + 1 = fuel by dsimp [fuel]; omega] at atom
  rw [atom]
  cases input with
  | nil => rfl
  | cons c rest =>
    have tail := LineBoundaryTotal.star_class ranges written rest (2 + extra)
    rw [show rest.length + 2 + (2 + extra) = fuel by dsimp [fuel]; omega] at tail
    change (match Except.ok (if inClass ranges c then some rest else none) with
      | .error reason => Except.error reason
      | .ok none => .ok none
      | .ok (some next) => if next.length < (c :: rest).length then
          recognizeEnv Generated.pegGrammar [] fuel (.star (.charClass ranges written)) next
        else .error "zero-width repetition") = _
    change recognizeEnv _ [] fuel _ rest = .ok (some (rest.dropWhile (inClass ranges))) at tail
    cases allowed : inClass ranges c <;> simp [runClass, allowed, tail]

private def digitRanges := [(48, 57)]
private def digit := Expr.charClass digitRanges "[0-9]"
private def digits := Expr.plus digit
private def dot := Expr.lit "." "'.'"
private def exp := Expr.lit "e" "'e'"
private def signs := Expr.charClass [(43, 43), (45, 45)] "[+\\-]"
private def fraction := Expr.choice [[dot, digits]]
private def exponent := Expr.choice [[exp, .opt signs, digits]]

/-- Recognition keeps the entire ordered optional group intact: a failed
    fraction or exponent restores its original suffix, not its inner suffix. -/
theorem I1_I2_generated_number (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "Number" []) input =
      next (recognizeEnv Generated.pegGrammar [] (fuel + 1) digits input) (fun rest =>
        next (recognizeEnv Generated.pegGrammar [] (fuel + 1) (.opt fraction) rest)
          (recognizeEnv Generated.pegGrammar [] (fuel + 1) (.opt exponent))) := by
  change recognizeEnv _ [] (fuel + 2) (.choice [[digits, .opt fraction, .opt exponent]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 1) item rest) _ [] xs input) [[digits, .opt fraction, .opt exponent]] = _
  simp only [digits]
  cases first : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.plus digit) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, first]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, first]; rfl
    | some rest =>
      cases decimal : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.opt fraction) rest with
      | error reason => simp [runChoices, foldChoice, runSequence, next, first, decimal]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, first, decimal]; rfl
        | some tail =>
          cases power : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.opt exponent) tail with
          | error reason => simp [runChoices, foldChoice, runSequence, next, first, decimal, power]; rfl
          | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, first, decimal, power] <;> rfl

/-- The unbounded digit run is a pure maximal-prefix recognizer. -/
theorem I1_I2_number_digits_total (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 4 + extra) digits input =
      .ok (runClass digitRanges input) := plus_class digitRanges "[0-9]" input extra

private def lower := Expr.charClass [(97, 122)] "[a-z]"
private def nameChars := Expr.charClass [(97, 122), (48, 57), (45, 45)] "[a-z0-9\\-]"
private def nameTail := Expr.star nameChars
private def qualified := Expr.choice [[dot, lower, nameTail]]
private def secondDot := Expr.choice [[dot, lower]]

/-- Qualification is optional as a whole, but a second qualified name is
    forbidden by a non-consuming guard. No name/AST equality is assumed. -/
theorem I1_I2_generated_identifier (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "Ident" []) input =
      next (recognizeEnv Generated.pegGrammar [] (fuel + 1) lower input) (fun start =>
        next (recognizeEnv Generated.pegGrammar [] (fuel + 1) nameTail start) (fun rest =>
          next (recognizeEnv Generated.pegGrammar [] (fuel + 1) (.opt qualified) rest)
            (recognizeEnv Generated.pegGrammar [] (fuel + 1) (.notPred secondDot)))) := by
  change recognizeEnv _ [] (fuel + 2) (.choice [[lower, nameTail, .opt qualified, .notPred secondDot]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 1) item rest) _ [] xs input) [[lower, nameTail, .opt qualified, .notPred secondDot]] = _
  simp only [lower, nameTail]
  cases first : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.charClass [(97, 122)] "[a-z]") input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, first]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, first]; rfl
    | some start =>
      cases tail : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.star nameChars) start with
      | error reason => simp [runChoices, foldChoice, runSequence, next, first, tail]; rfl
      | ok value => cases value with
        | none => simp [runChoices, foldChoice, runSequence, next, first, tail]; rfl
        | some rest =>
          cases qualifiedRead : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.opt qualified) rest with
          | error reason => simp [runChoices, foldChoice, runSequence, next, first, tail, qualifiedRead]; rfl
          | ok value => cases value with
            | none => simp [runChoices, foldChoice, runSequence, next, first, tail, qualifiedRead]; rfl
            | some ending =>
              cases boundary : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.notPred secondDot) ending with
              | error reason => simp [runChoices, foldChoice, runSequence, next, first, tail, qualifiedRead, boundary]; rfl
              | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, first, tail, qualifiedRead, boundary] <;> rfl

/-- The command-name tail is maximal for every input suffix, with no fixed
    bound on its number of characters. -/
theorem I1_I2_identifier_tail_total (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 2 + extra) nameTail input =
      .ok (some (input.dropWhile (inClass [(97, 122), (48, 57), (45, 45)]))) :=
  LineBoundaryTotal.star_class _ "[a-z0-9\\-]" input extra

private def triviaItem := Expr.choice [[.opt (.ref "Ws" []), .ref "ExprComment" []]]

/-- Repeated comments retain PEG's distinction between miss and error. The
    final optional whitespace consumes the suffix after the last comment. -/
theorem I1_I2_generated_expression_trivia (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "ES" []) input =
      next (RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [] n triviaItem) (fuel + 1) input)
        (recognizeEnv Generated.pegGrammar [] (fuel + 1) (.opt (.ref "Ws" []))) := by
  change recognizeEnv _ [] (fuel + 2) (.choice [[.star triviaItem, .opt (.ref "Ws" [])]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 1) item rest) _ [] xs input) [[.star triviaItem, .opt (.ref "Ws" [])]] = _
  have repeated := RuleRepetition.star Generated.pegGrammar [] triviaItem (fuel + 1) input
  cases first : RuleRepetition.scan (fun n => recognizeEnv Generated.pegGrammar [] n triviaItem) (fuel + 1) input with
  | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, first]; rfl
  | ok value => cases value with
    | none => simp [runChoices, foldChoice, runSequence, next, repeated, first]; rfl
    | some rest =>
      cases trailing : recognizeEnv Generated.pegGrammar [] (fuel + 1) (.opt (.ref "Ws" [])) rest with
      | error reason => simp [runChoices, foldChoice, runSequence, next, repeated, first, trailing]; rfl
      | ok value => cases value <;> simp [runChoices, foldChoice, runSequence, next, repeated, first, trailing] <;> rfl

end LexicalTotal
