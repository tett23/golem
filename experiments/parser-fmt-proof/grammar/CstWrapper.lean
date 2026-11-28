import StringRoundTrip
import ArgumentsRoundTrip
import CstWrapperMetadata
namespace CstWrapper
inductive Element where
  | token (name : String) (chars : List Char)
  | node (name : String) (children : List Element)
  deriving Repr

def consumed (input rest : List Char) : List Char := input.take (input.length - rest.length)
def wrap (grammar : PegModel.Grammar) (name : String) (input rest : List Char)
    (children : List Element) : List Element :=
  if grammar.inline.contains name then children
  else if grammar.tokens.contains name then
    [.token name (consumed input rest)]
  else [.node name children]

def project (grammar : PegModel.Grammar) (name : String) (fuel : Nat)
    (input : List Char) (children : List Element) : Except String (Option (List Char × List Element)) :=
  match PegModel.recognizeEnv grammar [] fuel (.ref name []) input with
  | .error error => .error error
  | .ok none => .ok none
  | .ok (some rest) => .ok (some (rest,wrap grammar name input rest children))
theorem consumed_append (front rest : List Char) : consumed (front ++ rest) rest = front := by
  simp only [consumed,List.length_append,Nat.add_sub_cancel]
  induction front with
  | nil => rfl
  | cons c front ih => simpa [List.take] using congrArg (List.cons c) ih

theorem wrap_token (grammar : PegModel.Grammar) (name : String) (input rest : List Char)
    (children : List Element) (notInline : grammar.inline.contains name = false)
    (isToken : grammar.tokens.contains name = true) :
    wrap grammar name input rest children = [.token name (consumed input rest)] := by
  simp [wrap,notInline,isToken]

theorem wrap_inline (grammar : PegModel.Grammar) (name : String) (input rest : List Char)
    (children : List Element) (isInline : grammar.inline.contains name = true) :
    wrap grammar name input rest children = children := by simp [wrap,isInline]

theorem wrap_node (grammar : PegModel.Grammar) (name : String) (input rest : List Char)
    (children : List Element) (notInline : grammar.inline.contains name = false)
    (notToken : grammar.tokens.contains name = false) :
    wrap grammar name input rest children = [.node name children] := by simp [wrap,notInline,notToken]

theorem I1_generated_word_token (word : WordRoundTrip.Word) (sep : Char) (tail : List Char)
    (extra : Nat) (children : List Element)
    (safe : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := word.chars ++ sep::tail
    project Generated.pegGrammar "Word" (input.length+8+extra) input children =
      .ok (some (sep::tail,[.token "Word" word.chars])) := by
  have hit := ArgumentsRoundTrip.canonical_word_before_separator word sep tail extra safe blocked
  dsimp only
  unfold project
  rw [hit]
  simp only
  rw [wrap_token _ _ _ _ _ word_not_inline word_token,consumed_append]

theorem I1_generated_quoted_token (parts : List StringRoundTrip.Part) (suffix : List Char)
    (extra : Nat) (children : List Element) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    project Generated.pegGrammar "StringLit" (parts.length+7+extra) (front ++ suffix) children =
      .ok (some (suffix,[.token "StringLit" front])) := by
  have hit := (StringRoundTrip.I1_generated_quoted_round_trip parts suffix extra).1
  dsimp only
  unfold project
  simp only [List.cons_append,List.append_assoc,List.singleton_append,List.nil_append]
  rw [hit]
  simp only
  rw [wrap_token _ _ _ _ _ string_not_inline string_token]
  have same := consumed_append ('"'::(StringRoundTrip.spell parts ++ ['"'])) suffix
  simpa [List.cons_append,List.append_assoc] using congrArg
    (fun raw => (Except.ok (some (suffix,[Element.token "StringLit" raw])) : Except String (Option (List Char × List Element)))) same

theorem I1_generated_eq_token (tail : List Char) (extra : Nat) (children : List Element) :
    project Generated.pegGrammar "Eq" (extra+3) ('='::tail) children =
      .ok (some (tail,[.token "Eq" ['=']])) := by
  have hit : PegModel.recognizeEnv Generated.pegGrammar [] (extra+3) (.ref "Eq" []) ('='::tail) = .ok (some tail) := by
    have literal : PegModel.recognizeEnv Generated.pegGrammar [] (extra+1) (.lit "=" "'='") ('='::tail) = .ok (some tail) := by
      have total := PegModelTest.literal_total Generated.pegGrammar [] extra "=" "'='" ('='::tail)
      simpa [List.isPrefixOf] using total
    change PegModel.runChoices (fun items => PegModel.runSequence
      (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (extra+1) item source)
      _ [] items ('='::tail)) [[.lit "=" "'='"]] = .ok (some tail)
    simp [PegModel.runChoices,PegModel.foldChoice,PegModel.runSequence,literal,Except.map] <;> rfl
  unfold project
  rw [hit]
  simp only
  rw [wrap_token _ _ _ _ _ eq_not_inline eq_token]
  have same := consumed_append ['='] tail
  exact congrArg (fun raw => (Except.ok (some (tail,[Element.token "Eq" raw])) : Except String (Option (List Char × List Element)))) same

theorem I1_generated_argvalue_inline (input rest : List Char) (children : List Element) :
    wrap Generated.pegGrammar "ArgValue" input rest children = children :=
  wrap_inline _ _ _ _ _ argvalue_inline

theorem I1_generated_keyword_node (input rest : List Char) (children : List Element) :
    wrap Generated.pegGrammar "KeywordArgument" input rest children = [.node "KeywordArgument" children] :=
  wrap_node _ _ _ _ _ keyword_not_inline keyword_not_token
#print axioms I1_generated_word_token
#print axioms I1_generated_quoted_token
#print axioms I1_generated_eq_token
end CstWrapper
