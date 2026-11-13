import PegModelTest

namespace LineBoundaryTotal

open PegModel PegModelTest

def ranges := [(32, 32), (9, 9)]
def whitespace (c : Char) := ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
def wsClass := Expr.charClass ranges "[ \\t]"

private theorem star (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 2 + extra) (.star wsClass) input =
      .ok (some (input.dropWhile whitespace)) := by
  induction input with
  | nil =>
      rw [show ([] : List Char).length + 2 + extra = extra + 1 + 1 by simp; omega]
      rfl
  | cons c rest ih =>
      rw [show (c :: rest).length + 2 + extra = (rest.length + 2 + extra) + 1 by simp; omega]
      have test := class_total Generated.pegGrammar [] (rest.length + 1 + extra)
        ranges "[ \\t]" (c :: rest)
      rw [show rest.length + 1 + extra + 1 = rest.length + 2 + extra by omega] at test
      change recognizeEnv _ [] _ wsClass _ = .ok (if whitespace c then some rest else none) at test
      conv => lhs; unfold recognizeEnv
      cases hit : whitespace c <;> simp [test, hit, ih, List.dropWhile, Id.run] <;> rfl

def wsResult : List Char → Option (List Char)
  | [] => none
  | c :: rest => if whitespace c then some (rest.dropWhile whitespace) else none

theorem ws (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 4 + extra) (.ref "Ws" []) input =
      .ok (wsResult input) := by
  rw [show input.length + 4 + extra = (input.length + 2 + extra) + 1 + 1 by omega]
  change recognizeEnv _ [] ((input.length + 2 + extra) + 1) (.choice [[.plus wsClass]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (input.length + 2 + extra) item rest) (fun _ _ _ => .ok none) [] xs input) [[.plus wsClass]] = _
  have plus : recognizeEnv Generated.pegGrammar [] (input.length + 2 + extra) (.plus wsClass) input =
      .ok (wsResult input) := by
    cases input with
    | nil => rw [show ([] : List Char).length + 2 + extra = extra + 1 + 1 by simp; omega]; rfl
    | cons c rest =>
        rw [show (c :: rest).length + 2 + extra = (rest.length + 2 + extra) + 1 by simp; omega]
        have test := class_total Generated.pegGrammar [] (rest.length + 1 + extra) ranges "[ \\t]" (c :: rest)
        rw [show rest.length + 1 + extra + 1 = rest.length + 2 + extra by omega] at test
        change recognizeEnv _ [] _ wsClass _ = .ok (if whitespace c then some rest else none) at test
        conv => lhs; unfold recognizeEnv
        cases hit : whitespace c <;> simp [test, hit, star, wsResult, Id.run] <;> rfl
  cases res : wsResult input <;>
    simp [runChoices, foldChoice, runSequence, List.foldlM, plus, res, Bind.bind, Except.bind, pure,
      Except.pure, Except.map]

private theorem optional_ws (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 5 + extra) (.opt (.ref "Ws" [])) input =
      .ok (some (input.dropWhile whitespace)) := by
  rw [show input.length + 5 + extra = (input.length + 4 + extra) + 1 by omega]
  conv => lhs; unfold recognizeEnv
  have result := ws env input extra
  change (match recognizeEnv Generated.pegGrammar env (input.length + 4 + extra) (.ref "Ws" []) input with
    | Except.error reason => Except.error reason
    | Except.ok none => Except.ok (some input)
    | Except.ok hit => Except.ok hit) = _
  rw [result]
  cases input with
  | nil => simp [wsResult]
  | cons c rest =>
      cases hit : whitespace c <;> simp [wsResult, hit, List.dropWhile] <;> rfl

def afterNl : List Char → Option (List Char)
  | [] => none
  | '\n' :: rest => some rest
  | _ :: _ => none

def blankResult (input : List Char) : Option (List Char) :=
  (afterNl (input.dropWhile whitespace)).orElse (fun _ =>
    (wsResult input).bind (fun rest => if rest.isEmpty then some rest else none))

