import PosArgDelimited
open PegModel CstWrapper
example (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') (notBracket : separator ≠ '[') :
    let input := word.chars ++ separator::tail
    PosArgTrace.read Generated.pegGrammar (input.length+14+extra) input =
      .ok (some (separator::tail,[Element.node "Argument" [Element.token "Word" word.chars]])) :=
  PosArgDelimited.I1_delimited_capture word separator tail extra safe blocked notEq notBracket
example (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') (notBracket : separator ≠ '[') :
    let input := word.chars ++ separator::tail
    ArgumentTrace.lower (PosArgTrace.read Generated.pegGrammar (input.length+14+extra) input) =
      .ok (some (separator::tail,[.positional (.word word.chars)])) :=
  PosArgDelimited.I1_delimited_ast word separator tail extra safe blocked notEq notBracket
example (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') (notBracket : separator ≠ '[') :
    let input := word.chars ++ separator::tail
    KeywordTrace.erase (PosArgTrace.read Generated.pegGrammar (input.length+14+extra) input) =
      recognizeEnv Generated.pegGrammar [] (input.length+14+extra) (.ref "PosArg" []) input :=
  PosArgDelimited.I1_delimited_erasure word separator tail extra safe blocked notEq notBracket

#eval show IO Unit from do
  let words : List String := ["cinder","*","**","星","7.25","cinder%%"]
  let separators : List Char := [' ', '\t', '\n', ']', ':', '|', '"', '\\']
  for word in words do
    unless !word.isEmpty && word.toList.all WordRoundTrip.allowed &&
        !WordRoundTrip.startsComment word.toList do
      throw (IO.userError "invalid delimited-word fixture")
    for separator in separators do
      unless !WordRoundTrip.allowed separator && separator != '=' && separator != '[' do
        throw (IO.userError "invalid delimited-word separator")
      let rest := separator :: "tail]".toList
      let input := word.toList ++ rest
      let budget := input.length+14
      let got := PosArgTrace.read Generated.pegGrammar budget input
      match got with
      | .ok (some (suffix,[Element.node "Argument" [Element.token "Word" raw]])) =>
        unless suffix == rest && raw == word.toList do
          throw (IO.userError "wrong delimited word capture")
      | _ => throw (IO.userError s!"missing delimited word capture {repr got}")
      match ArgumentTrace.lower got with
      | .ok (some (suffix,[.positional (.word raw)])) =>
        unless suffix == rest && raw == word.toList do
          throw (IO.userError "wrong delimited word AST")
      | _ => throw (IO.userError "missing delimited word AST")
      match PegModel.recognizeEnv Generated.pegGrammar [] budget (.ref "PosArg" []) input with
      | .ok (some suffix) => unless suffix == rest do throw (IO.userError "wrong delimited word erasure")
      | _ => throw (IO.userError "missing delimited word erasure")
  for input in ["cinder=7","**[7]"] do
    match PosArgTrace.read Generated.pegGrammar 512 input.toList with
    | .ok none => pure ()
    | other => throw (IO.userError s!"accepted excluded keyword/double-splat {repr other}")
  match PosArgTrace.read Generated.pegGrammar 512 "*[7]".toList with
  | .error "unmodeled non-token capture" => pure ()
  | other => throw (IO.userError s!"lost excluded splat scope {repr other}")
  match PosArgTrace.read Generated.pegGrammar 512 "cinder[7]".toList with
  | .ok (some (suffix,[Element.node "Argument" [Element.token "Word" raw]])) =>
    unless suffix == "[7]".toList && raw == "cinder".toList do
      throw (IO.userError "wrong longer-word bracket scope")
  | other => throw (IO.userError s!"lost longer-word bracket scope {repr other}")
  IO.println "root ADR 0351: 48 delimited word captures, ASTs and recognizers agree; 4 lexical limits retained"
