import KeywordTrace
#eval show IO Unit from do
  let got := KeywordTrace.quoteFlags
    (KeywordTrace.keyword Generated.pegGrammar 512 "key=a%%b]\n".toList)
  match got with
  | .ok (some (rest,["G01102"])) =>
    unless rest == "]\n".toList do throw (IO.userError "wrong diagnostic suffix")
  | _ => throw (IO.userError s!"missing modeled G01102 {repr got}")
  IO.println "modeled G01102 quote predicate matched"