private def blankAlts : List (List Expr) :=
  [[.opt (.ref "Ws" []), .ref "Nl" []], [.ref "Ws" [], .notPred .any]]

theorem generated_blank_line (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 7 + extra) (.ref "BlankLine" []) input =
      .ok (blankResult input) := by
  let inner := input.length + 5 + extra
  rw [show input.length + 7 + extra = inner + 1 + 1 by dsimp [inner]; omega]
  change recognizeEnv _ [] (inner + 1) (.choice blankAlts) input = _
  change runChoices (fun xs => runSequence (fun sc item rest =>
    recognizeEnv Generated.pegGrammar sc inner item rest) (fun _ _ _ => .ok none) [] xs input) blankAlts = _
  have optional := optional_ws [] input extra
  have spaces := ws [] input (extra + 1)
  rw [show input.length + 4 + (extra + 1) = inner by dsimp [inner]; omega] at spaces
  have newline (rest : List Char) : recognizeEnv Generated.pegGrammar [] inner (.ref "Nl" []) rest =
      .ok (afterNl rest) := by
    rw [show inner = (input.length + 1 + extra) + 4 by dsimp [inner]; omega]
    exact generated_nl_eval [] _ rest
  have eof (rest : List Char) : recognizeEnv Generated.pegGrammar [] inner (.notPred .any) rest =
      .ok (if rest.isEmpty then some rest else none) := by
    rw [show inner = (input.length + 3 + extra) + 2 by dsimp [inner]; omega]
    exact eof_lookahead _ [] _ rest
  change recognizeEnv _ [] inner _ _ = _ at optional
  cases nl : afterNl (input.dropWhile whitespace) with
  | some tail =>
      simp [blankAlts, blankResult, Option.orElse, nl, optional, newline, runChoices, foldChoice, runSequence, List.foldlM,
        Bind.bind, Except.bind, pure, Except.pure, Except.map]
  | none =>
      cases wsAt : wsResult input with
      | none =>
          simp [blankAlts, blankResult, Option.orElse, nl, wsAt, optional, newline, spaces, runChoices, foldChoice,
            runSequence, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]
      | some rest =>
          cases ended : rest.isEmpty <;>
            simp [blankAlts, blankResult, Option.orElse, nl, wsAt, ended, optional, newline, spaces, eof, runChoices,
              foldChoice, runSequence, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]

theorem generated_sp (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 7 + extra) (.ref "Sp" []) input =
      .ok (some (input.dropWhile whitespace)) := by
  rw [show input.length + 7 + extra = (input.length + 5 + extra) + 1 + 1 by omega]
  change recognizeEnv _ [] ((input.length + 5 + extra) + 1) (.choice [[.opt (.ref "Ws" [])]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (input.length + 5 + extra) item rest) (fun _ _ _ => .ok none) [] xs input) [[.opt (.ref "Ws" [])]] = _
  simp [optional_ws [] input extra, runChoices, foldChoice, runSequence, List.foldlM,
    Bind.bind, Except.bind, pure, Except.pure, Except.map]

theorem generated_eol (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 9 + extra) (.ref "EOL" []) input =
      .ok (match input.dropWhile whitespace with
        | [] => some [] | '\n' :: rest => some rest | _ :: _ => none) := by
  let inner := input.length + 7 + extra
  rw [show input.length + 9 + extra = inner + 1 + 1 by dsimp [inner]; omega]
  let endChoice := Expr.choice [[.ref "Nl" []], [.notPred .any]]
  change recognizeEnv _ [] (inner + 1) (.choice [[.ref "Sp" [], endChoice]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    inner item rest) (fun _ _ _ => .ok none) [] xs input) [[.ref "Sp" [], endChoice]] = _
  have endAt := generated_newline_or_eof [] (input.length + 1 + extra) (input.dropWhile whitespace)
  rw [show input.length + 1 + extra + 6 = inner by dsimp [inner]; omega] at endAt
  have sp := generated_sp [] input extra
  change recognizeEnv _ [] inner _ _ = _ at sp
  change recognizeEnv _ [] inner endChoice _ = _ at endAt
  cases suffix : input.dropWhile whitespace with
  | nil =>
      simp [runChoices, foldChoice, runSequence, List.foldlM, sp, suffix] at endAt ⊢
      rw [endAt]; rfl
  | cons c rest =>
      by_cases line : c = '\n' <;>
        simp [runChoices, foldChoice, runSequence, List.foldlM, sp, suffix, line] at endAt ⊢ <;>
        rw [endAt] <;> rfl

