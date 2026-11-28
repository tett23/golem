import TokenLowering
namespace KeywordTrace
open PegModel CstWrapper
abbrev Result := Except String (Option (List Char × List Element))
abbrev Reader := String → List String → List Char → Result

def leaf (grammar : Grammar) (fuel : Nat) (name : String) (args : List String)
    (input : List Char) : Result :=
  match recognizeEnv grammar [] fuel (.ref name args) input with
  | .error reason => .error reason
  | .ok none => .ok none
  | .ok (some rest) =>
    if grammar.tokens.contains name && !grammar.inline.contains name then
      .ok (some (rest,wrap grammar name input rest []))
    else .error "unmodeled non-token capture"

def sequence (read : Reader) : List Expr → List Char → Result
  | [],input => .ok (some (input,[]))
  | .ref name args::more,input =>
    match read name args input with
    | .error reason => .error reason
    | .ok none => .ok none
    | .ok (some (after,first)) =>
      match sequence read more after with
      | .error reason => .error reason
      | .ok none => .ok none
      | .ok (some (rest,last)) => .ok (some (rest,first++last))
  | _::_,_ => .error "unmodeled non-reference expression"

def choices (read : Reader) : List (List Expr) → List Char → Result
  | [],_ => .ok none
  | items::more,input =>
    match sequence read items input with
    | .ok none => choices read more input
    | result => result

def finish (grammar : Grammar) (name : String) (input : List Char) (result : Result) : Result :=
  result.map (fun result => result.map fun (rest,children) => (rest,wrap grammar name input rest children))
def body (grammar : Grammar) (name : String) (read : Reader) (input : List Char) : Result :=
  match grammar.rules.find? (fun rule => rule.name == name) with
  | none => .error "missing trace rule"
  | some rule =>
    if rule.params.isEmpty && rule.templateParams.isEmpty then
      finish grammar name input (choices read (rule.alts.map (·.items)) input)
    else .error "unmodeled parameterized trace rule"

def value (grammar : Grammar) (fuel : Nat) (input : List Char) : Result :=
  if fuel < 2 then .error "fuel"
  else body grammar "ArgValue" (leaf grammar (fuel-2)) input

def keyword (grammar : Grammar) (fuel : Nat) (input : List Char) : Result :=
  if fuel < 2 then .error "fuel"
  else body grammar "KeywordArgument"
    (fun name args source =>
      if name == "ArgValue" && args.isEmpty then value grammar (fuel-2) source
      else leaf grammar (fuel-2) name args source) input

theorem leaf_project (grammar : Grammar) (fuel : Nat) (name : String) (input : List Char)
    (isToken : grammar.tokens.contains name = true)
    (notInline : grammar.inline.contains name = false) :
    leaf grammar fuel name [] input = CstWrapper.project grammar name fuel input [] := by
  simp [leaf,CstWrapper.project,isToken,notInline] <;> rfl

theorem value_quoted (parts : List StringRoundTrip.Part) (suffix : List Char) (extra : Nat) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    value Generated.pegGrammar (parts.length+9+extra) (front++suffix) =
      .ok (some (suffix,[Element.token "StringLit" front])) := by
  dsimp only
  unfold value
  rw [if_neg (by omega)]
  unfold body
  rw [QuotedArgumentRules.value_found]
  change finish Generated.pegGrammar "ArgValue" _
    (choices (leaf Generated.pegGrammar (parts.length+9+extra-2))
      QuotedArgumentRules.valueItems _) = _
  have budget : parts.length+9+extra-2 = parts.length+7+extra := by omega
  rw [budget]
  simp only [QuotedArgumentRules.valueItems,choices,sequence]
  rw [leaf_project _ _ _ _ CstWrapper.string_token CstWrapper.string_not_inline,
    CstWrapper.I1_generated_quoted_token parts suffix extra []]
  simp [finish,Except.map,CstWrapper.I1_generated_argvalue_inline]


