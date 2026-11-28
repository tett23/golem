import PosArgTrace
import PosArgDelimitedMetadata
import PosArgBracketPrefix
namespace PosArgDelimited
open PegModel CstWrapper PosArgTrace
set_option autoImplicit false

private theorem blocked_excludes (separator target : Char)
    (blocked : WordRoundTrip.allowed separator = false)
    (valid : WordRoundTrip.allowed target = true) : (target == separator) = false := by
  cases equal : (target == separator) with
  | false => rfl
  | true =>
    have same : target = separator := eq_of_beq equal
    subst target
    exact valid.symm.trans blocked

private theorem safe_after_separator (word : WordRoundTrip.Word) (separator : Char) (tail : List Char)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) :
    WordRoundTrip.startsComment (word.chars ++ separator :: tail) = false := by
  have notPercent : separator ≠ '%' := by
    intro same
    subst separator
    contradiction
  cases chars : word.chars with
  | nil => exact False.elim (word.nonempty chars)
  | cons first rest =>
    cases rest with
    | nil =>
      by_cases firstEq : first = '%'
      <;> simp_all [WordRoundTrip.startsComment]
    | cons second rest =>
      by_cases firstEq : first = '%'
      <;> by_cases secondEq : second = '%'
      <;> simp_all [WordRoundTrip.startsComment]

private theorem bracket_miss (word : WordRoundTrip.Word) (c : Char)
    (member : c ∈ word.chars) : ('[' == c) = false := by
  have valid := word.valid c member
  cases equal : ('[' == c) with
  | false => rfl
  | true =>
    have same : '[' = c := eq_of_beq equal
    subst c
    contradiction

private theorem splat_prefixes_after_separator (word : WordRoundTrip.Word) (separator : Char) (tail : List Char)
    (blocked : WordRoundTrip.allowed separator = false) (bracketSafe : separator = '[' → word.chars ≠ ['*'] ∧ word.chars ≠ ['*','*']) :
    "*[".toList.isPrefixOf (word.chars ++ separator :: tail) = false ∧
    "**[".toList.isPrefixOf (word.chars ++ separator :: tail) = false := by
  by_cases isBracket : separator = '['
  · subst separator
    exact PosArgBracketPrefix.I1_no_splat_prefix word tail (bracketSafe rfl).1 (bracketSafe rfl).2
  ·
    have bracketSep : ('[' == separator) = false := by
      cases equal : ('[' == separator) with
      | false => rfl
      | true => exact False.elim (isBracket (eq_of_beq equal).symm)
    have starSep := blocked_excludes separator '*' blocked (by decide)
    cases chars : word.chars with
    | nil => exact False.elim (word.nonempty chars)
    | cons first rest =>
      cases rest with
      | nil => simp [List.append,List.isPrefixOf,bracketSep,starSep]
      | cons second rest =>
        have secondMiss := bracket_miss word second (by simp [chars])
        cases rest with
        | nil => simp [List.append,List.isPrefixOf,secondMiss,bracketSep]
        | cons third rest =>
          have thirdMiss := bracket_miss word third (by simp [chars])
          simp [List.append,List.isPrefixOf,secondMiss,thirdMiss]

