import WordEof
import ArgumentTrace
namespace ArgumentEof
open PegModel CstWrapper KeywordTrace
set_option autoImplicit false
private theorem token_at_eof (word : WordRoundTrip.Word) (extra : Nat) (children : List Element)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    project Generated.pegGrammar "Word" (word.chars.length+8+extra) word.chars children =
      .ok (some ([],[.token "Word" word.chars])) := by
  unfold project
  rw [WordEof.I1_word_at_eof word extra safe]
  simp only
  rw [wrap_token _ _ _ _ _ word_not_inline word_token]
  simp [consumed]

private theorem value_at_eof (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    let input := word.chars
    value Generated.pegGrammar (input.length+10+extra) input =
      .ok (some ([],[Element.token "Word" word.chars])) := by
  dsimp only
  let input := word.chars
  have wordHit : leaf Generated.pegGrammar (input.length+8+extra) "Word" [] input =
      .ok (some ([],[Element.token "Word" word.chars])) := by
    rw [leaf_project _ _ _ _ CstWrapper.word_token CstWrapper.word_not_inline]
    exact token_at_eof word extra [] safe
  cases chars : word.chars with
  | nil => exact False.elim (word.nonempty chars)
  | cons c cs =>
    have allowed : WordRoundTrip.allowed c = true := word.valid c (by simp [chars])
    have inputEq : input = c::(cs) := by simp [input,chars]
    have misses := WordRoundTrip.ordinary_value_precedence (input.length+extra) c (cs) allowed
    dsimp only at misses
    rcases misses with ⟨notString,notExpr,notReserved,notInline⟩
    rw [←inputEq] at notString notExpr notReserved notInline
    have ordered : input.length+extra+8=input.length+8+extra := by omega
    rw [ordered] at notString notExpr notReserved notInline
    have missString : leaf Generated.pegGrammar (input.length+8+extra) "StringLit" [] input = .ok none := by
      simp [leaf,notString]
    have missExpr : leaf Generated.pegGrammar (input.length+8+extra) "ExprCtx" [] input = .ok none := by
      simp [leaf,notExpr]
    have missReserved : leaf Generated.pegGrammar (input.length+8+extra) "ReservedBracket" [] input = .ok none := by
      simp [leaf,notReserved]
    have missInline : leaf Generated.pegGrammar (input.length+8+extra) "InlineCommand" ["0"] input = .ok none := by
      simp [leaf,notInline]
    rw [←inputEq]
    change value Generated.pegGrammar (input.length+10+extra) input = _
    unfold value
    rw [if_neg (by omega)]
    unfold body
    rw [QuotedArgumentRules.value_found]
    change finish Generated.pegGrammar "ArgValue" input
      (choices (leaf Generated.pegGrammar (input.length+10+extra-2))
        QuotedArgumentRules.valueItems input) = _
    rw [show input.length+10+extra-2=input.length+8+extra by omega]
    simp [QuotedArgumentRules.valueItems,choices,sequence,missString,missExpr,missReserved,missInline,wordHit,
      finish,Except.map,CstWrapper.I1_generated_argvalue_inline] <;> exact chars


theorem I1_capture (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    let input := word.chars
    ArgumentTrace.read Generated.pegGrammar (input.length+12+extra) input =
      .ok (some ([],[Element.node "Argument" [Element.token "Word" word.chars]])) := by
  dsimp only
  unfold ArgumentTrace.read
  rw [if_neg (by omega)]
  unfold KeywordTrace.body
  rw [ArgumentTrace.argument_found]
  change KeywordTrace.finish Generated.pegGrammar "Argument" _
    (KeywordTrace.choices _ [[.ref "ArgValue" []]] _) = _
  have budget : (word.chars).length+12+extra-2 =
      (word.chars).length+10+extra := by omega
  simp only [KeywordTrace.choices,KeywordTrace.sequence,List.isEmpty,budget]
  rw [value_at_eof word extra safe]
  simp [KeywordTrace.finish,Except.map,CstWrapper.wrap,ArgumentTrace.argument_not_inline,ArgumentTrace.argument_not_token]


theorem I1_ast (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    ArgumentTrace.lower (ArgumentTrace.read Generated.pegGrammar (word.chars.length+12+extra) word.chars) =
      .ok (some ([],[.positional (.word word.chars)])) := by
  rw [I1_capture word extra safe]
  rfl
private theorem value_recognizer_at_eof (value : WordRoundTrip.Word)
    (extra : Nat)
    (safe : WordRoundTrip.startsComment value.chars = false) :
    let input := value.chars
    PegModel.recognizeEnv Generated.pegGrammar []
      (input.length + extra + 10) (.ref "ArgValue" []) input =
        .ok (some ([])) := by
  dsimp only
  have safeStart := safe
  have word := WordEof.I1_word_at_eof value extra safeStart
  cases chars : value.chars with
  | nil => exact False.elim (value.nonempty chars)
  | cons c rest =>
      have allowed : WordRoundTrip.allowed c = true := value.valid c (by simp [chars])
      have misses := WordRoundTrip.ordinary_value_precedence
        ((value.chars).length + extra) c (rest) allowed
      rcases misses with ⟨notString, notExpr, notReserved, notInline⟩
      have inputEq : value.chars = c :: (rest) := by
        simp [chars]
      rw [← inputEq] at notString notExpr notReserved notInline
      have fuelWord : (value.chars).length + 8 + extra =
          ((value.chars).length + extra + 7) + 1 := by omega
      have fuelMiss : (value.chars).length + extra + 8 =
          ((value.chars).length + extra + 7) + 1 := by omega
      rw [fuelWord] at word
      rw [fuelMiss] at notString notExpr notReserved notInline
      have result := ArgumentsRoundTrip.canonical_argvalue_word
        ((value.chars).length + extra + 7)
        (value.chars) ([])
        notString notExpr notReserved notInline word
      have fuelResult : ((value.chars).length + extra + 7) + 3 =
          (value.chars).length + extra + 10 := by omega
      rw [fuelResult] at result
      simpa only [chars] using result



private theorem argument_of_value_at_eof (fuel : Nat) (input rest : List Char)
    (hit : recognizeEnv Generated.pegGrammar [] fuel (.ref "ArgValue" []) input = .ok (some rest)) :
    recognizeEnv Generated.pegGrammar [] (fuel+2) (.ref "Argument" []) input = .ok (some rest) := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [ArgumentTrace.argument_found]
  change runChoices (fun items => runSequence
    (fun scope item source => recognizeEnv Generated.pegGrammar scope fuel item source)
    _ [] items input) [[.ref "ArgValue" []]] = _
  simp [runChoices,foldChoice,runSequence,hit,Except.map] <;> rfl


theorem I1_erasure (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    KeywordTrace.erase (ArgumentTrace.read Generated.pegGrammar (word.chars.length+12+extra) word.chars) =
      recognizeEnv Generated.pegGrammar [] (word.chars.length+12+extra) (.ref "Argument" []) word.chars := by
  rw [I1_capture word extra safe]
  have child := value_recognizer_at_eof word extra safe
  dsimp only at child
  have recognized := argument_of_value_at_eof (word.chars.length+extra+10) _ _ child
  have budget : word.chars.length+extra+10+2 = word.chars.length+12+extra := by omega
  rw [budget] at recognized
  simpa [KeywordTrace.erase,Except.map] using recognized.symm
#print axioms I1_capture
#print axioms I1_ast
#print axioms I1_erasure
end ArgumentEof