theorem I1_quoted_keyword (name : WordRoundTrip.Word) (parts : List StringRoundTrip.Part)
    (suffix : List Char) (extra : Nat) (safe : WordRoundTrip.startsComment name.chars = false) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    let input := name.chars ++ '='::(front++suffix)
    keyword Generated.pegGrammar (input.length+parts.length+16+extra) input =
      .ok (some (suffix,[Element.node "KeywordArgument"
        (TokenLowering.rawFields (name,.string parts))])) := by
  dsimp only
  let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
  let input := name.chars ++ '='::(front++suffix)
  let budget := input.length+parts.length+16+extra
  let read : Reader := fun child args source =>
    if child == "ArgValue" && args.isEmpty then value Generated.pegGrammar (budget-2) source
    else leaf Generated.pegGrammar (budget-2) child args source
  have word : read "Word" [] input =
      .ok (some ('='::(front++suffix),[Element.token "Word" name.chars])) := by
    change leaf Generated.pegGrammar (budget-2) "Word" [] input = _
    rw [leaf_project _ _ _ _ CstWrapper.word_token CstWrapper.word_not_inline]
    rw [show budget-2=input.length+8+(parts.length+6+extra) by dsimp [budget]; omega]
    exact CstWrapper.I1_generated_word_token name '=' (front++suffix) (parts.length+6+extra)
      [] safe (by decide)
  have equals : read "Eq" [] ('='::(front++suffix)) =
      .ok (some (front++suffix,[Element.token "Eq" ['=']])) := by
    change leaf Generated.pegGrammar (budget-2) "Eq" [] ('='::(front++suffix)) = _
    rw [leaf_project _ _ _ _ CstWrapper.eq_token CstWrapper.eq_not_inline]
    rw [show budget-2=(input.length+parts.length+11+extra)+3 by dsimp [budget]; omega]
    exact CstWrapper.I1_generated_eq_token (front++suffix) (input.length+parts.length+11+extra) []
  have quoted : read "ArgValue" [] (front++suffix) =
      .ok (some (suffix,[Element.token "StringLit" front])) := by
    change value Generated.pegGrammar (budget-2) (front++suffix) = _
    rw [show budget-2=parts.length+9+(input.length+5+extra) by dsimp [budget]; omega]
    exact value_quoted parts suffix (input.length+5+extra)
  change keyword Generated.pegGrammar budget input = _
  unfold keyword
  rw [if_neg (by dsimp [budget]; omega)]
  unfold body
  rw [QuotedArgumentRules.keyword_found]
  change finish Generated.pegGrammar "KeywordArgument" input
    (choices read [QuotedArgumentRules.keywordItems] input) = _
  simp only [front,List.cons_append,List.append_assoc,List.singleton_append,List.nil_append] at word equals quoted
  simp [QuotedArgumentRules.keywordItems,choices,sequence,word,equals,quoted,
    finish,Except.map,CstWrapper.I1_generated_keyword_node,TokenLowering.rawFields,
    MixedKeywords.spelling,front]

#print axioms I1_quoted_keyword


def erase (result : Result) : ParseResult :=
  result.map (fun value => value.map (·.1))
theorem project_erasure (grammar : Grammar) (name : String) (fuel : Nat)
    (input : List Char) (children : List Element) :
    erase (CstWrapper.project grammar name fuel input children) =
      recognizeEnv grammar [] fuel (.ref name []) input := by
  unfold erase CstWrapper.project
  cases recognizeEnv grammar [] fuel (.ref name []) input with
  | error reason => rfl
  | ok value => cases value <;> rfl

def lower (result : Result) : Except String (Option (List Char × List (List Char × KeywordLowering.Value))) :=
  result.map (fun value => value.map fun (rest,children) => (rest,TokenLowering.arguments children))

theorem I1_quoted_erasure (name : WordRoundTrip.Word) (parts : List StringRoundTrip.Part)
    (suffix : List Char) (extra : Nat) (safe : WordRoundTrip.startsComment name.chars = false) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    let input := name.chars ++ '='::(front++suffix)
    let fuel := input.length+parts.length+16+extra
    erase (keyword Generated.pegGrammar fuel input) =
      recognizeEnv Generated.pegGrammar [] fuel (.ref "KeywordArgument" []) input := by
  dsimp only
  rw [I1_quoted_keyword name parts suffix extra safe]
  have recognized := QuotedKeywords.I1_generated_quoted_keyword name parts suffix extra safe
  dsimp only at recognized
  simpa [erase,Except.map,List.cons_append,List.append_assoc] using recognized.symm