private theorem keyword_misses_after_separator (word : WordRoundTrip.Word) (separator : Char)
    (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') :
    let input := word.chars ++ separator::tail
    PegModel.recognizeEnv Generated.pegGrammar [] (input.length+11+extra)
      (.choice [[.ref "Word" [],.ref "Eq" []]]) input = .ok none := by
  dsimp only
  let input := word.chars ++ separator::tail
  let n := input.length+extra
  have eqSep : ('=' == separator) = false := by
    cases equal : ('=' == separator) with
    | false => rfl
    | true => exact False.elim (notEq (eq_of_beq equal).symm)
  have noEqPrefix : "=".toList.isPrefixOf (separator::tail) = false := by
    simp [List.isPrefixOf,eqSep]
  have literalMiss : PegModel.recognizeEnv Generated.pegGrammar [] (n+8)
      (.lit "=" "'='") (separator::tail) = .ok none := by
    simp [PegModel.recognizeEnv,noEqPrefix]; rfl
  have eqMiss : PegModel.recognizeEnv Generated.pegGrammar [] (n+10)
      (.ref "Eq" []) (separator::tail) = .ok none := by
    change PegModel.runChoices (fun items => PegModel.runSequence
      (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (n+8) item source)
      _ [] items (separator::tail)) [[.lit "=" "'='"]] = _
    simp [PegModel.runChoices,PegModel.foldChoice,PegModel.runSequence,literalMiss,Except.map] <;> rfl
  have wordHit := ArgumentsRoundTrip.canonical_word_at_budget word separator tail (n+10) safe blocked
    (by dsimp [n,input]; omega)
  have actual : PegModel.recognizeEnv Generated.pegGrammar [] (n+11)
      (.choice [[.ref "Word" [],.ref "Eq" []]]) input = .ok none := by
    change PegModel.runChoices (fun items => PegModel.runSequence
      (fun scope item source => PegModel.recognizeEnv Generated.pegGrammar scope (n+10) item source)
      _ [] items input) [[.ref "Word" [],.ref "Eq" []]] = _
    simp [PegModel.runChoices,PegModel.foldChoice,PegModel.runSequence,wordHit,eqMiss,Except.map] <;> rfl
  rw [show (word.chars ++ separator::tail).length+11+extra = n+11 by dsimp [n,input]; omega]
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

private theorem splat_miss (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (fuel : Nat)
    (blocked : WordRoundTrip.allowed separator = false) (bracketSafe : separator = '[' → word.chars ≠ ['*'] ∧ word.chars ≠ ['*','*']) :
    recognizeEnv Generated.pegGrammar [] (fuel + 3) (.ref "Splat" [])
      (word.chars ++ separator :: tail) = .ok none := by
  have prefixes := splat_prefixes_after_separator word separator tail blocked bracketSafe
  have first := literal_miss fuel "**[" "'**['" _ prefixes.2
  have second := literal_miss fuel "*[" "'*['" _ prefixes.1
  change runChoices (fun items => runSequence
    (fun scope item source => recognizeEnv Generated.pegGrammar scope (fuel+1) item source)
    _ [] items (word.chars ++ separator :: tail)) [[.lit "**[" "'**['"], [.lit "*[" "'*['"]] = _
  simp [runChoices,foldChoice,runSequence,first,second,Except.map] <;> rfl

private theorem word_guards (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') (bracketSafe : separator = '[' → word.chars ≠ ['*'] ∧ word.chars ≠ ['*','*']) :
    let input := word.chars ++ separator :: tail
    let budget := input.length+12+extra
    recognizeEnv Generated.pegGrammar [] budget noComment input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget noKeyword input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget noDoubleSplat input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget noSplat input = .ok (some input) ∧
    recognizeEnv Generated.pegGrammar [] budget (.ref "SplatArgument" []) input = .ok none := by
  dsimp only
  let input := word.chars ++ separator :: tail
  let n := input.length+extra
  have commentPrefix := WordRoundTrip.safe_comment_prefixes input (safe_after_separator word separator tail safe blocked)
  have splatPrefix := splat_prefixes_after_separator word separator tail blocked bracketSafe
  have comment := literal_miss (n+10) "%%" "'%%'" input commentPrefix.1
  have double := literal_miss (n+10) "**[" "'**['" input splatPrefix.2
  have splat := splat_miss word separator tail (n+8) blocked bracketSafe
  have keywordMiss := keyword_misses_after_separator word separator tail extra safe blocked notEq
  dsimp only at keywordMiss
  rw [show (word.chars ++ separator::tail).length+11+extra = n+11 by dsimp [n,input]; omega] at keywordMiss
  have argumentMiss : recognizeEnv Generated.pegGrammar [] (n+12) (.ref "SplatArgument" []) input = .ok none := by
    change runChoices (fun items => runSequence
      (fun scope item source => recognizeEnv Generated.pegGrammar scope (n+10) item source)
      _ [] items input) [[.ref "Splat" [], .ref "ExprBody" [], .label (.choice [[.ref "RBr" []]]) "close"]] = _
    simp only [runChoices,foldChoice,List.foldlM]
    rw [PegModelTest.sequence_head_miss _ _ [] (.ref "Splat" []) _ input
      (splat_miss word separator tail (n+7) blocked bracketSafe)]
    rfl
  have budget : (word.chars ++ separator::tail).length+12+extra = n+12 := by dsimp [n,input]; omega
  rw [budget]
  exact ⟨negative_miss (n+11) _ _ comment,negative_miss (n+11) _ _ keywordMiss,
    negative_miss (n+11) _ _ double,negative_miss (n+11) _ _ splat,argumentMiss⟩

private theorem boundary_capture (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') (bracketSafe : separator = '[' → word.chars ≠ ['*'] ∧ word.chars ≠ ['*','*']) :
    let input := word.chars ++ separator :: tail
    read Generated.pegGrammar (input.length+14+extra) input =
      .ok (some (separator :: tail,[Element.node "Argument" [Element.token "Word" word.chars]])) := by
  dsimp only
  let input := word.chars ++ separator::tail
  let budget := input.length+12+extra
  let reader : KeywordTrace.Reader := fun name args source =>
    if name == "Argument" && args.isEmpty then ArgumentTrace.read Generated.pegGrammar budget source
    else KeywordTrace.leaf Generated.pegGrammar budget name args source
  have guards := word_guards word separator tail extra safe blocked notEq bracketSafe
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
      .ok (some (separator::tail,[Element.node "Argument" [Element.token "Word" word.chars]])) := by
    change ArgumentTrace.read Generated.pegGrammar budget input = _
    exact ArgumentTrace.I1_word_capture word separator tail extra safe blocked
  unfold PosArgTrace.read
  rw [if_neg (by omega),posarg_found]
  change KeywordTrace.finish Generated.pegGrammar "PosArg" input
    (choices Generated.pegGrammar (input.length+14+extra-2) _ branches input) = _
  rw [show input.length+14+extra-2 = budget by dsimp [budget]; omega]
  change KeywordTrace.finish Generated.pegGrammar "PosArg" input
    (choices Generated.pegGrammar budget reader branches input) = _
  simp [branches,choices,sequence,expression,noComment,noKeyword,noDoubleSplat,noSplat,comment,keyword,doubleSplat,splat,missing,argument,
    KeywordTrace.finish,Except.map,CstWrapper.wrap,posarg_inline]

private theorem boundary_ast (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') (bracketSafe : separator = '[' → word.chars ≠ ['*'] ∧ word.chars ≠ ['*','*']) :
    let input := word.chars ++ separator :: tail
    ArgumentTrace.lower (read Generated.pegGrammar (input.length+14+extra) input) =
      .ok (some (separator::tail,[.positional (.word word.chars)])) := by
  dsimp only
  rw [boundary_capture word separator tail extra safe blocked notEq bracketSafe]
  rfl

private theorem word_recognizer (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') (bracketSafe : separator = '[' → word.chars ≠ ['*'] ∧ word.chars ≠ ['*','*']) :
    let input := word.chars ++ separator :: tail
    recognizeEnv Generated.pegGrammar [] (input.length+14+extra) (.ref "PosArg" []) input =
      .ok (some (separator::tail)) := by
  dsimp only
  let input := word.chars ++ separator::tail
  let budget := input.length+12+extra
  have guards := word_guards word separator tail extra safe blocked notEq bracketSafe
  rcases guards with ⟨comment,keyword,doubleSplat,splat,notSplat⟩
  change recognizeEnv Generated.pegGrammar [] budget noComment input = .ok (some input) at comment
  change recognizeEnv Generated.pegGrammar [] budget noKeyword input = .ok (some input) at keyword
  change recognizeEnv Generated.pegGrammar [] budget noDoubleSplat input = .ok (some input) at doubleSplat
  change recognizeEnv Generated.pegGrammar [] budget noSplat input = .ok (some input) at splat
  change recognizeEnv Generated.pegGrammar [] budget (.ref "SplatArgument" []) input = .ok none at notSplat
  dsimp only [noComment,noKeyword,noDoubleSplat,noSplat] at comment keyword doubleSplat splat
  have argument : recognizeEnv Generated.pegGrammar [] budget (.ref "Argument" []) input = .ok (some (separator::tail)) := by
    have projected := ArgumentTrace.I1_word_erasure word separator tail extra safe blocked
    dsimp only at projected
    rw [ArgumentTrace.I1_word_capture word separator tail extra safe blocked] at projected
    simpa only [KeywordTrace.erase,Except.map,Option.map] using projected.symm
  rw [show input.length+14+extra = budget+2 by dsimp [budget]; omega]
  conv => lhs; unfold recognizeEnv; dsimp only; rw [posarg_found]
  change runChoices (fun items => runSequence
    (fun scope item source => recognizeEnv Generated.pegGrammar scope budget item source)
    _ [] items input) branches = _
  simp [branches,noComment,noKeyword,noDoubleSplat,noSplat,runChoices,foldChoice,runSequence,
    comment,keyword,doubleSplat,splat,notSplat,argument,Except.map] <;> rfl

private theorem boundary_erasure (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') (bracketSafe : separator = '[' → word.chars ≠ ['*'] ∧ word.chars ≠ ['*','*']) :
    let input := word.chars ++ separator :: tail
    KeywordTrace.erase (read Generated.pegGrammar (input.length+14+extra) input) =
      recognizeEnv Generated.pegGrammar [] (input.length+14+extra) (.ref "PosArg" []) input := by
  dsimp only
  rw [boundary_capture word separator tail extra safe blocked notEq bracketSafe]
  simpa only [KeywordTrace.erase,Except.map,Option.map] using (word_recognizer word separator tail extra safe blocked notEq bracketSafe).symm

theorem I1_delimited_capture (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') (notBracket : separator ≠ '[') :
    let input := word.chars ++ separator :: tail
    read Generated.pegGrammar (input.length+14+extra) input =
      .ok (some (separator :: tail,[Element.node "Argument" [Element.token "Word" word.chars]])) := by
  exact boundary_capture word separator tail extra safe blocked notEq
    (by intro same; exact False.elim (notBracket same))

theorem I1_delimited_ast (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') (notBracket : separator ≠ '[') :
    let input := word.chars ++ separator :: tail
    ArgumentTrace.lower (read Generated.pegGrammar (input.length+14+extra) input) =
      .ok (some (separator::tail,[.positional (.word word.chars)])) := by
  exact boundary_ast word separator tail extra safe blocked notEq
    (by intro same; exact False.elim (notBracket same))

theorem I1_delimited_erasure (word : WordRoundTrip.Word) (separator : Char) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (blocked : WordRoundTrip.allowed separator = false) (notEq : separator ≠ '=') (notBracket : separator ≠ '[') :
    let input := word.chars ++ separator :: tail
    KeywordTrace.erase (read Generated.pegGrammar (input.length+14+extra) input) =
      recognizeEnv Generated.pegGrammar [] (input.length+14+extra) (.ref "PosArg" []) input := by
  exact boundary_erasure word separator tail extra safe blocked notEq
    (by intro same; exact False.elim (notBracket same))

theorem I1_bracket_capture (word : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (single : word.chars ≠ ['*']) (double : word.chars ≠ ['*','*']) :
    let input := word.chars ++ '[' :: tail
    read Generated.pegGrammar (input.length+14+extra) input =
      .ok (some ('[' :: tail,[Element.node "Argument" [Element.token "Word" word.chars]])) := by
  exact boundary_capture word '[' tail extra safe (by decide) (by decide)
    (by intro _; exact ⟨single,double⟩)

theorem I1_bracket_ast (word : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (single : word.chars ≠ ['*']) (double : word.chars ≠ ['*','*']) :
    let input := word.chars ++ '[' :: tail
    ArgumentTrace.lower (read Generated.pegGrammar (input.length+14+extra) input) =
      .ok (some ('['::tail,[.positional (.word word.chars)])) := by
  exact boundary_ast word '[' tail extra safe (by decide) (by decide)
    (by intro _; exact ⟨single,double⟩)

theorem I1_bracket_erasure (word : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false)
    (single : word.chars ≠ ['*']) (double : word.chars ≠ ['*','*']) :
    let input := word.chars ++ '[' :: tail
    KeywordTrace.erase (read Generated.pegGrammar (input.length+14+extra) input) =
      recognizeEnv Generated.pegGrammar [] (input.length+14+extra) (.ref "PosArg" []) input := by
  exact boundary_erasure word '[' tail extra safe (by decide) (by decide)
    (by intro _; exact ⟨single,double⟩)

#print axioms I1_delimited_capture
#print axioms I1_bracket_capture
#print axioms I1_delimited_ast
#print axioms I1_bracket_ast
#print axioms I1_delimited_erasure
#print axioms I1_bracket_erasure
end PosArgDelimited
