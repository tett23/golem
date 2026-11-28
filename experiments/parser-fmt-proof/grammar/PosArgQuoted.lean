import PosArgTrace
namespace PosArgTrace
open PegModel CstWrapper

private theorem quoted_guards (fuel : Nat) (tail : List Char) :
    recognizeEnv Generated.pegGrammar [] (fuel+11) noComment ('"'::tail) = .ok (some ('"'::tail)) ∧
    recognizeEnv Generated.pegGrammar [] (fuel+11) noKeyword ('"'::tail) = .ok (some ('"'::tail)) ∧
    recognizeEnv Generated.pegGrammar [] (fuel+11) noDoubleSplat ('"'::tail) = .ok (some ('"'::tail)) ∧
    recognizeEnv Generated.pegGrammar [] (fuel+11) noSplat ('"'::tail) = .ok (some ('"'::tail)) ∧
    recognizeEnv Generated.pegGrammar [] (fuel+11) (.ref "SplatArgument" []) ('"'::tail) = .ok none := by
  exact ⟨rfl,rfl,rfl,rfl,rfl⟩

theorem I1_quoted_capture (parts : List StringRoundTrip.Part) (suffix : List Char) (extra : Nat) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    read Generated.pegGrammar (parts.length+13+extra) (front++suffix) =
      .ok (some (suffix,[Element.node "Argument" [Element.token "StringLit" front]])) := by
  dsimp only
  simp only [List.cons_append,List.append_assoc,List.singleton_append]
  let input := '"'::(StringRoundTrip.spell parts ++ '"'::suffix)
  let budget := parts.length+11+extra
  let reader : KeywordTrace.Reader := fun name args source =>
    if name == "Argument" && args.isEmpty then ArgumentTrace.read Generated.pegGrammar budget source
    else KeywordTrace.leaf Generated.pegGrammar budget name args source
  have guards := quoted_guards (parts.length+extra) (StringRoundTrip.spell parts ++ '"'::suffix)
  rw [show parts.length+extra+11 = budget by dsimp [budget]; omega] at guards
  rcases guards with ⟨comment,keyword,doubleSplat,splat,notSplat⟩
  change recognizeEnv Generated.pegGrammar [] budget noComment input = .ok (some input) at comment
  change recognizeEnv Generated.pegGrammar [] budget noKeyword input = .ok (some input) at keyword
  change recognizeEnv Generated.pegGrammar [] budget noDoubleSplat input = .ok (some input) at doubleSplat
  change recognizeEnv Generated.pegGrammar [] budget noSplat input = .ok (some input) at splat
  dsimp only [noComment,noKeyword,noDoubleSplat,noSplat] at comment keyword doubleSplat splat
  have missing : reader "SplatArgument" [] input = .ok none := by
    change KeywordTrace.leaf Generated.pegGrammar budget "SplatArgument" [] input = _
    change recognizeEnv Generated.pegGrammar [] budget (.ref "SplatArgument" []) input = .ok none at notSplat
    unfold KeywordTrace.leaf
    rw [notSplat]
  have argument : reader "Argument" [] input =
      .ok (some (suffix,[Element.node "Argument" [Element.token "StringLit"
        ('"'::(StringRoundTrip.spell parts ++ ['"']))]])) := by
    change ArgumentTrace.read Generated.pegGrammar budget input = _
    simpa only [List.cons_append,List.append_assoc,List.singleton_append] using
      ArgumentTrace.I1_quoted_capture parts suffix extra
  unfold read
  rw [if_neg (by omega),posarg_found]
  change KeywordTrace.finish Generated.pegGrammar "PosArg" input
    (choices Generated.pegGrammar (parts.length+13+extra-2) _ branches input) = _
  rw [show parts.length+13+extra-2 = budget by dsimp [budget]; omega]
  change KeywordTrace.finish Generated.pegGrammar "PosArg" input
    (choices Generated.pegGrammar budget reader branches input) = _
  simp [branches,choices,sequence,expression,noComment,noKeyword,noDoubleSplat,noSplat,comment,keyword,doubleSplat,splat,missing,argument,
    KeywordTrace.finish,Except.map,CstWrapper.wrap,posarg_inline]

