import MixedKeywords
import PrintedArguments
namespace MixedKeywords
open PegModel WordRoundTrip ArgumentsRoundTrip

def chunk (entry : Entry) : List Char :=
  ' ' :: entry.1.chars ++ '=' :: spelling entry.2
def chunks (args : List Entry) : List (List Char) := args.map chunk

def valueWeight : Input → Nat
  | .word _ => 0
  | .string parts => parts.length

def weight : List Entry → Nat
  | [] => 0
  | (_,parts)::rest => valueWeight parts + weight rest

theorem chunks_length (args : List Entry) : (chunks args).length = args.length := by simp [chunks]
theorem chunks_join (args : List Entry) (suffix : List Char) :
    printArgs args ++ suffix = (chunks args).join ++ '\n'::suffix := by
  induction args with
  | nil => rfl
  | cons entry args ih =>
    rcases entry with ⟨name,parts⟩
    simpa [printArgs,chunks,chunk,List.append_assoc] using congrArg
      (fun tail => ' ' :: name.chars ++ '=' :: spelling parts ++ tail) ih

theorem mixed_comments (args : List Entry) (suffix : List Char) (budget : Nat)
    (safe : safeNames args) (enough : 80 ≤ budget) :
    recognizeEnv Generated.pegGrammar [] budget leadingComments (printArgs args ++ suffix) =
      .ok (some (printArgs args ++ suffix)) := by
  cases args with
  | nil =>
    rw [show budget = (budget-80)+80 by omega]
    rfl
  | cons entry args =>
    rcases entry with ⟨name,parts⟩
    have result := comments_before_keyword (budget-12) name
      (spelling parts ++ (printArgs args ++ suffix)) (safe (name,parts) (by simp))
    rw [show budget-12+12=budget by omega] at result
    simpa [printArgs,leadingComments,List.append_assoc] using result

theorem mixed_step (name : Word) (parts : Input)
    (args : List Entry) (suffix : List Char) (budget : Nat)
    (safe : startsComment name.chars = false) (restSafe : safeNames args)
    (values : safeValues ((name,parts)::args))
    (large : 81 ≤ budget)
    (enough : (printArgs ((name,parts)::args) ++ suffix).length + valueWeight parts + 24 ≤ budget) :
    recognizeEnv Generated.pegGrammar [] budget keywordRepetitionChild (printArgs ((name,parts)::args) ++ suffix) =
      .ok (some (printArgs args ++ suffix)) := by
  have comments := mixed_comments args suffix (budget-1) restSafe (by omega)
  cases parts with
  | word value =>
    obtain ⟨sep,tail,printed,blocked⟩ := printed_tail args
    have result := canonical_printed_keyword_step name value sep (tail ++ suffix) budget
      safe (values (name,.word value) (by simp)) blocked (by
        simp only [printArgs,spelling,printed,List.append_assoc,List.length_append,List.length_cons,valueWeight] at enough ⊢
        omega) (by
        simpa [leadingComments,printed] using comments)
    simpa [printArgs,spelling,printed,List.append_assoc] using result
  | string parts =>
    let tail := printArgs args ++ suffix
    let body := name.chars ++ '='::'"'::(StringRoundTrip.spell parts ++ '"'::tail)
    have hit := QuotedKeywords.quoted_keyword_at_budget name parts tail (budget-3) safe (by
      dsimp [tail]
      simp only [printArgs,spelling,valueWeight,List.cons_append,List.append_assoc,List.length_cons,List.length_append] at enough ⊢
      omega)
    have kwarg := canonical_kwarg_of_keyword (budget-4) body tail (by
      rw [show budget-4+1=budget-3 by omega]
      exact hit)
    rw [show budget-4+3=budget-1 by omega] at kwarg
    have space : recognizeEnv Generated.pegGrammar [] (budget-1) (.ref "Sp" []) (' '::body) = .ok (some body) := by
      cases chars : name.chars with
      | nil => exact False.elim (name.nonempty chars)
      | cons c rest =>
        have result := WordRoundTrip.canonical_space_before_word (budget-11) c
          (rest ++ '='::'"'::(StringRoundTrip.spell parts ++ '"'::tail)) (name.valid c (by simp [chars]))
        rw [show budget-11+10=budget-1 by omega] at result
        simpa [body,chars,List.cons_append] using result
    have result := canonical_keyword_child_of_parts (budget-2) (' '::body) body tail tail
      (by rw [show budget-2+1=budget-1 by omega]; exact space)
      (by rw [show budget-2+1=budget-1 by omega]; exact kwarg)
      (by rw [show budget-2+1=budget-1 by omega]; exact comments)
    rw [show budget-2+2=budget by omega] at result
    simpa [printArgs,spelling,body,tail,List.append_assoc] using result

