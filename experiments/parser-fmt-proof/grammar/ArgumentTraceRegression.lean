import ArgumentTrace
open CstWrapper
#eval show IO Unit from do
  for (input,suffix,raw,kind) in
      [("\"value\"@tail","@tail","\"value\"","StringLit"),
       ("word tail"," tail","word","Word")] do
    let got := ArgumentTrace.read Generated.pegGrammar 512 input.toList
    match got with
    | .ok (some (rest,[Element.node "Argument" [Element.token actualKind actualRaw]])) =>
      unless rest == suffix.toList && actualKind == kind && actualRaw == raw.toList do
        throw (IO.userError s!"root ADR 0351 I1: wrong positional argument capture {repr got}")
    | _ => throw (IO.userError s!"root ADR 0351 I1: missing positional argument capture {repr got}")
  let got := ArgumentTrace.lower (ArgumentTrace.read Generated.pegGrammar 512 "\"value\"@tail".toList)
  match got with
  | .ok (some (rest,[.positional (.string value)])) =>
    unless rest == "@tail".toList && value == "value".toList do
      throw (IO.userError s!"root ADR 0351 I1, I2: wrong positional argument lowering {repr got}")
  | _ => throw (IO.userError s!"root ADR 0351 I1, I2: missing positional argument lowering {repr got}")
  IO.println "root ADR 0351 I1, I2: positional word and quoted captures retain their node and kind"
