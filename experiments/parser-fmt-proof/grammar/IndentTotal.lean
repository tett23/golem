import Generated

namespace IndentTotal

open PegModel

def expected : Nat → List Char → Option (List Char)
  | 0, input => some input
  | _ + 1, [] => none
  | n + 1, c :: rest => if c = ' ' then expected n rest else none

private def branches : List (List Expr) :=
  [[.semanticPred true " n == 0 "], [.lit " " "' '", .ref "Ind" ["n - 1"]]]

private theorem resolve (env : Params) (arg : String) (n fuel : Nat) (input : List Char)
    (value : integer env arg = some n) :
    recognizeEnv Generated.pegGrammar env (fuel + 1) (.ref "Ind" [arg]) input =
      recognizeEnv Generated.pegGrammar [("n", n)] fuel (.choice branches) input := by
  change (match [arg].mapM (integer env) with
    | none => Except.error "opaque argument for Ind"
    | some values => recognizeEnv Generated.pegGrammar (List.zip ["n"] values) fuel (.choice branches) input) = _
  simp [List.mapM, List.mapM.loop, value, branches]

private theorem decrement (n : Nat) : integer [("n", n + 1)] "n - 1" = some n := by
  change (if 1 ≤ n + 1 then some (n + 1 - 1) else none) = some n
  simp; omega

private theorem zeroTest (n fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("n", n)] (fuel + 1) (.semanticPred true " n == 0 ") input =
      .ok (if n = 0 then some input else none) := by
  change Except.ok (if (n == 0) == true then some input else none) = _
  simp

theorem generated_indent (n : Nat) (input : List Char) (env : Params) (arg : String) (extra : Nat)
    (value : integer env arg = some n) :
    recognizeEnv Generated.pegGrammar env (2 * n + 3 + extra) (.ref "Ind" [arg]) input =
      .ok (expected n input) := by
  induction n generalizing input env arg extra with
  | zero =>
      rw [show 2 * 0 + 3 + extra = (extra + 1) + 1 + 1 by omega, resolve env arg 0 _ input value]
      change runChoices (fun items => runSequence
        (fun scope item rest => recognizeEnv Generated.pegGrammar scope (extra + 1) item rest)
        (fun _ _ _ => .ok none) [("n", 0)] items input) branches = _
      simp [branches, runChoices, foldChoice, runSequence, zeroTest, List.foldlM, expected,
        Bind.bind, Except.bind, pure, Except.pure, Except.map]
  | succ n ih =>
      let base := 2 * n + 2 + extra
      rw [show 2 * (n + 1) + 3 + extra = (base + 1) + 1 + 1 by dsimp [base]; omega,
        resolve env arg (n + 1) _ input value]
      change runChoices (fun items => runSequence
        (fun scope item rest => recognizeEnv Generated.pegGrammar scope (base + 1) item rest)
        (fun _ _ _ => .ok none) [("n", n + 1)] items input) branches = _
      have recurse (rest : List Char) := ih rest [("n", n + 1)] "n - 1" extra (decrement n)
      rw [show 2 * n + 3 + extra = base + 1 by dsimp [base]; omega] at recurse
      cases input with
      | nil =>
          have lit : recognizeEnv Generated.pegGrammar [("n", n+1)] (base + 1) (.lit " " "' '") [] =
              .ok none := by rfl
          simp [branches, runChoices, foldChoice, runSequence, zeroTest, List.foldlM, expected,
            lit, Bind.bind, Except.bind, pure, Except.pure, Except.map]
      | cons c rest =>
          have lit : recognizeEnv Generated.pegGrammar [("n", n+1)] (base + 1) (.lit " " "' '") (c :: rest) =
              .ok (if c = ' ' then some rest else none) := by
            change Except.ok (if " ".toList.isPrefixOf (c :: rest) then some ((c :: rest).drop " ".toList.length) else none) = _
            by_cases h : c = ' '
            · subst c; simp [show " ".toList = [' '] by rfl, List.isPrefixOf]
            · have miss : (' ' == c) = false := by cases he : (' ' == c) <;> simp_all <;> exact h he.symm
              simp [show " ".toList = [' '] by rfl, List.isPrefixOf, miss, h]
          by_cases isSpace : c = ' '
          · subst c
            cases result : expected n rest <;>
              simp [branches, runChoices, foldChoice, runSequence, zeroTest, List.foldlM, expected,
                lit, recurse, result, Bind.bind, Except.bind, pure, Except.pure, Except.map]
          · simp [branches, runChoices, foldChoice, runSequence, zeroTest, List.foldlM, expected,
              lit, isSpace, Bind.bind, Except.bind, pure, Except.pure, Except.map]

end IndentTotal
