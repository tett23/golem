import LineBoundaryTotal

namespace ExpressionIdentTotal

open PegModel PegModelTest

private def leading := [(97, 122), (65, 90), (95, 95)]
private def continuing := [(97, 122), (65, 90), (48, 57), (95, 95)]
def starts (c : Char) := leading.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
def continues (c : Char) := continuing.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
private def first := Expr.charClass leading "[a-zA-Z_]"
private def next := Expr.charClass continuing "[a-zA-Z0-9_]"

def remainder : List Char → Option (List Char)
  | [] => none
  | c :: tail => if starts c then some (tail.dropWhile continues) else none

def lexeme : List Char → Option (List Char)
  | [] => none
  | c :: tail => if starts c then some (c :: tail.takeWhile continues) else none

theorem generated_expr_ident (env : Params) (input : List Char) (extra : Nat) :
    recognizeEnv Generated.pegGrammar env (input.length + 4 + extra) (.ref "ExprIdent" []) input =
      .ok (remainder input) := by
  let inner := input.length + 2 + extra
  rw [show input.length + 4 + extra = inner + 1 + 1 by dsimp [inner]; omega]
  change recognizeEnv _ [] (inner + 1) (.choice [[first, .star next]]) input = _
  change runChoices (fun xs => runSequence (fun sc item rest => recognizeEnv Generated.pegGrammar sc inner item rest)
    (fun _ _ _ => .ok none) [] xs input) [[first, .star next]] = _
  have head := class_total Generated.pegGrammar [] (input.length + 1 + extra) leading "[a-zA-Z_]" input
  rw [show input.length + 1 + extra + 1 = inner by dsimp [inner]; omega] at head
  cases input with
  | nil =>
      change recognizeEnv _ [] inner first [] = .ok none at head
      simp [head, remainder, runChoices, runSequence, foldChoice, List.foldlM, Bind.bind,
        Except.bind, pure, Except.pure, Except.map]
  | cons c tail =>
      change recognizeEnv _ [] inner first (c :: tail) = .ok (if starts c then some tail else none) at head
      have star := LineBoundaryTotal.star_class continuing "[a-zA-Z0-9_]" tail (extra+1)
      rw [show tail.length + 2 + (extra + 1) = inner by dsimp [inner]; omega] at star
      change recognizeEnv _ [] inner (.star next) tail = .ok (some (tail.dropWhile continues)) at star
      unfold first at head ⊢
      cases allowed : starts c <;>
        simp [head, star, allowed, remainder, runChoices, runSequence, foldChoice, List.foldlM,
          Bind.bind, Except.bind, pure, Except.pure, Except.map] <;> rfl

private theorem spelling (tail suffix : List Char) (valid : ∀ c ∈ tail, continues c = true)
    (boundary : ∀ c rest, suffix = c :: rest → continues c = false) :
    (tail ++ suffix).takeWhile continues = tail ∧ (tail ++ suffix).dropWhile continues = suffix := by
  induction tail with
  | nil =>
      cases suffix with
      | nil => decide
      | cons c cs => simp [List.takeWhile, List.dropWhile, boundary c cs rfl]
  | cons c cs ih =>
      have h := valid c (by simp)
      have rec := ih (fun x mem => valid x (by simp [mem]))
      simp [List.takeWhile, List.dropWhile, h, rec]

theorem I1_ident_round_trip (env : Params) (initial : Char) (tail suffix : List Char) (extra : Nat)
    (head : starts initial = true) (valid : ∀ c ∈ tail, continues c = true)
    (boundary : ∀ c rest, suffix = c :: rest → continues c = false) :
    let input := initial :: (tail ++ suffix)
    recognizeEnv Generated.pegGrammar env (input.length + 4 + extra) (.ref "ExprIdent" []) input =
      .ok (some suffix) ∧ lexeme input = some (initial :: tail) := by
  dsimp only
  rw [generated_expr_ident]
  have parts := spelling tail suffix valid boundary
  simp [remainder, lexeme, head, parts]

end ExpressionIdentTotal
