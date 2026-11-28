import PosArgTrace
namespace PosArgTrace
open PegModel CstWrapper

private theorem space_safe (word : WordRoundTrip.Word) (tail : List Char)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    WordRoundTrip.startsComment (word.chars ++ ' ' :: tail) = false := by
  cases chars : word.chars with
  | nil => exact False.elim (word.nonempty chars)
  | cons first rest =>
    cases rest with
    | nil => simp [List.append, WordRoundTrip.startsComment]
    | cons second rest =>
      by_cases firstEq : first = '%'
      <;> by_cases secondEq : second = '%'
      <;> simp_all [WordRoundTrip.startsComment]

private theorem bracket_miss (word : WordRoundTrip.Word) (c : Char)
    (member : c ∈ word.chars) : ('[' == c) = false := by
  have valid := word.valid c member
  cases eq : ('[' == c) with
  | false => rfl
  | true =>
    have same : '[' = c := eq_of_beq eq
    subst c
    contradiction

private theorem splat_prefixes_miss (word : WordRoundTrip.Word) (tail : List Char) :
    "*[".toList.isPrefixOf (word.chars ++ ' ' :: tail) = false ∧
    "**[".toList.isPrefixOf (word.chars ++ ' ' :: tail) = false := by
  cases chars : word.chars with
  | nil => exact False.elim (word.nonempty chars)
  | cons first rest =>
    cases rest with
    | nil => simp [List.append, List.isPrefixOf]
    | cons second rest =>
      have secondMiss := bracket_miss word second (by simp [chars])
      cases rest with
      | nil => simp [List.append, List.isPrefixOf, secondMiss]
      | cons third rest =>
        have thirdMiss := bracket_miss word third (by simp [chars])
        simp [List.append, List.isPrefixOf, secondMiss, thirdMiss]

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