theorem I1_quoted_ast (name : WordRoundTrip.Word) (parts : List StringRoundTrip.Part)
    (suffix : List Char) (extra : Nat) (safe : WordRoundTrip.startsComment name.chars = false) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    let input := name.chars ++ '='::(front++suffix)
    lower (keyword Generated.pegGrammar (input.length+parts.length+16+extra) input) =
      .ok (some (suffix,[(name.chars,QuotedKeywords.Value.string (parts.map StringRoundTrip.partValue))])) := by
  dsimp only
  rw [I1_quoted_keyword name parts suffix extra safe]
  simp [lower,Except.map,TokenLowering.arguments,List.filterMap,
    TokenLowering.I1_converted_keyword,MixedKeywords.abstract,MixedKeywords.abstractValue]

#print axioms I1_quoted_erasure
#print axioms I1_quoted_ast


theorem value_word (word : WordRoundTrip.Word) (sep : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := word.chars ++ sep::tail
    value Generated.pegGrammar (input.length+10+extra) input =
      .ok (some (sep::tail,[Element.token "Word" word.chars])) := by
  dsimp only
  let input := word.chars ++ sep::tail
  have wordHit : leaf Generated.pegGrammar (input.length+8+extra) "Word" [] input =
      .ok (some (sep::tail,[Element.token "Word" word.chars])) := by
    rw [leaf_project _ _ _ _ CstWrapper.word_token CstWrapper.word_not_inline]
    exact CstWrapper.I1_generated_word_token word sep tail extra [] safe blocked
  cases chars : word.chars with
  | nil => exact False.elim (word.nonempty chars)
  | cons c cs =>
    have allowed : WordRoundTrip.allowed c = true := word.valid c (by simp [chars])
    have inputEq : input = c::(cs++sep::tail) := by simp [input,chars]
    have misses := WordRoundTrip.ordinary_value_precedence (input.length+extra) c (cs++sep::tail) allowed
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
    simp only [List.cons_append]
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

#print axioms value_word


theorem I1_word_keyword (name word : WordRoundTrip.Word) (sep : Char) (tail : List Char)
    (extra : Nat) (safeName : WordRoundTrip.startsComment name.chars = false)
    (safeValue : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let valueInput := word.chars ++ sep::tail
    let input := name.chars ++ '='::valueInput
    keyword Generated.pegGrammar (input.length+20+extra) input =
      .ok (some (sep::tail,[Element.node "KeywordArgument"
        (TokenLowering.rawFields (name,.word word))])) := by
  dsimp only
  let valueInput := word.chars ++ sep::tail
  let input := name.chars ++ '='::valueInput
  let budget := input.length+20+extra
  let read : Reader := fun child args source =>
    if child == "ArgValue" && args.isEmpty then value Generated.pegGrammar (budget-2) source
    else leaf Generated.pegGrammar (budget-2) child args source
  have nameHit : read "Word" [] input =
      .ok (some ('='::valueInput,[Element.token "Word" name.chars])) := by
    change leaf Generated.pegGrammar (budget-2) "Word" [] input = _
    rw [leaf_project _ _ _ _ CstWrapper.word_token CstWrapper.word_not_inline]
    rw [show budget-2=input.length+8+(10+extra) by dsimp [budget]; omega]
    exact CstWrapper.I1_generated_word_token name '=' valueInput (10+extra) [] safeName (by decide)
  have eqHit : read "Eq" [] ('='::valueInput) =
      .ok (some (valueInput,[Element.token "Eq" ['=']])) := by
    change leaf Generated.pegGrammar (budget-2) "Eq" [] ('='::valueInput) = _
    rw [leaf_project _ _ _ _ CstWrapper.eq_token CstWrapper.eq_not_inline]
    rw [show budget-2=(input.length+15+extra)+3 by dsimp [budget]; omega]
    exact CstWrapper.I1_generated_eq_token valueInput (input.length+15+extra) []
  have valueHit : read "ArgValue" [] valueInput =
      .ok (some (sep::tail,[Element.token "Word" word.chars])) := by
    change value Generated.pegGrammar (budget-2) valueInput = _
    have enough : budget-2=valueInput.length+10+(name.chars.length+9+extra) := by
      dsimp [budget,input]
      simp only [List.length_append,List.length_cons]
      omega
    rw [enough]
    exact value_word word sep tail (name.chars.length+9+extra) safeValue blocked
  change keyword Generated.pegGrammar budget input = _
  unfold keyword
  rw [if_neg (by dsimp [budget]; omega)]
  unfold body
  rw [QuotedArgumentRules.keyword_found]
  change finish Generated.pegGrammar "KeywordArgument" input
    (choices read [QuotedArgumentRules.keywordItems] input) = _
  simp [QuotedArgumentRules.keywordItems,choices,sequence,nameHit,eqHit,valueHit,
    finish,Except.map,CstWrapper.I1_generated_keyword_node,TokenLowering.rawFields]

theorem I1_word_ast (name word : WordRoundTrip.Word) (sep : Char) (tail : List Char)
    (extra : Nat) (safeName : WordRoundTrip.startsComment name.chars = false)
    (safeValue : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := name.chars ++ '='::(word.chars++sep::tail)
    lower (keyword Generated.pegGrammar (input.length+20+extra) input) =
      .ok (some (sep::tail,[(name.chars,QuotedKeywords.Value.word word.chars)])) := by
  dsimp only
  rw [I1_word_keyword name word sep tail extra safeName safeValue blocked]
  simp [lower,Except.map,TokenLowering.arguments,List.filterMap,
    TokenLowering.I1_converted_keyword,MixedKeywords.abstract,MixedKeywords.abstractValue]

#print axioms I1_word_keyword
#print axioms I1_word_ast


theorem value_word_recognizer (value : WordRoundTrip.Word)
    (sep : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment value.chars = false)
    (blocked : WordRoundTrip.allowed sep = false) :
    let input := value.chars ++ sep :: tail
    PegModel.recognizeEnv Generated.pegGrammar []
      (input.length + extra + 10) (.ref "ArgValue" []) input =
        .ok (some (sep :: tail)) := by
  dsimp only
  have safeStart := safe
  have word := ArgumentsRoundTrip.canonical_word_before_separator value sep tail extra safeStart blocked
  cases chars : value.chars with
  | nil => exact False.elim (value.nonempty chars)
  | cons c rest =>
      have allowed : WordRoundTrip.allowed c = true := value.valid c (by simp [chars])
      have misses := WordRoundTrip.ordinary_value_precedence
        ((value.chars ++ sep :: tail).length + extra) c (rest ++ sep :: tail) allowed
      rcases misses with ⟨notString, notExpr, notReserved, notInline⟩
      have inputEq : value.chars ++ sep :: tail = c :: (rest ++ sep :: tail) := by
        simp [chars]
      rw [← inputEq] at notString notExpr notReserved notInline
      have fuelWord : (value.chars ++ sep :: tail).length + 8 + extra =
          ((value.chars ++ sep :: tail).length + extra + 7) + 1 := by omega
      have fuelMiss : (value.chars ++ sep :: tail).length + extra + 8 =
          ((value.chars ++ sep :: tail).length + extra + 7) + 1 := by omega
      rw [fuelWord] at word
      rw [fuelMiss] at notString notExpr notReserved notInline
      have result := ArgumentsRoundTrip.canonical_argvalue_word
        ((value.chars ++ sep :: tail).length + extra + 7)
        (value.chars ++ sep :: tail) (sep :: tail)
        notString notExpr notReserved notInline word
      have fuelResult : ((value.chars ++ sep :: tail).length + extra + 7) + 3 =
          (value.chars ++ sep :: tail).length + extra + 10 := by omega
      rw [fuelResult] at result
      simpa only [chars] using result


theorem I1_word_erasure (name word : WordRoundTrip.Word) (sep : Char) (tail : List Char)
    (extra : Nat) (safeName : WordRoundTrip.startsComment name.chars = false)
    (safeValue : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := name.chars ++ '='::(word.chars++sep::tail)
    let fuel := input.length+20+extra
    erase (keyword Generated.pegGrammar fuel input) =
      recognizeEnv Generated.pegGrammar [] fuel (.ref "KeywordArgument" []) input := by
  dsimp only
  rw [I1_word_keyword name word sep tail extra safeName safeValue blocked]
  let valueInput := word.chars ++ sep::tail
  let input := name.chars ++ '='::valueInput
  let fuel := input.length+17+extra
  have nameHit : recognizeEnv Generated.pegGrammar [] (fuel+1) (.ref "Word" []) input =
      .ok (some ('='::valueInput)) := by
    apply ArgumentsRoundTrip.canonical_word_at_budget name '=' valueInput (fuel+1) safeName (by decide)
    dsimp [fuel,input]
    omega
  have eqHit : recognizeEnv Generated.pegGrammar [] (fuel+1) (.ref "Eq" []) ('='::valueInput) =
      .ok (some valueInput) := by
    have hit := congrArg erase (CstWrapper.I1_generated_eq_token valueInput (input.length+15+extra) [])
    rw [project_erasure] at hit
    change recognizeEnv Generated.pegGrammar [] ((input.length+15+extra)+3)
      (.ref "Eq" []) ('='::valueInput) = .ok (some valueInput) at hit
    rw [show (input.length+15+extra)+3=fuel+1 by dsimp [fuel]; omega] at hit
    exact hit
  have valueHit : recognizeEnv Generated.pegGrammar [] (fuel+1) (.ref "ArgValue" []) valueInput =
      .ok (some (sep::tail)) := by
    have hit := value_word_recognizer word sep tail (name.chars.length+9+extra) safeValue blocked
    dsimp only at hit
    have same : (word.chars++sep::tail).length+(name.chars.length+9+extra)+10 = fuel+1 := by
      dsimp [fuel,input,valueInput]
      simp only [List.length_append,List.length_cons]
      omega
    rw [same] at hit
    exact hit
  have result := ArgumentsRoundTrip.canonical_keyword_of_parts fuel input ('='::valueInput)
    valueInput (sep::tail) nameHit eqHit valueHit
  change erase (.ok (some (sep::tail,[Element.node "KeywordArgument"
      (TokenLowering.rawFields (name,.word word))]))) =
    recognizeEnv Generated.pegGrammar [] (input.length+20+extra) (.ref "KeywordArgument" []) input
  rw [show input.length+20+extra=fuel+3 by dsimp [fuel]; omega]
  rw [result]
  rfl

#print axioms value_word_recognizer
#print axioms I1_word_erasure


def wordTokens (fields : List Element) : List (List Char) :=
  fields.filterMap fun field => match field with
    | .token "Word" chars => some chars
    | _ => none
def keywordQuoteCodes (fields : List Element) : List String :=
  ((wordTokens fields).drop 1).filterMap fun chars =>
    if WordRoundTrip.containsDoublePercent chars then some "G01102" else none
def quoteFlags (result : Result) : Except String (Option (List Char × List String)) :=
  result.map (fun answer => answer.map fun (rest,children) =>
    (rest,(children.map fun child => match child with
      | .node "KeywordArgument" fields => keywordQuoteCodes fields
      | _ => []).join))

theorem word_quote_codes (name word : WordRoundTrip.Word) :
    keywordQuoteCodes (TokenLowering.rawFields (name,.word word)) =
      if WordRoundTrip.containsDoublePercent word.chars then ["G01102"] else [] := by
  cases h : WordRoundTrip.containsDoublePercent word.chars <;>
    simp [keywordQuoteCodes,wordTokens,TokenLowering.rawFields,List.filterMap,List.drop,h]

theorem string_quote_codes (name : WordRoundTrip.Word) (parts : List StringRoundTrip.Part) :
    keywordQuoteCodes (TokenLowering.rawFields (name,.string parts)) = [] := by rfl

theorem I1_word_quote_codes (name word : WordRoundTrip.Word) (sep : Char) (tail : List Char)
    (extra : Nat) (safeName : WordRoundTrip.startsComment name.chars = false)
    (safeValue : WordRoundTrip.startsComment word.chars = false) (blocked : WordRoundTrip.allowed sep = false) :
    let input := name.chars ++ '='::(word.chars++sep::tail)
    quoteFlags (keyword Generated.pegGrammar (input.length+20+extra) input) =
      .ok (some (sep::tail,if WordRoundTrip.containsDoublePercent word.chars then ["G01102"] else [])) := by
  dsimp only
  rw [I1_word_keyword name word sep tail extra safeName safeValue blocked]
  simp [quoteFlags,Except.map,word_quote_codes]

theorem I1_quoted_quote_codes (name : WordRoundTrip.Word) (parts : List StringRoundTrip.Part)
    (suffix : List Char) (extra : Nat) (safe : WordRoundTrip.startsComment name.chars = false) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    let input := name.chars ++ '='::(front++suffix)
    quoteFlags (keyword Generated.pegGrammar (input.length+parts.length+16+extra) input) =
      .ok (some (suffix,[])) := by
  dsimp only
  rw [I1_quoted_keyword name parts suffix extra safe]
  simp [quoteFlags,Except.map,string_quote_codes]

#print axioms word_quote_codes
#print axioms string_quote_codes
#print axioms I1_word_quote_codes
#print axioms I1_quoted_quote_codes
end KeywordTrace
