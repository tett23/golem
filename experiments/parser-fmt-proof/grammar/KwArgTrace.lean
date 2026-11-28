import KeywordTrace
import KwArgMetadata
namespace KwArgTrace
open PegModel CstWrapper

def read (grammar : Grammar) (fuel : Nat) (input : List Char) : KeywordTrace.Result :=
  if fuel < 2 then .error "fuel"
  else KeywordTrace.body grammar "KwArg"
    (fun name args source =>
      if name == "KeywordArgument" && args.isEmpty then KeywordTrace.keyword grammar (fuel-2) source
      else KeywordTrace.leaf grammar (fuel-2) name args source) input

theorem I1_quoted_capture (name : WordRoundTrip.Word) (parts : List StringRoundTrip.Part)
    (suffix : List Char) (extra : Nat) (safe : WordRoundTrip.startsComment name.chars = false) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    let input := name.chars ++ '='::(front++suffix)
    read Generated.pegGrammar (input.length+parts.length+18+extra) input =
      .ok (some (suffix,[Element.node "KeywordArgument"
        (TokenLowering.rawFields (name,.string parts))])) := by
  dsimp only
  unfold read
  rw [if_neg (by omega)]
  unfold KeywordTrace.body
  have fields := kwarg_found
  cases found : Generated.pegGrammar.rules.find? (fun rule => rule.name == "KwArg") with
  | none => simp [found] at fields
  | some rule =>
    rw [found] at fields
    have fields := Option.some.inj fields
    have params : rule.params = [] := congrArg Prod.fst fields
    have templates : rule.templateParams = [] := congrArg (Prod.fst ∘ Prod.snd) fields
    have items : rule.alts.map (·.items) = [.ref "KeywordArgument" []]::fallback := congrArg (Prod.snd ∘ Prod.snd) fields
    simp only [params,templates,items]
    change KeywordTrace.finish Generated.pegGrammar "KwArg" _
      (KeywordTrace.choices _ ([.ref "KeywordArgument" []]::fallback) _) = _
    have budget (n : Nat) : n+parts.length+18+extra-2 = n+parts.length+16+extra := by omega
    simp only [KeywordTrace.choices,KeywordTrace.sequence]
    rw [budget]
    simp only [List.isEmpty]
    rw [KeywordTrace.I1_quoted_keyword name parts suffix extra safe]
    simp [KeywordTrace.finish,KeywordTrace.sequence,CstWrapper.wrap,kwarg_inline,Except.map]