theorem mixed_hits (args : List Entry) (suffix : List Char) (extra : Nat)
    (safe : safeNames args) (values : safeValues args) (enough : (printArgs args ++ suffix).length + weight args ≤ extra) :
    CanonicalKeywordHits extra suffix (chunks args) := by
  induction args with
  | nil => trivial
  | cons entry args ih =>
    rcases entry with ⟨name,parts⟩
    have firstSafe := safe (name,parts) (by simp)
    have restSafe : safeNames args := by
      intro entry member
      exact safe entry (by simp [member])
    have restEnough : (printArgs args ++ suffix).length + weight args ≤ extra := by
      simp only [printArgs,weight,List.length_append,List.length_cons] at enough ⊢
      omega
    have restValues : safeValues args := by
      intro entry member
      exact values entry (by simp [member])
    have more := ih restSafe restValues restEnough
    have step := mixed_step name parts args suffix (extra+80+(chunks args).length+1)
      firstSafe restSafe values (by omega) (by simp only [weight] at enough; omega)
    rw [chunks_join ((name,parts)::args) suffix,chunks_join args suffix] at step
    exact ⟨step,by simp [chunk],more⟩

theorem mixed_keywords (args : List Entry) (suffix : List Char) (extra : Nat)
    (safe : safeNames args) (values : safeValues args) (enough : (printArgs args ++ suffix).length + weight args ≤ extra) :
    recognizeEnv Generated.pegGrammar [] (extra+80+args.length+1)
      (.star keywordRepetitionChild) (printArgs args ++ suffix) = .ok (some ('\n'::suffix)) := by
  rw [chunks_join args suffix,←chunks_length args]
  exact canonical_star_chunks Generated.pegGrammar [] keywordRepetitionChild (extra+80) ('\n'::suffix)
    (chunks args) (keyword_hits_to_star_steps extra suffix (chunks args) (mixed_hits args suffix extra safe values enough))
#print axioms mixed_hits
#print axioms mixed_keywords
theorem mixed_positional (extra : Nat) (args : List Entry)
    (safe : safeNames args) (suffix : List Char) :
    let input := printArgs args ++ suffix
    PegModel.recognizeEnv Generated.pegGrammar [] (input.length + extra + 20)
      (.star positionalItem) input = .ok (some input) := by
  cases args with
  | nil => rfl
  | cons pair rest =>
    rcases pair with ⟨name, value⟩
    let tail := spelling value ++ (printArgs rest ++ suffix)
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
    simpa [fuel, body, tail, printArgs, List.append_assoc] using star

theorem I1_generated_mixed_arguments (args : List Entry) (suffix : List Char) (extra : Nat)
    (safe : safeNames args) (values : safeValues args) :
    let input := printArgs args ++ suffix
    recognizeEnv Generated.pegGrammar [] (input.length + weight args + extra + args.length + 83)
      (.ref "Arguments" []) input = .ok (some ('\n'::suffix)) := by
  let input := printArgs args ++ suffix
  let budget := input.length + weight args + extra + args.length + 1
  have comments := mixed_comments args suffix (budget+80) safe (by omega)
  have positions := mixed_positional (weight args+extra+args.length+61) args safe suffix
  have keywords := mixed_keywords args suffix (input.length+weight args+extra) safe values (by dsimp [input]; omega)
  change recognizeEnv Generated.pegGrammar [] (input.length+weight args+extra+args.length+83)
    (.ref "Arguments" []) input = _
  apply canonical_arguments_from_repetitions budget input suffix
  · exact comments
  · change recognizeEnv Generated.pegGrammar []
      (input.length+(weight args+extra+args.length+61)+20) (.star positionalItem) input = _ at positions
    rwa [show budget+80=input.length+(weight args+extra+args.length+61)+20 by dsimp [budget]; omega]
  · rwa [show budget+80=input.length+weight args+extra+80+args.length+1 by dsimp [budget]; omega]
#print axioms I1_generated_mixed_arguments
end MixedKeywords
