import PosArgDelimited
open WordRoundTrip PegModel CstWrapper PosArgTrace
set_option autoImplicit false
example (word : Word) (tail : List Char) (extra : Nat)
    (safe : startsComment word.chars = false)
    (single : word.chars ≠ ['*']) (double : word.chars ≠ ['*','*']) :
    let input := word.chars ++ '[' :: tail
    read Generated.pegGrammar (input.length+14+extra) input =
      .ok (some ('[' :: tail,[Element.node "Argument" [Element.token "Word" word.chars]])) :=
  PosArgDelimited.I1_bracket_capture word tail extra safe single double
example (word : Word) (tail : List Char) (extra : Nat)
    (safe : startsComment word.chars = false)
    (single : word.chars ≠ ['*']) (double : word.chars ≠ ['*','*']) :
    let input := word.chars ++ '[' :: tail
    ArgumentTrace.lower (read Generated.pegGrammar (input.length+14+extra) input) =
      .ok (some ('['::tail,[.positional (.word word.chars)])) :=
  PosArgDelimited.I1_bracket_ast word tail extra safe single double
example (word : Word) (tail : List Char) (extra : Nat)
    (safe : startsComment word.chars = false)
    (single : word.chars ≠ ['*']) (double : word.chars ≠ ['*','*']) :
    let input := word.chars ++ '[' :: tail
    KeywordTrace.erase (read Generated.pegGrammar (input.length+14+extra) input) =
      recognizeEnv Generated.pegGrammar [] (input.length+14+extra) (.ref "PosArg" []) input :=
  PosArgDelimited.I1_bracket_erasure word tail extra safe single double

example : "*[".toList.isPrefixOf (['*'] ++ "[7]".toList) = true := by decide
example : "**[".toList.isPrefixOf (['*','*'] ++ "[7]".toList) = true := by decide
example : "*[".toList.isPrefixOf ("***".toList ++ "[7]".toList) = false := by decide
example : "**[".toList.isPrefixOf ("***".toList ++ "[7]".toList) = false := by decide

#eval show IO Unit from do
  let words : List String := ["cinder","***","星","7.25","cinder%%"]
  let suffixes : List String := ["[","[7]","[tail]"]
  for word in words do
    unless !word.isEmpty && word.toList.all WordRoundTrip.allowed &&
        !WordRoundTrip.startsComment word.toList && word != "*" && word != "**" do
      throw (IO.userError "invalid bracket word fixture")
    for rest in suffixes do
      let input := (word ++ rest).toList
      let budget := input.length+14
      let got := PosArgTrace.read Generated.pegGrammar budget input
      match got with
      | .ok (some (suffix,[Element.node "Argument" [Element.token "Word" raw]])) =>
        unless suffix == rest.toList && raw == word.toList do
          throw (IO.userError "wrong bracket word capture")
      | _ => throw (IO.userError s!"missing bracket word capture {repr got}")
      match ArgumentTrace.lower got with
      | .ok (some (suffix,[.positional (.word raw)])) =>
        unless suffix == rest.toList && raw == word.toList do
          throw (IO.userError "wrong bracket word AST")
      | _ => throw (IO.userError "missing bracket word AST")
      match PegModel.recognizeEnv Generated.pegGrammar [] budget (.ref "PosArg" []) input with
      | .ok (some suffix) => unless suffix == rest.toList do throw (IO.userError "wrong bracket word erasure")
      | _ => throw (IO.userError "missing bracket word erasure")
  match PosArgTrace.read Generated.pegGrammar 512 "*[7]".toList with
  | .error "unmodeled non-token capture" => pure ()
  | other => throw (IO.userError s!"lost bracket splat scope {repr other}")
  match PosArgTrace.read Generated.pegGrammar 512 "**[7]".toList with
  | .ok none => pure ()
  | other => throw (IO.userError s!"lost bracket double-splat scope {repr other}")
  IO.println "root ADR 0351: 15 bracket word captures, ASTs and recognizers agree; 2 splat limits retained"
