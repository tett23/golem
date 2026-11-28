import KeywordTrace
#eval show IO Unit from do
  let input := "key=\"a\\\"b\"@tail".toList
  let got := KeywordTrace.keyword Generated.pegGrammar 512 input
  match got with
  | .ok (some (rest,[CstWrapper.Element.node "KeywordArgument"
      [CstWrapper.Element.token "Word" name,CstWrapper.Element.token "Eq" equals,
       CstWrapper.Element.token "StringLit" raw]])) =>
    unless rest == "@tail".toList && name == "key".toList && equals == ['='] &&
        raw == "\"a\\\"b\"".toList do
      throw (IO.userError s!"wrong traced CST {repr got}")
  | _ => throw (IO.userError s!"missing traced CST children {repr got}")
  let result := KeywordTrace.lower got
  match result with
  | .ok (some (rest,[(name,QuotedKeywords.Value.string chars)])) =>
    unless rest == "@tail".toList && name == "key".toList && chars == "a\"b".toList do
      throw (IO.userError s!"wrong traced AST {repr result}")
  | _ => throw (IO.userError s!"missing traced AST {repr result}")
  IO.println "generated keyword CST and decoded AST matched"