private theorem splat_miss (word : WordRoundTrip.Word) (tail : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar [] (fuel + 3) (.ref "Splat" [])
      (word.chars ++ ' ' :: tail) = .ok none := by
  have prefixes := splat_prefixes_miss word tail
  have first := literal_miss fuel "**[" "'**['" _ prefixes.2
  have second := literal_miss fuel "*[" "'*['" _ prefixes.1
  change runChoices (fun items => runSequence
    (fun scope item source => recognizeEnv Generated.pegGrammar scope (fuel+1) item source)
    _ [] items (word.chars ++ ' ' :: tail)) [[.lit "**[" "'**['"], [.lit "*[" "'*['"]] = _
  simp [runChoices,foldChoice,runSequence,first,second,Except.map] <;> rfl

private theorem word_guards (word : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    let input := word.chars ++ ' ' :: tail
    let budget := input.length+12+extra
    recognizeEnv Generated.pegGrammar [] budget noComment input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget noKeyword input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget noDoubleSplat input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget noSplat input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget (.ref "SplatArgument" []) input = .ok none := by
  dsimp only
  let input := word.chars ++ ' ' :: tail
  let n := input.length+extra
  have commentPrefix := WordRoundTrip.safe_comment_prefixes input (space_safe word tail safe)
  have splatPrefix := splat_prefixes_miss word tail
  have comment := literal_miss (n+10) "%%" "'%%'" input commentPrefix.1
  have double := literal_miss (n+10) "**[" "'**['" input splatPrefix.2
  have splat := splat_miss word tail (n+8)
  have wordHit := ArgumentsRoundTrip.canonical_word_at_budget word ' ' tail (n+10) safe (by decide)
    (by dsimp [n,input]; omega)
  have eqMiss : recognizeEnv Generated.pegGrammar [] (n+10) (.ref "Eq" []) (' '::tail) = .ok none := by rfl
  have keywordMiss : recognizeEnv Generated.pegGrammar [] (n+11)
      (.choice [[.ref "Word" [], .ref "Eq" []]]) input = .ok none := by
    change runChoices (fun items => runSequence
      (fun scope item source => recognizeEnv Generated.pegGrammar scope (n+10) item source)
      _ [] items input) [[.ref "Word" [], .ref "Eq" []]] = _
    simp [runChoices,foldChoice,runSequence,wordHit,eqMiss,Except.map] <;> rfl
  have argumentMiss : recognizeEnv Generated.pegGrammar [] (n+12) (.ref "SplatArgument" []) input = .ok none := by
    change runChoices (fun items => runSequence
      (fun scope item source => recognizeEnv Generated.pegGrammar scope (n+10) item source)
      _ [] items input) [[.ref "Splat" [], .ref "ExprBody" [], .label (.choice [[.ref "RBr" []]]) "close"]] = _
    simp only [runChoices,foldChoice,List.foldlM]
    rw [PegModelTest.sequence_head_miss _ _ [] (.ref "Splat" []) _ input
      (splat_miss word tail (n+7))]
    rfl
  have budget : (word.chars ++ ' '::tail).length+12+extra = n+12 := by dsimp [n,input]; omega
  rw [budget]
  exact ⟨negative_miss (n+11) _ _ comment,negative_miss (n+11) _ _ keywordMiss,
    negative_miss (n+11) _ _ double,negative_miss (n+11) _ _ splat,argumentMiss⟩

theorem I1_word_capture_space (word : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    let input := word.chars ++ ' ' :: tail
    read Generated.pegGrammar (input.length+14+extra) input =
      .ok (some (' ' :: tail,[Element.node "Argument" [Element.token "Word" word.chars]])) := by
  dsimp only
  let input := word.chars ++ ' '::tail
  let budget := input.length+12+extra
  let reader : KeywordTrace.Reader := fun name args source =>
    if name == "Argument" && args.isEmpty then ArgumentTrace.read Generated.pegGrammar budget source
    else KeywordTrace.leaf Generated.pegGrammar budget name args source
  have guards := word_guards word tail extra safe
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
      .ok (some (' '::tail,[Element.node "Argument" [Element.token "Word" word.chars]])) := by
    change ArgumentTrace.read Generated.pegGrammar budget input = _
    exact ArgumentTrace.I1_word_capture word ' ' tail extra safe (by decide)
  unfold read
  rw [if_neg (by omega),posarg_found]
  change KeywordTrace.finish Generated.pegGrammar "PosArg" input
    (choices Generated.pegGrammar (input.length+14+extra-2) _ branches input) = _
  rw [show input.length+14+extra-2 = budget by dsimp [budget]; omega]
  change KeywordTrace.finish Generated.pegGrammar "PosArg" input
    (choices Generated.pegGrammar budget reader branches input) = _
  simp [branches,choices,sequence,expression,noComment,noKeyword,noDoubleSplat,noSplat,comment,keyword,doubleSplat,splat,missing,argument,
    KeywordTrace.finish,Except.map,CstWrapper.wrap,posarg_inline]

theorem I1_word_ast_space (word : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    let input := word.chars ++ ' ' :: tail
    ArgumentTrace.lower (read Generated.pegGrammar (input.length+14+extra) input) =
      .ok (some (' '::tail,[.positional (.word word.chars)])) := by
  dsimp only
  rw [I1_word_capture_space word tail extra safe]
  rfl

private theorem word_recognizer (word : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    let input := word.chars ++ ' ' :: tail
    recognizeEnv Generated.pegGrammar [] (input.length+14+extra) (.ref "PosArg" []) input =
      .ok (some (' '::tail)) := by
  dsimp only
  let input := word.chars ++ ' '::tail
  let budget := input.length+12+extra
  have guards := word_guards word tail extra safe
  rcases guards with ⟨comment,keyword,doubleSplat,splat,notSplat⟩
  change recognizeEnv Generated.pegGrammar [] budget noComment input = .ok (some input) at comment
  change recognizeEnv Generated.pegGrammar [] budget noKeyword input = .ok (some input) at keyword
  change recognizeEnv Generated.pegGrammar [] budget noDoubleSplat input = .ok (some input) at doubleSplat
  change recognizeEnv Generated.pegGrammar [] budget noSplat input = .ok (some input) at splat
  change recognizeEnv Generated.pegGrammar [] budget (.ref "SplatArgument" []) input = .ok none at notSplat
  dsimp only [noComment,noKeyword,noDoubleSplat,noSplat] at comment keyword doubleSplat splat
  have argument : recognizeEnv Generated.pegGrammar [] budget (.ref "Argument" []) input = .ok (some (' '::tail)) := by
    have projected := ArgumentTrace.I1_word_erasure word ' ' tail extra safe (by decide)
    dsimp only at projected
    rw [ArgumentTrace.I1_word_capture word ' ' tail extra safe (by decide)] at projected
    simpa only [KeywordTrace.erase,Except.map,Option.map] using projected.symm
  rw [show input.length+14+extra = budget+2 by dsimp [budget]; omega]
  conv => lhs; unfold recognizeEnv; dsimp only; rw [posarg_found]
  change runChoices (fun items => runSequence
    (fun scope item source => recognizeEnv Generated.pegGrammar scope budget item source)
    _ [] items input) branches = _
  simp [branches,noComment,noKeyword,noDoubleSplat,noSplat,runChoices,foldChoice,runSequence,
    comment,keyword,doubleSplat,splat,notSplat,argument,Except.map] <;> rfl

theorem I1_word_erasure_space (word : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    let input := word.chars ++ ' ' :: tail
    KeywordTrace.erase (read Generated.pegGrammar (input.length+14+extra) input) =
      recognizeEnv Generated.pegGrammar [] (input.length+14+extra) (.ref "PosArg" []) input := by
  dsimp only
  rw [I1_word_capture_space word tail extra safe]
  simpa only [KeywordTrace.erase,Except.map,Option.map] using (word_recognizer word tail extra safe).symm

#print axioms I1_word_capture_space
#print axioms I1_word_ast_space
#print axioms I1_word_erasure_space
end PosArgTrace
