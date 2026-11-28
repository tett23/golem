import KwArgTrace
open CstWrapper
#eval show IO Unit from do
  let got := KwArgTrace.read Generated.pegGrammar 512 "key=\"value\"@tail".toList
  match got with
  | .ok (some (rest,[Element.node "KeywordArgument"
      [Element.token "Word" name,Element.token "Eq" equals,Element.token "StringLit" raw]])) =>
    unless rest == "@tail".toList && name == "key".toList && equals == ['='] &&
        raw == "\"value\"".toList do throw (IO.userError s!"wrong KwArg capture {repr got}")
  | _ => throw (IO.userError s!"missing inline KwArg capture {repr got}")
  IO.println "inline KwArg kept its keyword node only"
