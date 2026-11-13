import LineBoundaryTotal

namespace CommentTotal

open PegModel PegModelTest

private def delimiter (value written : String) := Expr.lit value written
private def para := Expr.ref "ParaEnd" []
private def bodyItems (value written : String) : List Expr := [.notPred (delimiter value written), .notPred para, .any]
private def body (value written : String) := Expr.choice [bodyItems value written]


def stops (value : String) (input : List Char) := value.toList.isPrefixOf input || (LineBoundaryTotal.paraResult input).isSome

def suffix (value : String) : List Char → List Char
  | [] => []
  | c :: rest => if stops value (c :: rest) then c :: rest else suffix value rest

private theorem step (value written : String) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 12 + extra) (body value written) input =
      .ok (if stops value input then none else input.tail?) := by
  let inner := input.length + 11 + extra
  rw [show input.length + 12 + extra = inner + 1 by dsimp [inner]; omega]
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc inner item rest)
    (fun _ _ _ => .ok none) [] xs input) [bodyItems value written] = _
  have del := not_literal_total Generated.pegGrammar [] (input.length + 9 + extra) value written input
  rw [show input.length + 9 + extra + 2 = inner by dsimp [inner]; omega] at del
  change recognizeEnv _ [] inner (.notPred (delimiter value written)) _ = _ at del
  have endAt : recognizeEnv Generated.pegGrammar [] inner (.notPred para) input =
      .ok (if (LineBoundaryTotal.paraResult input).isSome then none else some input) := by
    rw [show inner = (input.length + 10 + extra) + 1 by dsimp [inner]; omega]
    change (match recognizeEnv Generated.pegGrammar [] (input.length + 10 + extra) (.ref "ParaEnd" []) input with
      | Except.error reason => if isLabelFailure reason then Except.ok (some input) else Except.error reason
      | Except.ok none => Except.ok (some input)
      | Except.ok (some _) => Except.ok none) = _
    rw [LineBoundaryTotal.generated_para_end]
    cases LineBoundaryTotal.paraResult input <;> rfl
  have any : recognizeEnv Generated.pegGrammar [] inner .any input = .ok input.tail? := by
    rw [show inner = (input.length + 10 + extra) + 1 by dsimp [inner]; omega]
    cases input <;> rfl
  cases d : value.toList.isPrefixOf input <;> cases p : (LineBoundaryTotal.paraResult input).isSome <;>
    cases t : input.tail? <;> simp [stops, bodyItems, del, endAt, any, d, p, t, runChoices, runSequence,
      foldChoice, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]

private theorem repeated (value written : String) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 13 + extra) (.star (body value written)) input =
      .ok (some (suffix value input)) := by
  induction input with
  | nil =>
      rw [show ([] : List Char).length + 13 + extra = (([] : List Char).length + 12 + extra) + 1 by omega]
      conv => lhs; unfold recognizeEnv
      have first := step value written [] extra
      simp only [List.tail?, ite_self] at first
      change recognizeEnv _ [] (12 + extra) (body value written) [] = .ok none at first
      simp [first, suffix]; rfl
  | cons c rest ih =>
      let inner := (c :: rest).length + 12 + extra
      rw [show (c :: rest).length + 13 + extra = inner + 1 by dsimp [inner]; omega]
      have first := step value written (c :: rest) extra
      change recognizeEnv _ [] inner (body value written) (c :: rest) = .ok (if stops value (c :: rest) then none else some rest) at first
      rw [show rest.length + 13 + extra = inner by dsimp [inner]] at ih
      conv => lhs; unfold recognizeEnv
      cases doneAt : stops value (c :: rest) <;> simp [first, doneAt, ih, suffix, Id.run]