theorem I1_quoted_ast (parts : List StringRoundTrip.Part) (suffix : List Char) (extra : Nat) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    ArgumentTrace.lower (read Generated.pegGrammar (parts.length+13+extra) (front++suffix)) =
      .ok (some (suffix,[.positional (.string (parts.map StringRoundTrip.partValue))])) := by
  dsimp only
  rw [I1_quoted_capture parts suffix extra]
  change (Except.ok (some (suffix,[ArgumentTrace.Argument.positional (.string (KeywordLowering.unquote
    ('"'::(StringRoundTrip.spell parts ++ ['"']))))])) :
      Except String (Option (List Char × List ArgumentTrace.Argument))) = _
  have decoded := KeywordLowering.unquote_spelling parts
  simp only [MixedKeywords.spelling] at decoded
  rw [decoded]

private theorem quoted_recognizer (parts : List StringRoundTrip.Part) (suffix : List Char) (extra : Nat) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    recognizeEnv Generated.pegGrammar [] (parts.length+13+extra) (.ref "PosArg" []) (front++suffix) =
      .ok (some suffix) := by
  dsimp only
  simp only [List.cons_append,List.append_assoc,List.singleton_append]
  let input := '"'::(StringRoundTrip.spell parts ++ '"'::suffix)
  let budget := parts.length+11+extra
  have guards := quoted_guards (parts.length+extra) (StringRoundTrip.spell parts ++ '"'::suffix)
  rw [show parts.length+extra+11 = budget by dsimp [budget]; omega] at guards
  rcases guards with ⟨comment,keyword,doubleSplat,splat,notSplat⟩
  change recognizeEnv Generated.pegGrammar [] budget noComment input = .ok (some input) at comment
  change recognizeEnv Generated.pegGrammar [] budget noKeyword input = .ok (some input) at keyword
  change recognizeEnv Generated.pegGrammar [] budget noDoubleSplat input = .ok (some input) at doubleSplat
  change recognizeEnv Generated.pegGrammar [] budget noSplat input = .ok (some input) at splat
  change recognizeEnv Generated.pegGrammar [] budget (.ref "SplatArgument" []) input = .ok none at notSplat
  dsimp only [noComment,noKeyword,noDoubleSplat,noSplat] at comment keyword doubleSplat splat
  have argument : recognizeEnv Generated.pegGrammar [] budget (.ref "Argument" []) input = .ok (some suffix) := by
    have projected := ArgumentTrace.I1_quoted_erasure parts suffix extra
    dsimp only at projected
    rw [ArgumentTrace.I1_quoted_capture parts suffix extra] at projected
    simpa only [KeywordTrace.erase,Except.map,Option.map,List.cons_append,List.append_assoc,List.singleton_append]
      using projected.symm
  rw [show parts.length+13+extra = budget+2 by dsimp [budget]; omega]
  conv => lhs; unfold recognizeEnv; dsimp only; rw [posarg_found]
  change runChoices (fun items => runSequence
    (fun scope item source => recognizeEnv Generated.pegGrammar scope budget item source)
    _ [] items input) branches = _
  simp [branches,noComment,noKeyword,noDoubleSplat,noSplat,runChoices,foldChoice,runSequence,
    comment,keyword,doubleSplat,splat,notSplat,argument,Except.map] <;> rfl

theorem I1_quoted_erasure (parts : List StringRoundTrip.Part) (suffix : List Char) (extra : Nat) :
    let front := '"'::(StringRoundTrip.spell parts ++ ['"'])
    KeywordTrace.erase (read Generated.pegGrammar (parts.length+13+extra) (front++suffix)) =
      recognizeEnv Generated.pegGrammar [] (parts.length+13+extra) (.ref "PosArg" []) (front++suffix) := by
  dsimp only
  rw [I1_quoted_capture parts suffix extra]
  simpa only [KeywordTrace.erase,Except.map,Option.map] using (quoted_recognizer parts suffix extra).symm

#print axioms I1_quoted_capture
#print axioms I1_quoted_ast
#print axioms I1_quoted_erasure
end PosArgTrace
