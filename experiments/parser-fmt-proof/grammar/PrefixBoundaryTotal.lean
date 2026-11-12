import PegModelTest

open PegModelTest
set_option maxHeartbeats 1000000

namespace PrefixBoundaryTotal

def classExpected (value : String) (ranges : List (Nat × Nat))
    (input : List Char) : Option (List Char) :=
  if value.toList.isPrefixOf input then
    match input.drop value.toList.length with
    | [] => none
    | c :: rest => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
      then some rest else none
  else none

theorem literal_class_sequence (grammar : PegModel.Grammar) (env : PegModel.Params)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (value written classWritten : String) (ranges : List (Nat × Nat))
    (input : List Char) (fuel : Nat) :
    PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 1) item rest)
      boundLength env [.lit value written, .charClass ranges classWritten] input =
      .ok (classExpected value ranges input) := by
  have literal := PegModelTest.literal_total grammar env fuel value written input
  cases hp : value.toList.isPrefixOf input with
  | false => simp [PegModel.runSequence, literal, hp, classExpected] <;> rfl
  | true =>
      have classHit := PegModelTest.class_total grammar env fuel ranges classWritten
        (input.drop value.toList.length)
      cases rest : input.drop value.toList.length with
      | nil =>
          rw [rest] at classHit
          simp [PegModel.runSequence, literal, classHit, hp, classExpected, rest] <;> rfl
      | cons c tail =>
          rw [rest] at classHit
          cases hc : ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) <;>
            simp [PegModel.runSequence, literal, classHit, hp, classExpected, rest, hc] <;> rfl

def boundaryExpected (value : String) (ranges : List (Nat × Nat))
    (input : List Char) : Option (List Char) :=
  if value.toList.isPrefixOf input then
    let rest := input.drop value.toList.length
    match rest with
    | [] => some []
    | c :: _ => if ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi)
      then none else some rest
  else none

theorem literal_not_class_sequence (grammar : PegModel.Grammar) (env : PegModel.Params)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (value written classWritten : String) (ranges : List (Nat × Nat))
    (input : List Char) (fuel : Nat) :
    PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 2) item rest)
      boundLength env [.lit value written, .notPred (.charClass ranges classWritten)] input =
      .ok (boundaryExpected value ranges input) := by
  have literal := PegModelTest.literal_total grammar env (fuel + 1) value written input
  have fuelEq : fuel + 1 + 1 = fuel + 2 := by omega
  rw [fuelEq] at literal
  cases hp : value.toList.isPrefixOf input with
  | false => simp [PegModel.runSequence, literal, hp, boundaryExpected] <;> rfl
  | true =>
      have classMiss := PegModelTest.not_class grammar env fuel ranges classWritten
        (input.drop value.toList.length)
      cases rest : input.drop value.toList.length with
      | nil =>
          rw [rest] at classMiss
          simp [PegModel.runSequence, literal, classMiss, hp, boundaryExpected, rest] <;> rfl
      | cons c tail =>
          rw [rest] at classMiss
          cases hc : ranges.any (fun (lo, hi) => lo ≤ c.toNat && c.toNat ≤ hi) <;>
            simp [PegModel.runSequence, literal, classMiss, hp, boundaryExpected, rest, hc] <;> rfl

theorem generated_number_open (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
      (.ref "NumberOpen" []) input =
      .ok (classExpected "##" [(48, 57)] input) := by
  have refFuel : fuel + 3 = (fuel + 2) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 2)
    (.choice [[.lit "##" "'##'", .charClass [(48, 57)] "[0-9]"]]) input = _
  have choiceFuel : fuel + 2 = (fuel + 1) + 1 := by omega
  rw [choiceFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 1) item rest)
      _ [] items input)
    [[.lit "##" "'##'", .charClass [(48, 57)] "[0-9]"]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  rw [literal_class_sequence Generated.pegGrammar [] _ "##" "'##'" "[0-9]" [(48, 57)] input fuel]
  rfl

theorem generated_set_ident (input : List Char) (fuel : Nat) :
    PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 4)
      (.ref "SetIdent" []) input =
      .ok (boundaryExpected "set" [(97, 122), (48, 57), (45, 45)] input) := by
  have refFuel : fuel + 4 = (fuel + 3) + 1 := by omega
  rw [refFuel]
  change PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3)
    (.choice [[.lit "set" "'set'",
      .notPred (.charClass [(97, 122), (48, 57), (45, 45)] "[a-z0-9\\-]")]]) input = _
  have choiceFuel : fuel + 3 = (fuel + 2) + 1 := by omega
  rw [choiceFuel]
  change PegModel.runChoices
    (fun items => PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv Generated.pegGrammar scope (fuel + 2) item rest)
      _ [] items input)
    [[.lit "set" "'set'",
      .notPred (.charClass [(97, 122), (48, 57), (45, 45)] "[a-z0-9\\-]")]] = _
  simp only [PegModel.runChoices, PegModel.foldChoice, List.foldlM]
  rw [literal_not_class_sequence Generated.pegGrammar [] _ "set" "'set'"
    "[a-z0-9\\-]" [(97, 122), (48, 57), (45, 45)] input fuel]
  rfl

example : PegModel.recognizeEnv Generated.pegGrammar [] 3
    (.ref "NumberOpen" []) "##7!".toList = .ok (some "!".toList) := by
  simpa using generated_number_open "##7!".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 3
    (.ref "NumberOpen" []) "##x".toList = .ok none := by
  simpa using generated_number_open "##x".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 4
    (.ref "SetIdent" []) "set=".toList = .ok (some "=".toList) := by
  simpa using generated_set_ident "set=".toList 0

example : PegModel.recognizeEnv Generated.pegGrammar [] 4
    (.ref "SetIdent" []) "setx".toList = .ok none := by
  simpa using generated_set_ident "setx".toList 0

end PrefixBoundaryTotal