theorem generated_skipped_expr (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 15 + extra) (.ref "SkippedExpr" []) input =
      .ok (some (suffix "]" input)) := by
  let inner := input.length + 13 + extra
  rw [show input.length + 15 + extra = inner + 1 + 1 by dsimp [inner]; omega]
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc inner item rest)
    (fun _ _ _ => .ok none) [] xs input) [[.star (body "]" "']'")]] = _
  have many := repeated "]" "']'" input extra
  change recognizeEnv _ [] inner (.star (body "]" "']'")) input = _ at many
  simp [many, runChoices, runSequence, foldChoice, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]

private def close := Expr.label (.choice [[delimiter "%%" "'%%'"]]) "comment_close"

def closingResult (input : List Char) : ParseResult :=
  if "%%".toList.isPrefixOf input then .ok (some (input.drop 2)) else .error "label: comment_close"

private theorem closing (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar [] (fuel + 3) close input = closingResult input := by
  have lit := sequence_literal_total Generated.pegGrammar [] (fun _ _ _ => .ok none) fuel "%%" "'%%'" input
  have choice : recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice [[delimiter "%%" "'%%'"]]) input =
      .ok (if "%%".toList.isPrefixOf input then some (input.drop 2) else none) := by
    change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
      (fuel + 1) item rest) (fun _ _ _ => .ok none) [] xs input) [[.lit "%%" "'%%'"]] = _
    simp only [runChoices, foldChoice, List.foldlM]
    rw [lit]; rfl
  change (match recognizeEnv Generated.pegGrammar [] (fuel + 2) (.choice [[delimiter "%%" "'%%'"]]) input with
    | Except.ok none => Except.error "label: comment_close"
    | result => result) = _
  rw [choice]
  cases hit : "%%".toList.isPrefixOf input <;> simp [closingResult, hit]

def result (opening : String) (input : List Char) : ParseResult :=
  if opening.toList.isPrefixOf input then closingResult (suffix "%%" (input.drop opening.toList.length)) else .ok none

theorem generated_comment (name opening written : String) (env : Params) (input : List Char) (extra : Nat)
    (kind : (name = "Comment" ∧ opening = "%%" ∧ written = "'%%'") ∨
      (name = "ProofComment" ∧ opening = "%%=" ∧ written = "'%%='")) :
    recognizeEnv Generated.pegGrammar env (input.length + 15 + extra) (.ref name []) input =
      result opening input := by
  let inner := input.length + 13 + extra
  rw [show input.length + 15 + extra = inner + 1 + 1 by dsimp [inner]; omega]
  have resolve : recognizeEnv Generated.pegGrammar env (inner + 1 + 1) (.ref name []) input =
      recognizeEnv Generated.pegGrammar [] (inner + 1) (.choice [[.lit opening written, .star (body "%%" "'%%'"), close]]) input := by
    rcases kind with ⟨rfl, rfl, rfl⟩ | ⟨rfl, rfl, rfl⟩ <;> rfl
  rw [resolve]
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc inner item rest)
    (fun _ _ _ => .ok none) [] xs input) [[.lit opening written, .star (body "%%" "'%%'"), close]] = _
  have lit := literal_total Generated.pegGrammar [] (input.length + 12 + extra) opening written input
  rw [show input.length + 12 + extra + 1 = inner by dsimp [inner]; omega] at lit
  let rest := input.drop opening.toList.length
  have shrinks : rest.length ≤ input.length := by simp [rest]; omega
  have many := repeated "%%" "'%%'" rest (input.length - rest.length + extra)
  rw [show rest.length + 13 + (input.length - rest.length + extra) = inner by dsimp [inner]; omega] at many
  have endAt := closing (suffix "%%" rest) (input.length + 10 + extra)
  rw [show input.length + 10 + extra + 3 = inner by dsimp [inner]; omega] at endAt
  change recognizeEnv _ [] inner (.lit opening written) input =
    .ok (if opening.toList.isPrefixOf input then some rest else none) at lit
  change _ = (if opening.toList.isPrefixOf input then closingResult (suffix "%%" rest) else .ok none)
  cases hit : opening.toList.isPrefixOf input <;> cases final : closingResult (suffix "%%" rest) with
  | error reason =>
      simp [hit, lit, many, endAt, final, runChoices, runSequence, foldChoice, List.foldlM,
        Bind.bind, Except.bind, pure, Except.pure, Except.map]
  | ok value =>
      cases value <;> simp [hit, lit, many, endAt, final, runChoices, runSequence, foldChoice, List.foldlM,
        Bind.bind, Except.bind, pure, Except.pure, Except.map] <;> rfl