theorem I1_word_capture (name word : WordRoundTrip.Word) (sep : Char) (tail : List Char)
    (extra : Nat) (safeName : WordRoundTrip.startsComment name.chars = false)
    (safeValue : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := name.chars ++ '='::(word.chars++sep::tail)
    read Generated.pegGrammar (input.length+22+extra) input =
      .ok (some (sep::tail,[Element.node "KeywordArgument"
        (TokenLowering.rawFields (name,.word word))])) := by
  dsimp only
  unfold read
  rw [if_neg (by omega)]
  unfold KeywordTrace.body
  have fields := kwarg_found
  cases found : Generated.pegGrammar.rules.find? (fun rule => rule.name == "KwArg") with
  | none => simp [found] at fields
  | some rule =>
    rw [found] at fields
    have fields := Option.some.inj fields
    have params : rule.params = [] := congrArg Prod.fst fields
    have templates : rule.templateParams = [] := congrArg (Prod.fst ∘ Prod.snd) fields
    have items : rule.alts.map (·.items) = [.ref "KeywordArgument" []]::fallback := congrArg (Prod.snd ∘ Prod.snd) fields
    simp only [params,templates,items]
    change KeywordTrace.finish Generated.pegGrammar "KwArg" _
      (KeywordTrace.choices _ ([.ref "KeywordArgument" []]::fallback) _) = _
    have budget (n : Nat) : n+22+extra-2 = n+20+extra := by omega
    simp only [KeywordTrace.choices,KeywordTrace.sequence]
    rw [budget]
    simp only [List.isEmpty]
    rw [KeywordTrace.I1_word_keyword name word sep tail extra safeName safeValue blocked]
    simp [KeywordTrace.finish,KeywordTrace.sequence,CstWrapper.wrap,kwarg_inline,Except.map]

theorem I1_quoted_erasure (name : WordRoundTrip.Word) (parts : List StringRoundTrip.Part)
    (suffix : List Char) (extra : Nat) (safe : WordRoundTrip.startsComment name.chars = false) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    let input := name.chars ++ '='::(front++suffix)
    let fuel := input.length+parts.length+18+extra
    KeywordTrace.erase (read Generated.pegGrammar fuel input) =
      recognizeEnv Generated.pegGrammar [] fuel (.ref "KwArg" []) input := by
  dsimp only
  rw [I1_quoted_capture name parts suffix extra safe]
  have child := KeywordTrace.I1_quoted_erasure name parts suffix extra safe
  dsimp only at child
  rw [KeywordTrace.I1_quoted_keyword name parts suffix extra safe] at child
  let input := name.chars ++ '='::(('"'::(StringRoundTrip.spell parts ++ ['"']))++suffix)
  have childHit : recognizeEnv Generated.pegGrammar [] (input.length+parts.length+15+extra+1)
      (.ref "KeywordArgument" []) input = .ok (some suffix) := by
    have budget : input.length+parts.length+15+extra+1 = input.length+parts.length+16+extra := by omega
    rw [budget]
    exact child.symm
  have result := ArgumentsRoundTrip.canonical_kwarg_of_keyword
    (input.length+parts.length+15+extra) input suffix childHit
  have budget : input.length+parts.length+15+extra+3 = input.length+parts.length+18+extra := by omega
  rw [budget] at result
  exact result.symm

theorem I1_word_erasure (name word : WordRoundTrip.Word) (sep : Char) (tail : List Char)
    (extra : Nat) (safeName : WordRoundTrip.startsComment name.chars = false)
    (safeValue : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := name.chars ++ '='::(word.chars++sep::tail)
    let fuel := input.length+22+extra
    KeywordTrace.erase (read Generated.pegGrammar fuel input) =
      recognizeEnv Generated.pegGrammar [] fuel (.ref "KwArg" []) input := by
  dsimp only
  rw [I1_word_capture name word sep tail extra safeName safeValue blocked]
  have child := KeywordTrace.I1_word_erasure name word sep tail extra safeName safeValue blocked
  dsimp only at child
  rw [KeywordTrace.I1_word_keyword name word sep tail extra safeName safeValue blocked] at child
  let input := name.chars ++ '='::(word.chars++sep::tail)
  have childHit : recognizeEnv Generated.pegGrammar [] (input.length+19+extra+1)
      (.ref "KeywordArgument" []) input = .ok (some (sep::tail)) := by
    have budget : input.length+19+extra+1 = input.length+20+extra := by omega
    rw [budget]
    exact child.symm
  have result := ArgumentsRoundTrip.canonical_kwarg_of_keyword
    (input.length+19+extra) input (sep::tail) childHit
  have budget : input.length+19+extra+3 = input.length+22+extra := by omega
  rw [budget] at result
  exact result.symm

theorem I1_quoted_ast (name : WordRoundTrip.Word) (parts : List StringRoundTrip.Part)
    (suffix : List Char) (extra : Nat) (safe : WordRoundTrip.startsComment name.chars = false) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    let input := name.chars ++ '='::(front++suffix)
    KeywordTrace.lower (read Generated.pegGrammar (input.length+parts.length+18+extra) input) =
      .ok (some (suffix,[(name.chars,QuotedKeywords.Value.string (parts.map StringRoundTrip.partValue))])) := by
  dsimp only
  rw [I1_quoted_capture name parts suffix extra safe]
  simp [KeywordTrace.lower,Except.map,TokenLowering.arguments,List.filterMap,
    TokenLowering.I1_converted_keyword,MixedKeywords.abstract,MixedKeywords.abstractValue]

theorem I1_word_ast (name word : WordRoundTrip.Word) (sep : Char) (tail : List Char)
    (extra : Nat) (safeName : WordRoundTrip.startsComment name.chars = false)
    (safeValue : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := name.chars ++ '='::(word.chars++sep::tail)
    KeywordTrace.lower (read Generated.pegGrammar (input.length+22+extra) input) =
      .ok (some (sep::tail,[(name.chars,QuotedKeywords.Value.word word.chars)])) := by
  dsimp only
  rw [I1_word_capture name word sep tail extra safeName safeValue blocked]
  simp [KeywordTrace.lower,Except.map,TokenLowering.arguments,List.filterMap,
    TokenLowering.I1_converted_keyword,MixedKeywords.abstract,MixedKeywords.abstractValue]

#print axioms I1_quoted_capture
#print axioms I1_word_capture
#print axioms I1_quoted_erasure
#print axioms I1_word_erasure
#print axioms I1_quoted_ast
#print axioms I1_word_ast
end KwArgTrace
