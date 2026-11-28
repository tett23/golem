import KeywordTrace
import ArgumentMetadata
namespace ArgumentTrace
open PegModel CstWrapper

def read (grammar : Grammar) (fuel : Nat) (input : List Char) : KeywordTrace.Result :=
  if fuel < 2 then .error "fuel"
  else KeywordTrace.body grammar "Argument"
    (fun name args source =>
      if name == "ArgValue" && args.isEmpty then KeywordTrace.value grammar (fuel-2) source
      else KeywordTrace.leaf grammar (fuel-2) name args source) input

inductive Argument where
  | positional : KeywordLowering.Value → Argument
  deriving Repr

def arguments (elements : List Element) : List Argument :=
  elements.filterMap fun element => match element with
    | .node "Argument" fields => (TokenLowering.value fields).map Argument.positional
    | _ => none

def lower (result : KeywordTrace.Result) : Except String (Option (List Char × List Argument)) :=
  result.map (fun result => result.map fun (rest,children) => (rest,arguments children))

theorem I1_quoted_capture (parts : List StringRoundTrip.Part) (suffix : List Char) (extra : Nat) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    read Generated.pegGrammar (parts.length+11+extra) (front++suffix) =
      .ok (some (suffix,[Element.node "Argument" [Element.token "StringLit" front]])) := by
  dsimp only
  unfold read
  rw [if_neg (by omega)]
  unfold KeywordTrace.body
  rw [argument_found]
  change KeywordTrace.finish Generated.pegGrammar "Argument" _
    (KeywordTrace.choices _ [[.ref "ArgValue" []]] _) = _
  have budget : parts.length+11+extra-2 = parts.length+9+extra := by omega
  simp only [KeywordTrace.choices,KeywordTrace.sequence,List.isEmpty,budget]
  rw [KeywordTrace.value_quoted parts suffix extra]
  simp [KeywordTrace.finish,Except.map,CstWrapper.wrap,argument_not_inline,argument_not_token]

theorem I1_word_capture (word : WordRoundTrip.Word) (sep : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := word.chars ++ sep::tail
    read Generated.pegGrammar (input.length+12+extra) input =
      .ok (some (sep::tail,[Element.node "Argument" [Element.token "Word" word.chars]])) := by
  dsimp only
  unfold read
  rw [if_neg (by omega)]
  unfold KeywordTrace.body
  rw [argument_found]
  change KeywordTrace.finish Generated.pegGrammar "Argument" _
    (KeywordTrace.choices _ [[.ref "ArgValue" []]] _) = _
  have budget : (word.chars++sep::tail).length+12+extra-2 =
      (word.chars++sep::tail).length+10+extra := by omega
  simp only [KeywordTrace.choices,KeywordTrace.sequence,List.isEmpty,budget]
  rw [KeywordTrace.value_word word sep tail extra safe blocked]
  simp [KeywordTrace.finish,Except.map,CstWrapper.wrap,argument_not_inline,argument_not_token]

theorem I1_quoted_ast (parts : List StringRoundTrip.Part) (suffix : List Char) (extra : Nat) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    lower (read Generated.pegGrammar (parts.length+11+extra) (front++suffix)) =
      .ok (some (suffix,[.positional (.string (parts.map StringRoundTrip.partValue))])) := by
  dsimp only
  rw [I1_quoted_capture parts suffix extra]
  change (Except.ok (some (suffix,[Argument.positional (.string (KeywordLowering.unquote
    ('"'::(StringRoundTrip.spell parts ++ ['"']))))])) :
      Except String (Option (List Char × List Argument))) = _
  have decoded := KeywordLowering.unquote_spelling parts
  simp only [MixedKeywords.spelling] at decoded
  rw [decoded]

theorem I1_word_ast (word : WordRoundTrip.Word) (sep : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := word.chars ++ sep::tail
    lower (read Generated.pegGrammar (input.length+12+extra) input) =
      .ok (some (sep::tail,[.positional (.word word.chars)])) := by
  dsimp only
  rw [I1_word_capture word sep tail extra safe blocked]
  rfl

private theorem argument_of_value (fuel : Nat) (input rest : List Char)
    (hit : recognizeEnv Generated.pegGrammar [] fuel (.ref "ArgValue" []) input = .ok (some rest)) :
    recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "Argument" []) input = .ok (some rest) := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [argument_found]
  change runChoices (fun items => runSequence
    (fun scope item source => recognizeEnv Generated.pegGrammar scope fuel item source)
    _ [] items input) [[.ref "ArgValue" []]] = _
  simp [runChoices,foldChoice,runSequence,hit,Except.map] <;> rfl

private theorem quoted_value_recognizer (parts : List StringRoundTrip.Part)
    (suffix : List Char) (extra : Nat) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    recognizeEnv Generated.pegGrammar [] (parts.length+9+extra) (.ref "ArgValue" []) (front++suffix) =
      .ok (some suffix) := by
  dsimp only
  let fuel := parts.length+6+extra
  have stringHit := (StringRoundTrip.I1_generated_quoted_round_trip parts suffix extra).1
  have fuelString : parts.length+7+extra = fuel+1 := by dsimp [fuel]; omega
  rw [fuelString] at stringHit
  have fuelValue : parts.length+9+extra = fuel+3 := by dsimp [fuel]; omega
  rw [fuelValue]
  rw [QuotedArgumentRules.value_ref _ (fuel+2) _
    (QuotedArgumentRules.sourceRule "ArgValue") QuotedArgumentRules.value_found]
  change runChoices (fun items => runSequence
    (fun scope item source => recognizeEnv Generated.pegGrammar scope (fuel+1) item source)
    _ [] items _) QuotedArgumentRules.valueItems = _
  simp [QuotedArgumentRules.valueItems,runChoices,foldChoice,runSequence,stringHit,Except.map] <;> rfl

theorem I1_quoted_erasure (parts : List StringRoundTrip.Part) (suffix : List Char) (extra : Nat) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    KeywordTrace.erase (read Generated.pegGrammar (parts.length+11+extra) (front++suffix)) =
      recognizeEnv Generated.pegGrammar [] (parts.length+11+extra) (.ref "Argument" []) (front++suffix) := by
  dsimp only
  rw [I1_quoted_capture parts suffix extra]
  have recognized := argument_of_value (parts.length+9+extra) _ _ (quoted_value_recognizer parts suffix extra)
  have budget : parts.length+9+extra+2 = parts.length+11+extra := by omega
  rw [budget] at recognized
  simpa [KeywordTrace.erase,Except.map] using recognized.symm

theorem I1_word_erasure (word : WordRoundTrip.Word) (sep : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := word.chars ++ sep::tail
    KeywordTrace.erase (read Generated.pegGrammar (input.length+12+extra) input) =
      recognizeEnv Generated.pegGrammar [] (input.length+12+extra) (.ref "Argument" []) input := by
  dsimp only
  rw [I1_word_capture word sep tail extra safe blocked]
  have child := KeywordTrace.value_word_recognizer word sep tail extra safe blocked
  dsimp only at child
  have recognized := argument_of_value ((word.chars++sep::tail).length+extra+10) _ _ child
  have budget : (word.chars++sep::tail).length+extra+10+2 =
      (word.chars++sep::tail).length+12+extra := by omega
  rw [budget] at recognized
  simpa [KeywordTrace.erase,Except.map] using recognized.symm

#print axioms I1_quoted_capture
#print axioms I1_word_capture
#print axioms I1_quoted_ast
#print axioms I1_word_ast
#print axioms I1_quoted_erasure
#print axioms I1_word_erasure
end ArgumentTrace
