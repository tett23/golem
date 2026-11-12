import ArgumentsRoundTrip

namespace ArgumentsRoundTrip

def leadingComments : PegModel.Expr := .star (.choice [[.ref "Sp" [], .ref "ArgComment" []]])

def positionalItem : PegModel.Expr :=
  .choice [[.ref "Sp" [], .ref "PosArg" [], leadingComments]]

theorem printed_leading_comments (fuel : Nat) (args : List (WordRoundTrip.Word × WordRoundTrip.Word))
    (safe : WordRoundTrip.safeNames args) (suffix : List Char) :
    let input := WordRoundTrip.printArgs args ++ suffix
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 12) leadingComments input = .ok (some input) := by
  cases args with
  | nil => rfl
  | cons pair rest =>
    rcases pair with ⟨name, value⟩
    have h := WordRoundTrip.comments_before_keyword fuel name
      (value.chars ++ WordRoundTrip.printArgs rest ++ suffix) (safe (name, value) (by simp))
    simpa [leadingComments, WordRoundTrip.printArgs, List.append_assoc] using h

theorem canonical_arguments_from_repetitions (fuel : Nat) (input suffix : List Char)
    (comments : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 80) leadingComments input =
      .ok (some input))
    (positions : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 80) (.star positionalItem) input =
      .ok (some input))
    (keywords : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 80) (.star keywordRepetitionChild) input =
      .ok (some ('\n' :: suffix))) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 82) (.ref "Arguments" []) input =
      .ok (some ('\n' :: suffix)) := by
  have order := canonical_arg_order_accepts_newline fuel suffix
  change PegModel.runChoices (fun items => PegModel.runSequence
    (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 80) item s)
    _ [] items input) [[leadingComments, .star positionalItem, .star keywordRepetitionChild,
      .label (.choice [[.notPred (.choice [[.ref "Sp" [], .ref "PosArg" []]])]]) "arg_order"]] = _
  unfold leadingComments at comments ⊢
  simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, List.foldlM,
    comments, positions, keywords, order, Except.map] <;> rfl

theorem printed_keyword_posarg_miss (name : WordRoundTrip.Word) (tail : List Char) (extra : Nat)
    (safe : WordRoundTrip.startsComment name.chars = false) :
    let input := name.chars ++ '=' :: tail
    PegModel.recognizeEnv Generated.pegGrammar [] (input.length + 12 + extra)
      (.ref "PosArg" []) input = .ok none := by
  let input := name.chars ++ '=' :: tail
  let base := input.length + 8 + extra
  have word := canonical_word_before_equals name tail extra safe
  have eqHit : PegModel.recognizeEnv Generated.pegGrammar [] base (.ref "Eq" []) ('=' :: tail) =
      .ok (some tail) := by
    dsimp only [base]
    rw [show input.length + 8 + extra = (input.length + extra) + 8 by omega]
    cases tail <;> rfl
  have wordEq : PegModel.recognizeEnv Generated.pegGrammar [] (base + 1)
      (.choice [[.ref "Word" [], .ref "Eq" []]]) input = .ok (some tail) := by
    change PegModel.runChoices (fun items => PegModel.runSequence
      (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope base item s)
      _ [] items input) [[.ref "Word" [], .ref "Eq" []]] = _
    change PegModel.recognizeEnv Generated.pegGrammar [] base (.ref "Word" []) input =
      .ok (some ('=' :: tail)) at word
    simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, List.foldlM, word, eqHit, Except.map] <;> rfl
  have guarded := WordRoundTrip.safe_name_before_equals name tail safe
  have missPrefix := (WordRoundTrip.safe_comment_prefixes input guarded).1
  have noComment : PegModel.recognizeEnv Generated.pegGrammar [] (base + 1)
      (.lit "%%" "'%%'") input = .ok none := by
    simp [PegModel.recognizeEnv, missPrefix]; rfl
  have rejected := canonical_posarg_rejects_keyword base input tail noComment wordEq
  change PegModel.recognizeEnv Generated.pegGrammar [] (input.length + 12 + extra) _ input = _
  simpa only [base, show input.length + 8 + extra + 4 = input.length + 12 + extra by omega] using rejected

theorem printed_positional_repetition (extra : Nat) (args : List (WordRoundTrip.Word × WordRoundTrip.Word))
    (safe : WordRoundTrip.safeNames args) (suffix : List Char) :
    let input := WordRoundTrip.printArgs args ++ suffix
    PegModel.recognizeEnv Generated.pegGrammar [] (input.length + extra + 20)
      (.star positionalItem) input = .ok (some input) := by
  cases args with
  | nil => rfl
  | cons pair rest =>
    rcases pair with ⟨name, value⟩
    let tail := value.chars ++ WordRoundTrip.printArgs rest ++ suffix
    let body := name.chars ++ '=' :: tail
    let fuel := (' ' :: body).length + extra
    have rejected := printed_keyword_posarg_miss name tail (extra + 7) (safe (name, value) (by simp))
    have pos : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 18)
        (.ref "PosArg" []) body = .ok none := by
      change PegModel.recognizeEnv Generated.pegGrammar [] (body.length + 12 + (extra + 7)) _ body = _ at rejected
      simpa only [fuel, List.length_cons, show body.length + 1 + extra + 18 =
        body.length + 12 + (extra + 7) by omega] using rejected
    have space : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 18)
        (.ref "Sp" []) (' ' :: body) = .ok (some body) := by
      cases h : name.chars with
      | nil => exact False.elim (name.nonempty h)
      | cons c cs =>
        have sp := WordRoundTrip.canonical_space_before_word (fuel + 8) c (cs ++ '=' :: tail)
          (name.valid c (by simp [h]))
        simpa only [body, h, List.cons_append] using sp
    have miss : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 19)
        positionalItem (' ' :: body) = .ok none := by
      change PegModel.runChoices (fun items => PegModel.runSequence
        (fun scope item s => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 18) item s)
        _ [] items (' ' :: body)) [[.ref "Sp" [], .ref "PosArg" [], leadingComments]] = _
      simp [PegModel.runChoices, PegModel.foldChoice, PegModel.runSequence, List.foldlM, space, pos, Except.map] <;> rfl
    have star : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 20)
        (.star positionalItem) (' ' :: body) = .ok (some (' ' :: body)) := by
      change (match PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 19) positionalItem (' ' :: body) with
        | .error e => Except.error e
        | .ok none => Except.ok (some (' ' :: body))
        | .ok (some remaining) => if remaining.length < (' ' :: body).length then
            PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 19) (.star positionalItem) remaining
          else Except.error "zero-width repetition") = _
      rw [miss]
    simpa [fuel, body, tail, WordRoundTrip.printArgs, List.append_assoc] using star

end ArgumentsRoundTrip
