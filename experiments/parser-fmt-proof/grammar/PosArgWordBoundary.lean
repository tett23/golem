import PosArgWord
open PegModel CstWrapper

example (word : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    let input := word.chars ++ ' ' :: tail
    PosArgTrace.read Generated.pegGrammar (input.length + 14 + extra) input =
      .ok (some (' ' :: tail, [Element.node "Argument" [Element.token "Word" word.chars]])) :=
  PosArgTrace.I1_word_capture_space word tail extra safe

example (word : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    let input := word.chars ++ ' ' :: tail
    ArgumentTrace.lower (PosArgTrace.read Generated.pegGrammar (input.length + 14 + extra) input) =
      .ok (some (' ' :: tail, [.positional (.word word.chars)])) :=
  PosArgTrace.I1_word_ast_space word tail extra safe

example (word : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    let input := word.chars ++ ' ' :: tail
    KeywordTrace.erase (PosArgTrace.read Generated.pegGrammar (input.length + 14 + extra) input) =
      recognizeEnv Generated.pegGrammar [] (input.length + 14 + extra) (.ref "PosArg" []) input :=
  PosArgTrace.I1_word_erasure_space word tail extra safe

#eval show IO Unit from do
  for (raw,tail) in [("cinder","tail"),("*","[7]"),("**","[7]"),("%","=value"),
      ("%x","%% note"),("cinder%%","next"),("星","続き"),("7.25","="),
      ("0",""),("-7","value"),("a/b","[7]"),("a.b","next")] do
    let input := (raw ++ " " ++ tail).toList
    let budget := input.length + 14
    let got := PosArgTrace.read Generated.pegGrammar budget input
    match got with
    | .ok (some (rest,[Element.node "Argument" [Element.token kind text]])) =>
      unless rest == (" "++tail).toList && kind == "Word" && text == raw.toList do
        throw (IO.userError s!"root ADR 0351: incorrect space-delimited word capture {repr got}")
    | _ => throw (IO.userError s!"root ADR 0351: missing space-delimited word capture {repr got}")
    match ArgumentTrace.lower got with
    | .ok (some (rest,[.positional (.word text)])) =>
      unless rest == (" "++tail).toList && text == raw.toList do
        throw (IO.userError "root ADR 0351: incorrect positional word AST")
    | _ => throw (IO.userError "root ADR 0351: missing positional word AST")
    match PegModel.recognizeEnv Generated.pegGrammar [] budget (.ref "PosArg" []) input with
    | .ok (some rest) => unless rest == (" "++tail).toList do
        throw (IO.userError "root ADR 0351: incorrect positional word erasure")
    | _ => throw (IO.userError "root ADR 0351: missing positional word erasure")
  IO.println "root ADR 0351: 12 space-delimited word captures, ASTs and recognizer results agree"
