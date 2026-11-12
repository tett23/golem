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

end ArgumentsRoundTrip
