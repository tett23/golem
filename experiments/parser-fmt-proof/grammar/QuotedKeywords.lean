import StringRoundTrip
import ArgumentsRoundTrip
import QuotedArgumentRules
namespace QuotedKeywords
open WordRoundTrip

abbrev Entry := Word × List StringRoundTrip.Part
inductive Value where
  | word (chars : List Char)
  | string (chars : List Char)
  deriving Repr, DecidableEq

def abstract (entry : Entry) : List Char × Value :=
  (entry.1.chars,.string (entry.2.map StringRoundTrip.partValue))

def printArgs : List Entry → List Char
  | [] => ['\n']
  | (name,parts)::rest => ' ' :: name.chars ++ '=' :: '"' ::
      (StringRoundTrip.spell parts ++ '"' :: printArgs rest)

def parseArgs : Nat → List Char → Option (List (List Char × Value))
  | _, ['\n'] => some []
  | fuel+1, ' '::rest =>
    if startsComment rest then none else
    let name := rest.takeWhile allowed
    let afterName := rest.dropWhile allowed
    if name.isEmpty then none else
    match afterName with
    | '='::'"'::body => do
      let (spelling,afterValue) ← StringRoundTrip.scanString Generated.stringLitEscapeFirst body
      let values ← parseArgs fuel afterValue
      some ((name,.string (StringRoundTrip.unescape spelling))::values)
    | _ => none
  | _, _ => none

def safeNames (args : List Entry) : Prop :=
  ∀ entry ∈ args, startsComment entry.1.chars = false

private theorem not_empty (word : Word) : word.chars.isEmpty = false := by
  cases h : word.chars with
  | nil => exact False.elim (word.nonempty h)
  | cons c rest => rfl

theorem I1_I2_quoted_arguments (args : List Entry) (fuel : Nat)
    (safe : safeNames args) (enough : args.length ≤ fuel) :
    parseArgs fuel (printArgs args) = some (args.map abstract) := by
  induction args generalizing fuel with
  | nil => cases fuel <;> rfl
  | cons entry args ih =>
    cases fuel with
    | zero => simp at enough
    | succ fuel =>
      rcases entry with ⟨name,parts⟩
      have firstSafe := safe (name,parts) (by simp)
      have guarded := safe_name_before_equals name
        ('"' :: (StringRoundTrip.spell parts ++ '"' :: printArgs args)) firstSafe
      have restSafe : safeNames args := by
        intro entry member
        exact safe entry (by simp [member])
      have restEnough : args.length ≤ fuel := Nat.le_of_succ_le_succ enough
      simp [printArgs,parseArgs,
        take_append name.chars ('"' :: (StringRoundTrip.spell parts ++ '"' :: printArgs args)) '=' name.valid (by decide),
        drop_append name.chars ('"' :: (StringRoundTrip.spell parts ++ '"' :: printArgs args)) '=' name.valid (by decide),
        guarded,not_empty name,StringRoundTrip.scan_spell,StringRoundTrip.unescape_spell,
        ih fuel restSafe restEnough,abstract]
private theorem argvalue_first (fuel : Nat) (input rest : List Char)
    (hit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel+1) (.ref "StringLit" []) input = .ok (some rest)) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel+3) (.ref "ArgValue" []) input = .ok (some rest) := by
  rw [QuotedArgumentRules.value_ref _ (fuel+2) input
    (QuotedArgumentRules.sourceRule "ArgValue") QuotedArgumentRules.value_found]
  change PegModel.runChoices (fun items => PegModel.runSequence
    (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+1) item source)
    _ [] items input) [[.ref "StringLit" []],[.ref "ExprCtx" []],[.ref "ReservedBracket" []],
      [.ref "InlineCommand" ["0"]],[.ref "Word" []]] = _
  simp [PegModel.runChoices,PegModel.foldChoice,PegModel.runSequence,hit,Except.map] <;> rfl

theorem I1_generated_quoted_keyword (name : Word) (parts : List StringRoundTrip.Part)
    (suffix : List Char) (extra : Nat) (safe : startsComment name.chars = false) :
    let input := name.chars ++ '=' :: '"' :: (StringRoundTrip.spell parts ++ '"' :: suffix)
    PegModel.recognizeEnv Generated.pegGrammar [] (input.length + parts.length + 16 + extra)
      (.ref "KeywordArgument" []) input = .ok (some suffix) := by
  let input := name.chars ++ '=' :: '"' :: (StringRoundTrip.spell parts ++ '"' :: suffix)
  let fuel := input.length + parts.length + extra + 13
  have word := ArgumentsRoundTrip.canonical_word_at_budget name '='
    ('"' :: (StringRoundTrip.spell parts ++ '"' :: suffix)) (fuel+1) safe (by decide) (by dsimp [fuel,input]; omega)
  have eqHit : PegModel.recognizeEnv Generated.pegGrammar [] (fuel+1) (.ref "Eq" [])
    ('=' :: '"' :: (StringRoundTrip.spell parts ++ '"' :: suffix)) =
    .ok (some ('"' :: (StringRoundTrip.spell parts ++ '"' :: suffix))) := by rfl
  have stringHit := (StringRoundTrip.I1_generated_quoted_round_trip parts suffix (input.length+5+extra)).1
  have matchFuel : parts.length+7+(input.length+5+extra) = (fuel-2)+1 := by dsimp [fuel]; omega
  rw [matchFuel] at stringHit
  have valueHit := argvalue_first (fuel-2) _ _ stringHit
  have enough : fuel-2+3 = fuel+1 := by dsimp [fuel]; omega
  rw [enough] at valueHit
  have keyword : PegModel.recognizeEnv Generated.pegGrammar [] (fuel+3)
      (.ref "KeywordArgument" []) input = .ok (some suffix) := by
    rw [QuotedArgumentRules.keyword_ref _ (fuel+2) input
      (QuotedArgumentRules.sourceRule "KeywordArgument") QuotedArgumentRules.keyword_found]
    change PegModel.runChoices (fun items => PegModel.runSequence
      (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (fuel+1) item source)
      _ [] items input) [[.ref "Word" [],.ref "Eq" [],.ref "ArgValue" []]] = _
    simp [PegModel.runChoices,PegModel.foldChoice,PegModel.runSequence,word,eqHit,valueHit,Except.map] <;> rfl
  change PegModel.recognizeEnv Generated.pegGrammar [] (input.length+parts.length+16+extra)
    (.ref "KeywordArgument" []) input = _
  rw [show input.length+parts.length+16+extra = fuel+3 by dsimp [fuel]; omega]
  exact keyword
#print axioms I1_I2_quoted_arguments
#print axioms I1_generated_quoted_keyword
end QuotedKeywords
