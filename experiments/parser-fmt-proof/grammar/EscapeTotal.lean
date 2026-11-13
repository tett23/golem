import PegModelTest

open PegModelTest
set_option maxHeartbeats 1000000

namespace EscapeTotal

def expected (value : String) (ranges : List (Nat × Nat))
    (input : List Char) : Option (List Char) :=
  if value.toList.isPrefixOf input then
    match input.drop value.toList.length with
    | [] => none
    | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
      then none else some rest
  else none

theorem literal_not_class_any (grammar : PegModel.Grammar) (env : PegModel.Params)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (value written classWritten : String) (ranges : List (Nat × Nat))
    (input : List Char) (fuel : Nat) :
    PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 2) item rest)
      boundLength env
        [.lit value written, .notPred (.charClass ranges classWritten), .any] input =
      .ok (expected value ranges input) := by
  have literal := PegModelTest.literal_total grammar env (fuel + 1) value written input
  have literalFuel : fuel + 1 + 1 = fuel + 2 := by omega
  rw [literalFuel] at literal
  cases hp : value.toList.isPrefixOf input with
  | false => simp [PegModel.runSequence, literal, hp, expected] <;> rfl
  | true =>
      have notClass := PegModelTest.not_class grammar env fuel ranges classWritten
        (input.drop value.toList.length)
      cases rest : input.drop value.toList.length with
      | nil =>
          rw [rest] at notClass
          have anyAt : PegModel.recognizeEnv grammar env (fuel + 2) .any [] = .ok none := by rfl
          simp [PegModel.runSequence, literal, notClass, anyAt, hp, expected, rest] <;> rfl
      | cons c tail =>
          rw [rest] at notClass
          have anyAt : PegModel.recognizeEnv grammar env (fuel + 2) .any (c :: tail) =
              .ok (some tail) := by rfl
          cases hc : ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) <;>
            simp [PegModel.runSequence, literal, notClass, anyAt, hp, expected, rest, hc] <;> rfl

def escapeItems : List PegModel.Expr :=
  [.lit "\\" "'\\\\'", .notPred (.charClass [(10, 10)] "[\\n]"), .any]

theorem generated_escape (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 4)
      (.ref "Escape" []) input =
      .ok (expected "\\" [(10, 10)] input) := by
  have refFuel : fuel + 4 = (fuel + 3) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
    (.choice [escapeItems]) input = _
  have choiceFuel : fuel + 3 = (fuel + 2) + 1 := by omega
  rw [choiceFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 2) item rest)
      _ [] items input) [escapeItems] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  rw [show escapeItems = [.lit "\\" "'\\\\'",
    .notPred (.charClass [(10, 10)] "[\\n]"), .any] from rfl]
  rw [literal_not_class_any Generated.pegGrammar [] _ "\\" "'\\\\'"
    "[\\n]" [(10, 10)] input fuel]
  rfl

theorem generated_reserved_body_escape_shape :
    ((Generated.pegGrammar.rules.find? (fun rule => rule.name == "ReservedBracketBody")).map
      (fun rule => match rule.alts with
        | [alt] => match alt.items with
          | [.star (.choice (first :: _))] => first
          | _ => []
        | _ => [])) = some escapeItems := by rfl

theorem generated_reserved_body_escape (input : List Char) (fuel : Nat) :
    PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 2) item rest)
      (fun _ _ _ => .ok none) [] escapeItems input =
      .ok (expected "\\" [(10, 10)] input) := by
  simpa [escapeItems] using literal_not_class_any Generated.pegGrammar []
    (fun _ _ _ => .ok none) "\\" "'\\\\'" "[\\n]" [(10, 10)] input fuel

example : PegModel.recognizeEnv Generated.pegGrammar [] 4
    (.ref "Escape" []) "\\x".toList = .ok (some []) := by
  simpa using generated_escape "\\x".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 4
    (.ref "Escape" []) "\\\n".toList = .ok none := by
  simpa using generated_escape "\\\n".toList 0

def reservedOrdinary : List PegModel.Expr :=
  [.notPred (.charClass [(91, 91), (93, 93), (92, 92), (10, 10)] "[\\[\\]\\\\\\n]"), .any]

theorem generated_reserved_body_ordinary_shape :
    ((Generated.pegGrammar.rules.find? (fun rule => rule.name == "ReservedBracketBody")).bind
      (fun rule => match rule.alts with
        | [alt] => match alt.items with
          | [.star (.choice alts)] => alts[3]?
          | _ => none
        | _ => none)) = some reservedOrdinary := by rfl

theorem generated_reserved_body_ordinary (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 4)
      (.choice [reservedOrdinary]) input =
      .ok (match input with
        | [] => none
        | c :: rest => if [(91, 91), (93, 93), (92, 92), (10, 10)].any
            (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) then none else some rest) := by
  exact PegModelTest.nonclass_any _ _ _ _ _ _

end EscapeTotal
