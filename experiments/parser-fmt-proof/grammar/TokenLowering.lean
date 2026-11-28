import CstWrapper
import KeywordLowering
namespace TokenLowering
open CstWrapper

def token : Element → Option KeywordLowering.Token
  | .token "Word" chars => some ⟨.word,chars⟩
  | .token "StringLit" chars => some ⟨.quoted,chars⟩
  | .token "Eq" chars => some ⟨.equals,chars⟩
  | _ => none

def value (elements : List Element) : Option KeywordLowering.Value :=
  match elements with
  | [element] => (token element).bind KeywordLowering.argValue
  | _ => none

def read (grammar : PegModel.Grammar) (name : String) (fuel : Nat)
    (input : List Char) (children : List Element) : Except String (Option (List Char × Option KeywordLowering.Value)) :=
  (CstWrapper.project grammar name fuel input children).map
    (fun result => result.map fun pair => (pair.1,value pair.2))

theorem I1_generated_word_value (word : WordRoundTrip.Word) (sep : Char) (tail : List Char)
    (extra : Nat) (children : List Element)
    (safe : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := word.chars ++ sep::tail
    read Generated.pegGrammar "Word" (input.length+8+extra) input children =
      .ok (some (sep::tail,some (.word word.chars))) := by
  dsimp only
  unfold read
  rw [CstWrapper.I1_generated_word_token word sep tail extra children safe blocked]
  rfl

theorem I1_generated_quoted_value (parts : List StringRoundTrip.Part) (suffix : List Char)
    (extra : Nat) (children : List Element) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    read Generated.pegGrammar "StringLit" (parts.length+7+extra) (front ++ suffix) children =
      .ok (some (suffix,some (.string (parts.map StringRoundTrip.partValue)))) := by
  dsimp only
  unfold read
  rw [CstWrapper.I1_generated_quoted_token parts suffix extra children]
  have decoded := KeywordLowering.unquote_spelling parts
  simp only [MixedKeywords.spelling] at decoded
  simp [Except.map, value, token, KeywordLowering.argValue, decoded]

theorem I1_generated_eq_not_value (tail : List Char) (extra : Nat) (children : List Element) :
    read Generated.pegGrammar "Eq" (extra+3) ('='::tail) children = .ok (some (tail,none)) := by
  unfold read
  rw [CstWrapper.I1_generated_eq_token tail extra children]
  rfl

def rawFields (entry : MixedKeywords.Entry) : List Element :=
  [.token "Word" entry.1.chars,.token "Eq" ['='],
    match entry.2 with
    | .word value => .token "Word" value.chars
    | .string parts => .token "StringLit" (MixedKeywords.spelling (.string parts))]
def keyword (fields : List Element) : Option (List Char × KeywordLowering.Value) :=
  KeywordLowering.lowerKeyword (fields.filterMap token)
def arguments (elements : List Element) : List (List Char × KeywordLowering.Value) :=
  elements.filterMap fun element => match element with
    | .node "KeywordArgument" fields => keyword fields
    | _ => none

theorem I1_converted_keyword (entry : MixedKeywords.Entry) :
    keyword (rawFields entry) = some (MixedKeywords.abstract entry) := by
  rcases entry with ⟨name,input⟩
  cases input with
  | word value => rfl
  | string parts =>
    change some (name.chars,QuotedKeywords.Value.string (KeywordLowering.unquote
      (MixedKeywords.spelling (.string parts)))) = _
    rw [KeywordLowering.unquote_spelling]
    rfl

theorem I1_classified_keyword (entry : MixedKeywords.Entry) (input rest : List Char) :
    arguments (wrap Generated.pegGrammar "KeywordArgument" input rest (rawFields entry)) =
      [MixedKeywords.abstract entry] := by
  rw [CstWrapper.I1_generated_keyword_node]
  simp [arguments,List.filterMap,I1_converted_keyword]

theorem I1_converted_arguments (entries : List MixedKeywords.Entry) :
    arguments (entries.map fun entry => Element.node "KeywordArgument" (rawFields entry)) =
      entries.map MixedKeywords.abstract := by
  induction entries with
  | nil => rfl
  | cons entry entries ih =>
    simp only [List.map_cons,arguments,List.filterMap,I1_converted_keyword]
    exact congrArg (List.cons (MixedKeywords.abstract entry)) ih

#print axioms I1_generated_word_value
#print axioms I1_generated_quoted_value
#print axioms I1_generated_eq_not_value
end TokenLowering
