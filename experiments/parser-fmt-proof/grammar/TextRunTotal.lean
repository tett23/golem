import PrefixBoundaryTotal

namespace TextRunTotal

open PegModel PegModelTest

structure Run where
  ranges : List (Nat × Nat)
  written : String
  stopAtNumber : Bool

def numberAt (input : List Char) := (PrefixBoundaryTotal.classExpected "##" [(48, 57)] input).isSome
def forbidden (r : Run) (c : Char) := r.ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
def allowed (r : Run) : List Char → Bool
  | [] => false
  | c :: cs => !(forbidden r c || "%%".toList.isPrefixOf (c :: cs) || (r.stopAtNumber && numberAt (c :: cs)))

private def items (r : Run) : List Expr :=
  [.notPred (.charClass r.ranges r.written), .notPred (.lit "%%" "'%%'")] ++
  (if r.stopAtNumber then [.notPred (.ref "NumberOpen" [])] else []) ++ [.any]

private def child (r : Run) := Expr.choice [items r]

private theorem step (r : Run) (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar [] (fuel + 5) (child r) input =
      .ok (if allowed r input then input.tail? else none) := by
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 4) item rest) _ [] xs input) [items r] = _
  have cls := not_class Generated.pegGrammar [] (fuel + 2) r.ranges r.written input
  have delim := not_literal_total Generated.pegGrammar [] (fuel + 2) "%%" "'%%'" input
  have num : recognizeEnv Generated.pegGrammar [] (fuel + 4) (.notPred (.ref "NumberOpen" [])) input =
      .ok (if numberAt input then none else some input) := by
    change (match recognizeEnv Generated.pegGrammar [] (fuel + 3) (.ref "NumberOpen" []) input with
      | Except.error reason => if isLabelFailure reason then Except.ok (some input) else Except.error reason
      | Except.ok none => Except.ok (some input)
      | Except.ok (some _) => Except.ok none) = _
    rw [PrefixBoundaryTotal.generated_number_open]
    unfold numberAt
    cases PrefixBoundaryTotal.classExpected "##" [(48, 57)] input <;> rfl
  have any : recognizeEnv Generated.pegGrammar [] (fuel + 4) .any input = .ok input.tail? := by cases input <;> rfl
  cases input with
  | nil =>
      cases mode : r.stopAtNumber <;>
        simp [child, items, allowed, mode, cls, delim, any, num, numberAt, PrefixBoundaryTotal.classExpected,
          runChoices, runSequence, foldChoice, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map] <;> rfl
  | cons c cs =>
      change _ = .ok (if forbidden r c then none else some (c :: cs)) at cls
      cases mode : r.stopAtNumber <;> cases cl : forbidden r c <;>
        cases de : "%%".toList.isPrefixOf (c :: cs) <;> cases no : numberAt (c :: cs) <;>
        simp [items, allowed, cl, de, no, mode, cls, delim, any, num, runChoices, runSequence, foldChoice,
          List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]

def suffix (r : Run) : List Char → List Char
  | [] => []
  | c :: cs => if allowed r (c :: cs) then suffix r cs else c :: cs

def result (r : Run) : List Char → Option (List Char)
  | [] => none
  | c :: cs => if allowed r (c :: cs) then some (suffix r cs) else none

private theorem star (r : Run) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 6 + extra) (.star (child r)) input =
      .ok (some (suffix r input)) := by
  induction input with
  | nil =>
      rw [show ([] : List Char).length + 6 + extra = extra + 5 + 1 by simp; omega]
      conv => lhs; unfold recognizeEnv
      simp [step, allowed, suffix]; rfl
  | cons c cs ih =>
      let inner := cs.length + 6 + extra
      rw [show (c :: cs).length + 6 + extra = inner + 1 by dsimp [inner]; omega]
      have hit := step r (c :: cs) (cs.length + 1 + extra)
      rw [show cs.length + 1 + extra + 5 = inner by dsimp [inner]; omega] at hit
      change recognizeEnv _ [] inner _ cs = _ at ih
      conv => lhs; unfold recognizeEnv
      cases a : allowed r (c :: cs) <;> simp [hit, a, ih, suffix, Id.run]

private theorem plus (r : Run) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar [] (input.length + 6 + extra) (.plus (child r)) input =
      .ok (result r input) := by
  cases input with
  | nil =>
      rw [show ([] : List Char).length + 6 + extra = extra + 5 + 1 by simp; omega]
      conv => lhs; unfold recognizeEnv
      simp [step, allowed, result]; rfl
  | cons c cs =>
      let inner := cs.length + 6 + extra
      rw [show (c :: cs).length + 6 + extra = inner + 1 by dsimp [inner]; omega]
      have hit := step r (c :: cs) (cs.length + 1 + extra)
      rw [show cs.length + 1 + extra + 5 = inner by dsimp [inner]; omega] at hit
      have tail := star r cs extra
      change recognizeEnv _ [] inner _ cs = _ at tail
      conv => lhs; unfold recognizeEnv
      cases a : allowed r (c :: cs) <;> simp [hit, a, tail, result, Id.run]

inductive TextKind where
  | prose | slot | cell | number

def TextKind.ruleName : TextKind → String
  | .prose => "Text" | .slot => "SlotText" | .cell => "CellText" | .number => "NumberBody"

def TextKind.run : TextKind → Run
  | .prose => ⟨[(91, 91), (92, 92), (10, 10)], "[\\[\\\\\\n]", true⟩
  | .slot => ⟨[(91, 91), (92, 92), (10, 10), (124, 124), (93, 93)], "[\\[\\\\\\n|\\]]", true⟩
  | .cell => ⟨[(91, 91), (92, 92), (10, 10), (124, 124)], "[\\[\\\\\\n|]", true⟩
  | .number => ⟨[(35, 35), (10, 10), (91, 91), (93, 93), (124, 124), (92, 92)],
      "[#\\n\\[\\]|\\\\]", false⟩

