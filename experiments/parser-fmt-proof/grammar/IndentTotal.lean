import Generated

namespace IndentTotal

open PegModel

-- Exactly n spaces.
def spaces : Nat → List Char → Option (List Char)
  | 0, input => some input
  | _ + 1, [] => none
  | n + 1, c :: rest => if c = ' ' then spaces n rest else none

-- Ind(n) reads the spaces of the column of n: the parameter carries
-- fenceBit between ::: lines (root ADR 0459), which reads no space.
def expected (n : Nat) (input : List Char) : Option (List Char) :=
  spaces (n % fenceBit) input

private def branches : List (List Expr) :=
  [[.semanticPred true " col n == 0 "], [.lit " " "' '", .ref "Ind" ["n - 1"]]]

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

private theorem columnTest (n fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("n", n)] (fuel + 1) (.semanticPred true " col n == 0 ") input =
      .ok (if n % fenceBit = 0 then some input else none) := by
  change Except.ok (if (n % fenceBit == 0) == true then some input else none) = _
  simp

private theorem column_step (n m : Nat) (h : n % fenceBit = m + 1) :
    ∃ k, n = k + 1 ∧ k % fenceBit = m := by
  unfold fenceBit at *
  exact ⟨n - 1, by omega, by omega⟩

private theorem indent_column (m : Nat) : ∀ (n : Nat) (input : List Char) (env : Params) (arg : String)
    (extra : Nat), n % fenceBit = m → integer env arg = some n →
    recognizeEnv Generated.pegGrammar env (2 * m + 3 + extra) (.ref "Ind" [arg]) input =
      .ok (spaces m input) := by
  induction m with
  | zero =>
      intro n input env arg extra column value
      rw [show 2 * 0 + 3 + extra = (extra + 1) + 1 + 1 by omega, resolve env arg n _ input value]
      change runChoices (fun items => runSequence
        (fun scope item rest => recognizeEnv Generated.pegGrammar scope (extra + 1) item rest)
        (fun _ _ _ => .ok none) [("n", n)] items input) branches = _
      simp [branches, runChoices, foldChoice, runSequence, columnTest, column, List.foldlM, spaces,
        Bind.bind, Except.bind, pure, Except.pure, Except.map]
  | succ m ih =>
      intro n input env arg extra column value
      obtain ⟨k, hn, hk⟩ := column_step n m column
      subst hn
      let base := 2 * m + 2 + extra
      rw [show 2 * (m + 1) + 3 + extra = (base + 1) + 1 + 1 by dsimp [base]; omega,
        resolve env arg (k + 1) _ input value]
      change runChoices (fun items => runSequence
        (fun scope item rest => recognizeEnv Generated.pegGrammar scope (base + 1) item rest)
        (fun _ _ _ => .ok none) [("n", k + 1)] items input) branches = _
      have recurse (rest : List Char) := ih k rest [("n", k + 1)] "n - 1" extra hk (decrement k)
      rw [show 2 * m + 3 + extra = base + 1 by dsimp [base]; omega] at recurse
      cases input with
      | nil =>
          have lit : recognizeEnv Generated.pegGrammar [("n", k+1)] (base + 1) (.lit " " "' '") [] =
              .ok none := by rfl
          simp [branches, runChoices, foldChoice, runSequence, columnTest, column, List.foldlM, spaces,
            lit, Bind.bind, Except.bind, pure, Except.pure, Except.map]
      | cons c rest =>
          have lit : recognizeEnv Generated.pegGrammar [("n", k+1)] (base + 1) (.lit " " "' '") (c :: rest) =
              .ok (if c = ' ' then some rest else none) := by
            change Except.ok (if " ".toList.isPrefixOf (c :: rest) then some ((c :: rest).drop " ".toList.length) else none) = _
            by_cases h : c = ' '
            · subst c; simp [show " ".toList = [' '] by rfl, List.isPrefixOf]
            · have miss : (' ' == c) = false := by cases he : (' ' == c) <;> simp_all <;> exact h he.symm
              simp [show " ".toList = [' '] by rfl, List.isPrefixOf, miss, h]
          by_cases isSpace : c = ' '
          · subst c
            cases result : spaces m rest <;>
              simp [branches, runChoices, foldChoice, runSequence, columnTest, column, List.foldlM, spaces,
                lit, recurse, result, Bind.bind, Except.bind, pure, Except.pure, Except.map]
          · simp [branches, runChoices, foldChoice, runSequence, columnTest, column, List.foldlM, spaces,
              lit, isSpace, Bind.bind, Except.bind, pure, Except.pure, Except.map]

theorem generated_indent (n : Nat) (input : List Char) (env : Params) (arg : String) (extra : Nat)
    (value : integer env arg = some n) :
    recognizeEnv Generated.pegGrammar env (2 * n + 3 + extra) (.ref "Ind" [arg]) input =
      .ok (expected n input) := by
  have small : n % fenceBit ≤ n := Nat.mod_le n fenceBit
  rw [show 2 * n + 3 + extra = 2 * (n % fenceBit) + 3 + (extra + 2 * (n - n % fenceBit)) by omega]
  exact indent_column (n % fenceBit) n input env arg _ rfl value

theorem spaces_length (n : Nat) (input rest : List Char)
    (ok : spaces n input = some rest) : rest.length ≤ input.length := by
  induction n generalizing input with
  | zero => simp [spaces] at ok; subst rest; exact Nat.le_refl _
  | succ n ih =>
      cases input with
      | nil => simp [spaces] at ok
      | cons c tail =>
          by_cases h : c = ' '
          · simp [spaces, h] at ok
            exact Nat.le_succ_of_le (ih tail ok)
          · simp [spaces, h] at ok

theorem expected_length (n : Nat) (input rest : List Char)
    (ok : expected n input = some rest) : rest.length ≤ input.length :=
  spaces_length (n % fenceBit) input rest ok

-- Below fenceBit the column is the parameter itself.
theorem expected_small (n : Nat) (input : List Char) (small : n < fenceBit) :
    expected n input = spaces n input := by
  simp [expected, Nat.mod_eq_of_lt small]

end IndentTotal