def eof (input : List Char) : Option (List Char) :=
  if input.isEmpty then some input else none

private def blankOrEof : Expr := .choice [[.ref "BlankLine" []], [.notPred .any]]

private theorem blank_or_eof (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 8 + extra) blankOrEof input =
      .ok ((blankResult input).orElse (fun _ => eof input)) := by
  let inner := input.length + 7 + extra
  rw [show input.length + 8 + extra = inner + 1 by dsimp [inner]; omega]
  change runChoices (fun xs => runSequence
    (fun sc item rest => recognizeEnv Generated.pegGrammar sc inner item rest)
    (fun _ _ _ => .ok none) env xs input) [[.ref "BlankLine" []], [.notPred .any]] = _
  have blank := generated_blank_line env input extra
  change recognizeEnv _ _ inner _ _ = _ at blank
  have endAt := eof_lookahead Generated.pegGrammar env (input.length + 5 + extra) input
  rw [show input.length + 5 + extra + 2 = inner by dsimp [inner]; omega] at endAt
  change _ = .ok (eof input) at endAt
  cases b : blankResult input <;> cases e : eof input <;>
    simp [runChoices, foldChoice, runSequence, List.foldlM, blank, endAt, b, e, Option.orElse,
      Bind.bind, Except.bind, pure, Except.pure, Except.map]

def paraResult (input : List Char) : Option (List Char) :=
  ((afterNl input).bind (fun rest => (blankResult rest).orElse (fun _ => eof rest))).orElse
    (fun _ => eof input)

private def paraAlts : List (List Expr) := [[.ref "Nl" [], blankOrEof], [.notPred .any]]

theorem generated_para_end (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 10 + extra) (.ref "ParaEnd" []) input =
      .ok (paraResult input) := by
  let inner := input.length + 8 + extra
  rw [show input.length + 10 + extra = inner + 1 + 1 by dsimp [inner]; omega]
  change recognizeEnv _ [] (inner + 1) (.choice paraAlts) input = _
  change runChoices (fun xs => runSequence
    (fun sc item rest => recognizeEnv Generated.pegGrammar sc inner item rest)
    (fun _ _ _ => .ok none) [] xs input) paraAlts = _
  have nl : recognizeEnv Generated.pegGrammar [] inner (.ref "Nl" []) input = .ok (afterNl input) := by
    rw [show inner = (input.length + 4 + extra) + 4 by dsimp [inner]; omega]
    exact generated_nl_eval [] _ input
  have endAt := eof_lookahead Generated.pegGrammar [] (input.length + 6 + extra) input
  rw [show input.length + 6 + extra + 2 = inner by dsimp [inner]; omega] at endAt
  change _ = .ok (eof input) at endAt
  cases first : afterNl input with
  | none =>
      cases last : eof input <;>
        simp [paraAlts, paraResult, nl, endAt, first, last, Option.orElse, runChoices, runSequence,
          foldChoice, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]
  | some rest =>
      have lengthEq : input.length = rest.length + 1 := by
        cases input with
        | nil => contradiction
        | cons c tail =>
            by_cases h : c = '\n'
            · subst c; simp [afterNl] at first; subst rest; rfl
            · simp [afterNl, h] at first
      have next := blank_or_eof [] rest (extra + 1)
      rw [show rest.length + 8 + (extra + 1) = inner by dsimp [inner]; omega] at next
      cases picked : blankResult rest <;> cases e : eof rest <;> cases last : eof input <;>
        simp [picked, e, Option.orElse] at next <;>
        simp [paraAlts, paraResult, nl, endAt, first, next, picked, e, last, Option.orElse, runChoices,
          runSequence, foldChoice, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map] <;> rfl

end LineBoundaryTotal