theorem generated_text_run (kind : TextKind) (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 8 + extra) (.ref kind.ruleName []) input =
      .ok (result kind.run input) := by
  let inner := input.length + 6 + extra
  rw [show input.length + 8 + extra = inner + 1 + 1 by dsimp [inner]; omega]
  have expand : recognizeEnv Generated.pegGrammar env (inner + 1 + 1) (.ref kind.ruleName []) input =
      recognizeEnv Generated.pegGrammar [] (inner + 1) (.choice [[.plus (child kind.run)]]) input := by
    cases kind <;> rfl
  rw [expand]
  change runChoices (fun xs => runSequence
    (fun sc item rest => recognizeEnv Generated.pegGrammar sc inner item rest)
    (fun _ _ _ => .ok none) [] xs input) [[.plus (child kind.run)]] = _
  have body := plus kind.run input extra
  change recognizeEnv _ [] inner _ input = _ at body
  cases outcome : result kind.run input <;>
    simp [body, outcome, runChoices, runSequence, foldChoice, List.foldlM, Bind.bind,
      Except.bind, pure, Except.pure, Except.map]

def afterMark (input : List Char) : Option (List Char) :=
  if "##".toList.isPrefixOf input then some (input.drop 2) else none

private theorem number_mark (env : Params) (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar env (fuel + 3) (.ref "NumberMark" []) input =
      .ok (afterMark input) := by
  change recognizeEnv _ [] (fuel + 2) (.choice [[.lit "##" "'##'"]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    (fuel + 1) item rest) (fun _ _ _ => .ok none) [] xs input) [[.lit "##" "'##'"]] = _
  simp only [runChoices, foldChoice, List.foldlM]
  rw [sequence_literal_total Generated.pegGrammar [] _ fuel "##" "'##'" input]
  rfl

private theorem optional_mark (input : List Char) (fuel : Nat) :
    recognizeEnv Generated.pegGrammar [] (fuel + 4) (.opt (.ref "NumberMark" [])) input =
      .ok (some ((afterMark input).getD input)) := by
  change (match recognizeEnv Generated.pegGrammar [] (fuel + 3) (.ref "NumberMark" []) input with
    | Except.error reason => Except.error reason
    | Except.ok none => Except.ok (some input)
    | Except.ok hit => Except.ok hit) = _
  rw [number_mark]
  cases afterMark input <;> rfl

def shorthandResult (input : List Char) : Option (List Char) := do
  if !numberAt input then none else
    let first ← afterMark input
    let remaining ← result TextKind.number.run first
    some ((afterMark remaining).getD remaining)

private def shorthandItems : List Expr :=
  [.andPred (.ref "NumberOpen" []), .ref "NumberMark" [], .ref "NumberBody" [], .opt (.ref "NumberMark" [])]

theorem generated_shorthand (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 10 + extra) (.ref "NumberShorthand" []) input =
      .ok (shorthandResult input) := by
  let inner := input.length + 8 + extra
  rw [show input.length + 10 + extra = inner + 1 + 1 by dsimp [inner]; omega]
  change recognizeEnv _ [] (inner + 1) (.choice [shorthandItems]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc
    inner item rest) (fun _ _ _ => .ok none) [] xs input) [shorthandItems] = _
  have look : recognizeEnv Generated.pegGrammar [] inner (.andPred (.ref "NumberOpen" [])) input =
      .ok (if numberAt input then some input else none) := by
    rw [show inner = (input.length + 4 + extra) + 3 + 1 by dsimp [inner]; omega]
    change (match recognizeEnv Generated.pegGrammar [] ((input.length + 4 + extra) + 3) (.ref "NumberOpen" []) input with
      | Except.error reason => if isLabelFailure reason then Except.ok none else Except.error reason
      | Except.ok none => Except.ok none
      | Except.ok (some _) => Except.ok (some input)) = _
    rw [PrefixBoundaryTotal.generated_number_open]
    unfold numberAt
    cases PrefixBoundaryTotal.classExpected "##" [(48, 57)] input <;> rfl
  have first := number_mark [] input (input.length + 5 + extra)
  rw [show input.length + 5 + extra + 3 = inner by dsimp [inner]; omega] at first
  have closing (rest : List Char) := optional_mark rest (input.length + 4 + extra)
  simp only [show input.length + 4 + extra + 4 = inner by dsimp [inner]; omega] at closing
  cases opening : numberAt input with
  | false =>
      simp [shorthandItems, shorthandResult, opening, look, runChoices, runSequence, foldChoice,
        List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]
  | true =>
      cases mark : afterMark input with
      | none =>
          simp [shorthandItems, shorthandResult, opening, look, first, mark, runChoices, runSequence,
            foldChoice, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]
      | some tail =>
          have bound : tail.length ≤ input.length := by
            unfold afterMark at mark
            split at mark
            · have eq := Option.some.inj mark
              rw [← eq]; simp; omega
            · contradiction
          have parsed := generated_text_run .number [] tail (input.length - tail.length + extra)
          rw [show tail.length + 8 + (input.length - tail.length + extra) = inner by dsimp [inner]; omega] at parsed
          change recognizeEnv _ [] inner (.ref "NumberBody" []) tail = _ at parsed
          cases body : result TextKind.number.run tail <;>
            simp [shorthandItems, shorthandResult, opening, look, first, mark, parsed, body, closing,
              runChoices, runSequence, foldChoice, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]

end TextRunTotal
