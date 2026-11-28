import CstWrapper
open CstWrapper
#eval show IO Unit from do
  let input := "\"a\\\"b\"@tail".toList
  let got := project Generated.pegGrammar "StringLit" 100 input [.node "ignored inner child" []]
  match got with
  | .ok (some (rest,[.token name chars])) =>
    unless rest == "@tail".toList && name == "StringLit" && chars == "\"a\\\"b\"".toList do
      throw (IO.userError s!"raw CST token mismatch: {repr got}")
  | _ => throw (IO.userError s!"missing raw CST token: {repr got}")
  IO.println "raw CST quoted spelling matched"
