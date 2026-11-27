import PegModelTest

namespace ReservedCommentTotal

open PegModel PegModelTest

private def newlineRanges : List (Nat × Nat) := [(10, 10)]
private def bodyItems (value written : String) : List Expr :=
  [.notPred (.lit value written), .notPred (.charClass newlineRanges "[\\n]"), .any]
private def body (value written : String) := Expr.choice [bodyItems value written]

def stops (value : String) (input : List Char) : Bool :=
  value.toList.isPrefixOf input || match input with
    | [] => false
    | c :: _ => newlineRanges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)

def suffix (value : String) : List Char → List Char
  | [] => []
  | c :: rest => if stops value (c :: rest) then c :: rest else suffix value rest

private theorem step (grammar : Grammar) (env : Params) (value written : String)
    (input : List Char) (fuel : Nat) :
    recognizeEnv grammar env (fuel + 4) (body value written) input =
      .ok (if stops value input then none else input.tail?) := by
  change runChoices (fun xs => runSequence
    (fun sc item rest => recognizeEnv grammar sc (fuel + 3) item rest)
    _ env xs input) [bodyItems value written] = _
  have delim := not_literal_total grammar env (fuel + 1) value written input
  have cls := not_class grammar env (fuel + 1) newlineRanges "[\\n]" input
  have any : recognizeEnv grammar env (fuel + 3) .any input = .ok input.tail? := by
    cases input <;> rfl
  cases input with
  | nil =>
      cases d : value.toList.isPrefixOf [] <;>
        simp [bodyItems, stops, delim, cls, any, d, runChoices, foldChoice,
          runSequence, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]
  | cons c rest =>
      cases d : value.toList.isPrefixOf (c :: rest) <;>
        cases n : newlineRanges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) <;>
        simp [bodyItems, stops, delim, cls, any, d, n, runChoices, foldChoice,
          runSequence, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]

theorem repeated (grammar : Grammar) (env : Params) (value written : String)
    (input : List Char) (extra : Nat) :
    recognizeEnv grammar env (input.length + 5 + extra) (.star (body value written)) input =
      .ok (some (suffix value input)) := by
  induction input with
  | nil =>
      rw [show ([] : List Char).length + 5 + extra = extra + 4 + 1 by simp; omega]
      conv => lhs; unfold recognizeEnv
      have first := step grammar env value written [] extra
      simp only [List.tail?, ite_self] at first
      simp [first, suffix]; rfl
  | cons c rest ih =>
      let inner := rest.length + 5 + extra
      rw [show (c :: rest).length + 5 + extra = inner + 1 by dsimp [inner]; omega]
      have first := step grammar env value written (c :: rest) (rest.length + 1 + extra)
      rw [show rest.length + 1 + extra + 4 = inner by dsimp [inner]; omega] at first
      change recognizeEnv _ _ inner _ rest = _ at ih
      conv => lhs; unfold recognizeEnv
      cases stop : stops value (c :: rest) <;> simp [first, stop, ih, suffix, Id.run]

private theorem repeated_at (grammar : Grammar) (env : Params) (value written : String)
    (input : List Char) (fuel : Nat) (enough : input.length + 5 ≤ fuel) :
    recognizeEnv grammar env fuel (.star (body value written)) input =
      .ok (some (suffix value input)) := by
  have result := repeated grammar env value written input (fuel - (input.length + 5))
  simpa [show input.length + 5 + (fuel - (input.length + 5)) = fuel by omega] using result

def commentItems (value written : String) : List Expr :=
  [.lit value written, .star (body value written), .lit value written]

def result (value : String) (input : List Char) : Option (List Char) :=
  if value.toList.isPrefixOf input then
    let rest := suffix value (input.drop value.toList.length)
    if value.toList.isPrefixOf rest then some (rest.drop value.toList.length) else none
  else none

theorem delimited_line_comment (grammar : Grammar) (env : Params)
    (boundLength : Params → Expr → List Char → Except String (Option Nat))
    (value written : String) (input : List Char) (extra : Nat) :
    runSequence (fun sc item rest => recognizeEnv grammar sc (input.length + 6 + extra) item rest)
      boundLength env (commentItems value written) input = .ok (result value input) := by
  have opening := literal_total grammar env (input.length + 5 + extra) value written input
  have remaining := repeated_at grammar env value written (input.drop value.toList.length)
    (input.length + 6 + extra) (by simp only [List.length_drop]; omega)
  have closing := literal_total grammar env (input.length + 5 + extra) value written
    (suffix value (input.drop value.toList.length))
  rw [show input.length + 5 + extra + 1 = input.length + 6 + extra by omega] at opening closing
  cases first : value.toList.isPrefixOf input <;>
    cases last : value.toList.isPrefixOf (suffix value (input.drop value.toList.length)) <;>
    simp [commentItems, result, opening, remaining, closing, first, last, runSequence,
      List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]

private def exportedCommentItems : Option (List Expr) :=
    (Generated.pegGrammar.rules.find? (fun r => r.name == "ReservedBracketBody")).bind
      (fun r => match r.alts with
        | [alt] => match alt.items with
          | [.star (.choice alts)] => alts[1]?
          | _ => none
        | _ => none)

theorem generated_comment_shape :
    exportedCommentItems = some (commentItems "%%" "'%%'") := by rfl

theorem generated_comment (input : List Char) (extra : Nat) :
    runSequence
      (fun sc item rest => recognizeEnv Generated.pegGrammar sc (input.length + 6 + extra) item rest)
      (fun _ _ _ => .ok none) [] (exportedCommentItems.getD []) input =
      .ok (result "%%" input) := by
  rw [generated_comment_shape]
  exact delimited_line_comment _ _ _ _ _ _ _

example : result "%%" "%%%%tail".toList = some "tail".toList := by decide
example : result "%%" "%%]text%%tail".toList = some "tail".toList := by decide
example : result "%%" "%%unfinished".toList = none := by decide
example : result "%%" "%%line\nbreak%%".toList = none := by decide

#print axioms delimited_line_comment
#print axioms generated_comment

end ReservedCommentTotal