end CommentTotal

namespace RestTotal

open PegModel PegModelTest

private def para := Expr.ref "ParaEnd" []
private def bodyItems : List Expr := [.notPred para, .any]
private def body := Expr.choice [bodyItems]


def stops (input : List Char) := (LineBoundaryTotal.paraResult input).isSome

def suffix : List Char → List Char
  | [] => []
  | c :: rest => if stops (c :: rest) then c :: rest else suffix rest

private theorem step (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 12 + extra) body input =
      .ok (if stops input then none else input.tail?) := by
  let inner := input.length + 11 + extra
  rw [show input.length + 12 + extra = inner + 1 by dsimp [inner]; omega]
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc inner item rest)
    (fun _ _ _ => .ok none) [] xs input) [bodyItems] = _
  have endAt : recognizeEnv Generated.pegGrammar [] inner (.notPred para) input =
      .ok (if (LineBoundaryTotal.paraResult input).isSome then none else some input) := by
    rw [show inner = (input.length + 10 + extra) + 1 by dsimp [inner]; omega]
    change (match recognizeEnv Generated.pegGrammar [] (input.length + 10 + extra) (.ref "ParaEnd" []) input with
      | Except.error reason => if isLabelFailure reason then Except.ok (some input) else Except.error reason
      | Except.ok none => Except.ok (some input)
      | Except.ok (some _) => Except.ok none) = _
    rw [LineBoundaryTotal.generated_para_end]
    cases LineBoundaryTotal.paraResult input <;> rfl
  have any : recognizeEnv Generated.pegGrammar [] inner .any input = .ok input.tail? := by
    rw [show inner = (input.length + 10 + extra) + 1 by dsimp [inner]; omega]
    cases input <;> rfl
  cases p : (LineBoundaryTotal.paraResult input).isSome <;>
    cases t : input.tail? <;> simp [stops, bodyItems, endAt, any, p, t, runChoices, runSequence,
      foldChoice, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]

private theorem repeated (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 13 + extra) (.star body) input =
      .ok (some (suffix input)) := by
  induction input with
  | nil =>
      rw [show ([] : List Char).length + 13 + extra = (([] : List Char).length + 12 + extra) + 1 by omega]
      conv => lhs; unfold recognizeEnv
      have first := step [] extra
      change recognizeEnv _ [] (12 + extra) body [] = .ok none at first
      simp [first, suffix]; rfl
  | cons c rest ih =>
      let inner := (c :: rest).length + 12 + extra
      rw [show (c :: rest).length + 13 + extra = inner + 1 by dsimp [inner]; omega]
      have first := step (c :: rest) extra
      change recognizeEnv _ [] inner body (c :: rest) = .ok (if stops (c :: rest) then none else some rest) at first
      rw [show rest.length + 13 + extra = inner by dsimp [inner]] at ih
      conv => lhs; unfold recognizeEnv
      cases doneAt : stops (c :: rest) <;> simp [first, doneAt, ih, suffix, Id.run]

theorem generated_rest (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 15 + extra) (.ref "Rest" []) input =
      .ok (some (suffix input)) := by
  let inner := input.length + 13 + extra
  rw [show input.length + 15 + extra = inner + 1 + 1 by dsimp [inner]; omega]
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc inner item rest)
    (fun _ _ _ => .ok none) [] xs input) [[.star body]] = _
  have many := repeated input extra
  change recognizeEnv _ [] inner (.star body) input = _ at many
  simp [many, runChoices, runSequence, foldChoice, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]

end RestTotal
