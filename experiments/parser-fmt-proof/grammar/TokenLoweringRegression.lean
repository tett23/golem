import TokenLowering
#eval show IO Unit from do
  let got := TokenLowering.read Generated.pegGrammar "StringLit" 100 "\"a\\\"b\"@tail".toList []
  match got with
  | .ok (some (rest,some (QuotedKeywords.Value.string chars))) =>
    unless rest == "@tail".toList && chars == "a\"b".toList do
      throw (IO.userError s!"wrong decoded value {repr got}")
  | _ => throw (IO.userError s!"wrong decoded kind {repr got}")
  IO.println "raw token to AST decoded string matched"
