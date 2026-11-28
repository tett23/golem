import PosArgEof
set_option autoImplicit false
example (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    PegModel.recognizeEnv Generated.pegGrammar [] (word.chars.length+8+extra)
      (.ref "Word" []) word.chars = .ok (some []) :=
  WordEof.I1_word_at_eof word extra safe
example (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    ArgumentTrace.read Generated.pegGrammar (word.chars.length+12+extra) word.chars =
      .ok (some ([],[CstWrapper.Element.node "Argument" [CstWrapper.Element.token "Word" word.chars]])) :=
  ArgumentEof.I1_capture word extra safe
example (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    ArgumentTrace.lower (ArgumentTrace.read Generated.pegGrammar (word.chars.length+12+extra) word.chars) =
      .ok (some ([],[.positional (.word word.chars)])) :=
  ArgumentEof.I1_ast word extra safe
example (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    KeywordTrace.erase (ArgumentTrace.read Generated.pegGrammar (word.chars.length+12+extra) word.chars) =
      PegModel.recognizeEnv Generated.pegGrammar [] (word.chars.length+12+extra) (.ref "Argument" []) word.chars :=
  ArgumentEof.I1_erasure word extra safe

example (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    PosArgTrace.read Generated.pegGrammar (word.chars.length+14+extra) word.chars =
      .ok (some ([],[CstWrapper.Element.node "Argument" [CstWrapper.Element.token "Word" word.chars]])) :=
  PosArgEof.I1_capture word extra safe
example (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    ArgumentTrace.lower (PosArgTrace.read Generated.pegGrammar (word.chars.length+14+extra) word.chars) =
      .ok (some ([],[.positional (.word word.chars)])) :=
  PosArgEof.I1_ast word extra safe
example (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    KeywordTrace.erase (PosArgTrace.read Generated.pegGrammar (word.chars.length+14+extra) word.chars) =
      PegModel.recognizeEnv Generated.pegGrammar [] (word.chars.length+14+extra) (.ref "PosArg" []) word.chars :=
  PosArgEof.I1_erasure word extra safe

#eval show IO Unit from do
  let words : List String := ["cinder","*","**","***","7.25","星","cinder%%","%","*cinder","-",".","a,b"]
  for word in words do
    unless !word.isEmpty && word.toList.all WordRoundTrip.allowed && !WordRoundTrip.startsComment word.toList do
      throw (IO.userError "invalid EOF positional fixture")
    let input := word.toList
    let got := PosArgTrace.read Generated.pegGrammar (input.length+14) input
    match got with
    | .ok (some ([],[CstWrapper.Element.node "Argument" [CstWrapper.Element.token "Word" raw]])) =>
      unless raw == input do throw (IO.userError "different EOF positional capture")
    | other => throw (IO.userError s!"missing EOF positional capture {repr other}")
    match ArgumentTrace.lower got with
    | .ok (some ([],[.positional (.word raw)])) =>
      unless raw == input do throw (IO.userError "different EOF positional AST")
    | other => throw (IO.userError s!"missing EOF positional AST {repr other}")
    match PegModel.recognizeEnv Generated.pegGrammar [] (input.length+14) (.ref "PosArg" []) input with
    | .ok (some []) => pure ()
    | other => throw (IO.userError s!"different EOF positional recognizer {repr other}")
  for text in ["","%%","%%=discard"] do
    match PosArgTrace.read Generated.pegGrammar 512 text.toList with
    | .ok none => pure ()
    | other => throw (IO.userError s!"accepted excluded EOF input {repr other}")
  IO.println "12 PosArg EOF captures, ASTs and recognizers agree"
