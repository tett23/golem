import QuotedKeywords
#eval show IO Unit from do
  let source := " path=\"a\\\"b\"\n".toList
  let got := QuotedKeywords.parseArgs 1 source
  match got with
  | some [(name,.string value)] =>
      unless name == "path".toList && value == "a\"b".toList do
        throw (IO.userError s!"I1/I2 quoted keyword value mismatch: {repr got}")
  | _ => throw (IO.userError s!"I1/I2 quoted keyword missing: {repr got}")
  IO.println "I1/I2 quoted keyword exact name, kind and decoded value matched"
