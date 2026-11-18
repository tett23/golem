import IndentTotal
import ThrowingPrefixTotal

namespace IndentedLabelTotal

open PegModel

def items (marker written label : String) : List Expr :=
  [.ref "Ind" ["ind"], .andPred (.lit marker written),
   .label (.choice [[.semanticPred true " False ", .lit marker written]]) label]

def outcome (n : Nat) (marker label : String) (input : List Char) : ParseResult :=
  match IndentTotal.expected n input with
  | none => .ok none
  | some rest => if marker.toList.isPrefixOf rest then .error ("label: " ++ label) else .ok none

theorem after_indent (n extra : Nat) (marker written label : String) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind", n)] (2*n + 5 + extra)
      (.choice [items marker written label]) input = outcome n marker label input := by
  let fuel := 2*n + 4 + extra
  have ind := IndentTotal.generated_indent n input [("ind", n)] "ind" (extra+1) (by rfl)
  rw [show 2*n + 3 + (extra+1) = fuel by dsimp [fuel]; omega] at ind
  rw [show 2*n + 5 + extra = fuel + 1 by dsimp [fuel]; omega]
  change runChoices (fun xs => runSequence
    (fun scope item rest => recognizeEnv Generated.pegGrammar scope fuel item rest)
    (fun _ _ _ => .ok none) [("ind", n)] xs input) [items marker written label] = _
  cases found : IndentTotal.expected n input with
  | none =>
      simp [items, outcome, found, runChoices, runSequence, foldChoice, List.foldlM, ind,
        Bind.bind, Except.bind, pure, Except.pure, Except.map]
  | some rest =>
      have look := ThrowingPrefixTotal.literal_lookahead_total Generated.pegGrammar [("ind", n)]
        (2*n + 2 + extra) marker written rest
      have thrown := ThrowingPrefixTotal.false_then_literal_label Generated.pegGrammar [("ind", n)]
        (2*n + extra) marker written label rest
      rw [show 2*n + 2 + extra + 2 = fuel by dsimp [fuel]; omega] at look
      rw [show 2*n + extra + 4 = fuel by dsimp [fuel]; omega] at thrown
      cases hit : marker.toList.isPrefixOf rest <;>
        simp [items, outcome, found, hit, runChoices, runSequence, foldChoice, List.foldlM, ind,
          look, thrown, Bind.bind, Except.bind, pure, Except.pure, Except.map]

theorem generated_indented_labels (name marker written label arg : String)
    (selected : (name = "OrphanDef" ∧ marker = "=:" ∧ written = "'=:'" ∧ label = "def_orphan") ∨
      (name = "ReservedBlock" ∧ marker = "@!" ∧ written = "'@!'" ∧ label = "reserved"))
    (env : Params) (n extra : Nat) (input : List Char) (value : integer env arg = some n) :
    recognizeEnv Generated.pegGrammar env (2*n + 6 + extra) (.ref name [arg]) input =
      outcome n marker label input := by
  have args : [arg].mapM (integer env) = some [n] := by simp [List.mapM, List.mapM.loop, value]
  rw [show 2*n + 6 + extra = (2*n + 5 + extra) + 1 by omega]
  rcases selected with ⟨rfl, rfl, rfl, rfl⟩ | ⟨rfl, rfl, rfl, rfl⟩
  all_goals
    change (match [arg].mapM (integer env) with
      | none => Except.error _
      | some vs => recognizeEnv Generated.pegGrammar (List.zip ["ind"] vs) (2*n + 5 + extra)
          (.choice [items _ _ _]) input) = _
    rw [args]
    exact after_indent _ _ _ _ _ _

private def spaces : List (Nat × Nat) := [(32, 32), (9, 9)]
private def spaceClass := Expr.charClass spaces "[ \\t]"
private def spaceHit (c : Char) := spaces.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
private def indentError := Expr.label (.choice [[.semanticPred true " False ", spaceClass]]) "indent"
private def badItems : List Expr := [.ref "Ind" ["ind"], .andPred spaceClass, indentError]

def badOutcome (n : Nat) (input : List Char) : ParseResult :=
  match IndentTotal.expected n input with
  | some (c :: _) => if spaceHit c then .error "label: indent" else .ok none
  | _ => .ok none

theorem generated_bad_indent (env : Params) (arg : String) (n extra : Nat) (input : List Char)
    (value : integer env arg = some n) :
    recognizeEnv Generated.pegGrammar env (2*n + 6 + extra) (.ref "BadIndent" [arg]) input =
      badOutcome n input := by
  let fuel := 2*n + 4 + extra
  have args : [arg].mapM (integer env) = some [n] := by simp [List.mapM, List.mapM.loop, value]
  rw [show 2*n + 6 + extra = fuel + 1 + 1 by dsimp [fuel]; omega]
  change (match [arg].mapM (integer env) with
    | none => Except.error "opaque argument for BadIndent"
    | some vs => recognizeEnv Generated.pegGrammar (List.zip ["ind"] vs) (fuel + 1) (.choice [badItems]) input) = _
  rw [args]
  let scope := [("ind", n)]
  change runChoices (fun xs => runSequence (fun e item rest => recognizeEnv Generated.pegGrammar e fuel item rest)
    (fun _ _ _ => .ok none) scope xs input) [badItems] = _
  have ind := IndentTotal.generated_indent n input scope "ind" (extra+1) (by rfl)
  rw [show 2*n + 3 + (extra+1) = fuel by dsimp [fuel]; omega] at ind
  cases found : IndentTotal.expected n input with
  | none =>
      simp [badItems, badOutcome, ind, found, runChoices, runSequence, foldChoice, List.foldlM,
        Bind.bind, Except.bind, pure, Except.pure, Except.map]
  | some rest =>
      have look := PegModelTest.class_lookahead Generated.pegGrammar scope
        (2*n + 1 + extra) spaces "[ \\t]" rest
      rw [show 2*n + 1 + extra + 3 = fuel by dsimp [fuel]; omega] at look
      have label : recognizeEnv Generated.pegGrammar scope fuel indentError rest = .error "label: indent" := by
        rw [show fuel = (2*n + extra) + 4 by dsimp [fuel]; omega]
        exact label_of_miss _ _ _ _ _ _ (by rfl)
      cases rest with
      | nil =>
          change recognizeEnv _ _ fuel (.andPred spaceClass) [] = .ok none at look
          simp [badItems, badOutcome, ind, found, look, runChoices, runSequence, foldChoice, List.foldlM,
            Bind.bind, Except.bind, pure, Except.pure, Except.map]
      | cons c tail =>
          change recognizeEnv _ _ fuel (.andPred spaceClass) (c :: tail) =
            .ok (if spaceHit c then some (c :: tail) else none) at look
          cases hit : spaceHit c <;>
            simp [badItems, badOutcome, ind, found, look, hit, label, runChoices, runSequence,
              foldChoice, List.foldlM, Bind.bind, Except.bind, pure, Except.pure, Except.map]

end IndentedLabelTotal
