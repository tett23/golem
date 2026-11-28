import ArgumentEof
import PosArgTrace
namespace PosArgEof
open PegModel CstWrapper PosArgTrace
set_option autoImplicit false
private theorem bracket_miss (word : WordRoundTrip.Word) (c : Char)
    (member : c ∈ word.chars) : ('[' == c) = false := by
  have valid := word.valid c member
  cases equal : ('[' == c) with
  | false => rfl
  | true =>
    have same : '[' = c := eq_of_beq equal
    subst c
    contradiction

private theorem splat_prefixes_at_eof (word : WordRoundTrip.Word) :
    "*[".toList.isPrefixOf word.chars = false ∧
    "**[".toList.isPrefixOf word.chars = false := by
  cases chars : word.chars with
  | nil => exact False.elim (word.nonempty chars)
  | cons first rest =>
    cases rest with
    | nil => simp [List.isPrefixOf]
    | cons second rest =>
      have secondMiss := bracket_miss word second (by simp [chars])
      cases rest with
      | nil => simp [List.isPrefixOf,secondMiss]
      | cons third rest =>
        have thirdMiss := bracket_miss word third (by simp [chars])
        simp [List.isPrefixOf,secondMiss,thirdMiss]

private theorem keyword_misses_at_eof (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    recognizeEnv Generated.pegGrammar [] (word.chars.length+11+extra)
      (.choice [[.ref "Word" [],.ref "Eq" []]]) word.chars = .ok none := by
  let input := word.chars
  let n := input.length+extra
  have eqMiss : recognizeEnv Generated.pegGrammar [] (n+10)
      (.ref "Eq" []) [] = .ok none := by rfl
  have wordHit := WordEof.I1_word_at_eof word (extra+2) safe
  rw [show word.chars.length+8+(extra+2)=n+10 by dsimp [n,input]; omega] at wordHit
  have actual : recognizeEnv Generated.pegGrammar [] (n+11)
      (.choice [[.ref "Word" [],.ref "Eq" []]]) input = .ok none := by
    change runChoices (fun items => runSequence
      (fun scope item source => recognizeEnv Generated.pegGrammar scope (n+10) item source)
      _ [] items input) [[.ref "Word" [],.ref "Eq" []]] = _
    simp [runChoices,foldChoice,runSequence,wordHit,eqMiss,Except.map] <;> rfl
  rw [show word.chars.length+11+extra=n+11 by dsimp [n,input]; omega]
  exact actual

private theorem literal_miss (fuel : Nat) (value written : String) (input : List Char)
    (miss : value.toList.isPrefixOf input = false) :
    recognizeEnv Generated.pegGrammar [] (fuel + 1) (.lit value written) input = .ok none := by
  simp [recognizeEnv, miss]; rfl

private theorem negative_miss (fuel : Nat) (child : Expr) (input : List Char)
    (miss : recognizeEnv Generated.pegGrammar [] fuel child input = .ok none) :
    recognizeEnv Generated.pegGrammar [] (fuel + 1) (.notPred child) input = .ok (some input) := by
  change (match recognizeEnv Generated.pegGrammar [] fuel child input with
    | .error reason => if isLabelFailure reason then Except.ok (some input) else Except.error reason
    | .ok none => Except.ok (some input)
    | .ok (some _) => Except.ok none) = Except.ok (some input)
  rw [miss]

private theorem splat_miss (word : WordRoundTrip.Word) (fuel : Nat)
 :
    recognizeEnv Generated.pegGrammar [] (fuel + 3) (.ref "Splat" [])
      (word.chars) = .ok none := by
  have prefixes := splat_prefixes_at_eof word
  have first := literal_miss fuel "**[" "'**['" _ prefixes.2
  have second := literal_miss fuel "*[" "'*['" _ prefixes.1
  change runChoices (fun items => runSequence
    (fun scope item source => recognizeEnv Generated.pegGrammar scope (fuel+1) item source)
    _ [] items (word.chars)) [[.lit "**[" "'**['"], [.lit "*[" "'*['"]] = _
  simp [runChoices,foldChoice,runSequence,first,second,Except.map] <;> rfl

private theorem word_guards (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
 :
    let input := word.chars
    let budget := input.length+12+extra
    recognizeEnv Generated.pegGrammar [] budget noComment input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget noKeyword input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget noDoubleSplat input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget noSplat input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget (.ref "SplatArgument" []) input = .ok none := by
  dsimp only
  let input := word.chars
  let n := input.length+extra
  have commentPrefix := WordRoundTrip.safe_comment_prefixes input (safe)
  have splatPrefix := splat_prefixes_at_eof word
  have comment := literal_miss (n+10) "%%" "'%%'" input commentPrefix.1
  have double := literal_miss (n+10) "**[" "'**['" input splatPrefix.2
  have splat := splat_miss word (n+8)
  have keywordMiss := keyword_misses_at_eof word extra safe
  rw [show (word.chars).length+11+extra = n+11 by dsimp [n,input]; omega] at keywordMiss
  have argumentMiss : recognizeEnv Generated.pegGrammar [] (n+12) (.ref "SplatArgument" []) input = .ok none := by
    change runChoices (fun items => runSequence
      (fun scope item source => recognizeEnv Generated.pegGrammar scope (n+10) item source)
      _ [] items input) [[.ref "Splat" [], .ref "ExprBody" [], .label (.choice [[.ref "RBr" []]]) "close"]] = _
    simp only [runChoices,foldChoice,List.foldlM]
    rw [PegModelTest.sequence_head_miss _ _ [] (.ref "Splat" []) _ input
      (splat_miss word (n+7))]
    rfl
  have budget : (word.chars).length+12+extra = n+12 := by dsimp [n,input]; omega
  rw [budget]
  exact ⟨negative_miss (n+11) _ _ comment,negative_miss (n+11) _ _ keywordMiss,
    negative_miss (n+11) _ _ double,negative_miss (n+11) _ _ splat,argumentMiss⟩

theorem I1_capture (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
 :
    let input := word.chars
    read Generated.pegGrammar (input.length+14+extra) input =
      .ok (some ([],[Element.node "Argument" [Element.token "Word" word.chars]])) := by
  dsimp only
  let input := word.chars
  let budget := input.length+12+extra
  let reader : KeywordTrace.Reader := fun name args source =>
    if name == "Argument" && args.isEmpty then ArgumentTrace.read Generated.pegGrammar budget source
    else KeywordTrace.leaf Generated.pegGrammar budget name args source
  have guards := word_guards word extra safe
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
      .ok (some ([],[Element.node "Argument" [Element.token "Word" word.chars]])) := by
    change ArgumentTrace.read Generated.pegGrammar budget input = _
    exact ArgumentEof.I1_capture word extra safe
  unfold PosArgTrace.read
  rw [if_neg (by omega),posarg_found]
  change KeywordTrace.finish Generated.pegGrammar "PosArg" input
    (choices Generated.pegGrammar (input.length+14+extra-2) _ branches input) = _
  rw [show input.length+14+extra-2 = budget by dsimp [budget]; omega]
  change KeywordTrace.finish Generated.pegGrammar "PosArg" input
    (choices Generated.pegGrammar budget reader branches input) = _
  simp [branches,choices,sequence,expression,noComment,noKeyword,noDoubleSplat,noSplat,comment,keyword,doubleSplat,splat,missing,argument,
    KeywordTrace.finish,Except.map,CstWrapper.wrap,posarg_inline]

theorem I1_ast (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
 :
    let input := word.chars
    ArgumentTrace.lower (read Generated.pegGrammar (input.length+14+extra) input) =
      .ok (some ([],[.positional (.word word.chars)])) := by
  dsimp only
  rw [I1_capture word extra safe]
  rfl

private theorem word_recognizer (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
 :
    let input := word.chars
    recognizeEnv Generated.pegGrammar [] (input.length+14+extra) (.ref "PosArg" []) input =
      .ok (some ([])) := by
  dsimp only
  let input := word.chars
  let budget := input.length+12+extra
  have guards := word_guards word extra safe
  rcases guards with ⟨comment,keyword,doubleSplat,splat,notSplat⟩
  change recognizeEnv Generated.pegGrammar [] budget noComment input = .ok (some input) at comment
  change recognizeEnv Generated.pegGrammar [] budget noKeyword input = .ok (some input) at keyword
  change recognizeEnv Generated.pegGrammar [] budget noDoubleSplat input = .ok (some input) at doubleSplat
  change recognizeEnv Generated.pegGrammar [] budget noSplat input = .ok (some input) at splat
  change recognizeEnv Generated.pegGrammar [] budget (.ref "SplatArgument" []) input = .ok none at notSplat
  dsimp only [noComment,noKeyword,noDoubleSplat,noSplat] at comment keyword doubleSplat splat
  have argument : recognizeEnv Generated.pegGrammar [] budget (.ref "Argument" []) input = .ok (some ([])) := by
    have projected := ArgumentEof.I1_erasure word extra safe
    rw [ArgumentEof.I1_capture word extra safe] at projected
    simpa only [KeywordTrace.erase,Except.map,Option.map] using projected.symm
  rw [show input.length+14+extra = budget+2 by dsimp [budget]; omega]
  conv => lhs; unfold recognizeEnv; dsimp only; rw [posarg_found]
  change runChoices (fun items => runSequence
    (fun scope item source => recognizeEnv Generated.pegGrammar scope budget item source)
    _ [] items input) branches = _
  simp [branches,noComment,noKeyword,noDoubleSplat,noSplat,runChoices,foldChoice,runSequence,
    comment,keyword,doubleSplat,splat,notSplat,argument,Except.map] <;> rfl

theorem I1_erasure (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
 :
    let input := word.chars
    KeywordTrace.erase (read Generated.pegGrammar (input.length+14+extra) input) =
      recognizeEnv Generated.pegGrammar [] (input.length+14+extra) (.ref "PosArg" []) input := by
  dsimp only
  rw [I1_capture word extra safe]
  simpa only [KeywordTrace.erase,Except.map,Option.map] using (word_recognizer word extra safe).symm

#print axioms I1_capture
#print axioms I1_ast
#print axioms I1_erasure
end PosArgEof
