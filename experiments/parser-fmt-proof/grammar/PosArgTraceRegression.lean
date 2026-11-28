import PosArgTrace
open PegModel CstWrapper
#eval show IO Unit from do
  for (raw,value) in [("\"value\"","value"),("\"\"",""),("\"a\\\"b\"","a\"b"),
      ("\"%%= note\"","%%= note"),("\"👩‍👩‍👧‍👦\"","👩‍👩‍👧‍👦")] do
    let input := (raw ++ "]\n").toList
    let got := PosArgTrace.read Generated.pegGrammar 512 input
    match got with
    | .ok (some (rest,[Element.node "Argument" [Element.token "StringLit" actualRaw]])) =>
      unless rest == [']','\n'] && actualRaw == raw.toList do
        throw (IO.userError s!"wrong guarded positional capture {repr got}")
    | _ => throw (IO.userError s!"missing guarded positional capture {repr got}")
    match KeywordTrace.erase got, recognizeEnv Generated.pegGrammar [] 512 (.ref "PosArg" []) input with
    | .ok (some projected), .ok (some actual) =>
      unless projected == actual do
        throw (IO.userError "guarded positional erasure disagrees with actual recognition")
    | _, _ => throw (IO.userError "guarded positional recognition failed")
    match ArgumentTrace.lower got with
    | .ok (some (rest,[.positional (.string decoded)])) =>
      unless rest == [']','\n'] && decoded == value.toList do
        throw (IO.userError "guarded positional lowering changed the value")
    | _ => throw (IO.userError "missing guarded positional lowering")
  for rejected in ["key=value", "%% note", "**[1]"] do
    match PosArgTrace.read Generated.pegGrammar 512 rejected.toList with
    | .ok none => pure ()
    | got => throw (IO.userError s!"guarded positional accepted a non-positional prefix {repr got}")
  match PosArgTrace.read Generated.pegGrammar 512 "*[1]".toList with
  | .error "unmodeled non-token capture" => pure ()
  | got => throw (IO.userError s!"splat capture scope changed {repr got}")
  IO.println "guarded positional quoted captures and values agree; guards and splat scope retained"
