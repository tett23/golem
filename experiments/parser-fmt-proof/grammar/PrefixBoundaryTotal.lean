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

inductive Marker where
  | literal (value written : String)
  | followedBy (value written : String) (ranges : List (Nat × Nat)) (classWritten : String)

def Marker.items : Marker → List PegModel.Expr
  | .literal value written => [.lit value written]
  | .followedBy value written ranges cls => [.lit value written, .charClass ranges cls]

def Marker.consume (input : List Char) : Marker → Option (List Char)
  | .literal value _ =>
      if value.toList.isPrefixOf input then some (input.drop value.toList.length) else none
  | .followedBy value _ ranges _ => classExpected value ranges input

theorem marker_sequence (marker : Marker) (grammar : PegModel.Grammar) (env : PegModel.Params)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat))
    (input : List Char) (fuel : Nat) :
    PegModel.runSequence
      (fun scope item rest => PegModel.recognizeEnv grammar scope (fuel + 1) item rest)
      boundLength env marker.items input = .ok (marker.consume input) := by
  cases marker with
  | literal value written => exact sequence_literal_total grammar env boundLength fuel value written input
  | followedBy value written ranges cls =>
      exact literal_class_sequence grammar env boundLength value written cls ranges input fuel

private def blockMarkers : List (Nat × Marker) :=
  [(1, .followedBy "-" "'-'" [(32, 32), (9, 9)] "[ \\t]"),
   (2, .followedBy "+" "'+'" [(32, 32), (9, 9)] "[ \\t]"),
   (3, .followedBy "=" "'='" [(32, 32), (9, 9), (58, 58)] "[ \\t:]"),
   (4, .literal "|" "'|'"), (5, .literal "```" "'```'"),
   (7, .followedBy "@" "'@'" [(97, 122)] "[a-z]"), (8, .literal "@!" "'@!'")]

theorem generated_block_marker_shapes :
    ((Generated.pegGrammar.rules.find? (fun r => r.name == "BlockStart")).map
      (fun r => blockMarkers.map (fun entry => r.alts[entry.1]?.map PegModel.Alt.items))) =
      some (blockMarkers.map (fun entry => some entry.2.items)) := by rfl

private def headingStartItems : List PegModel.Expr :=
  [.notPred (.ref "NumberOpen" []), .lit "#" "'#'"]

theorem generated_heading_start_shape :
    ((Generated.pegGrammar.rules.find? (fun r => r.name == "BlockStart")).bind
      (fun r => r.alts[0]?.map PegModel.Alt.items)) = some headingStartItems := by rfl

theorem heading_start_sequence (input : List Char) (fuel : Nat)
    (boundLength : PegModel.Params → PegModel.Expr → List Char → Except String (Option Nat)) :
    PegModel.runSequence
      (fun sc e rest => PegModel.recognizeEnv Generated.pegGrammar sc (fuel + 4) e rest)
      boundLength [] headingStartItems input =
      .ok (if (classExpected "##" [(48, 57)] input).isSome then none
        else if "#".toList.isPrefixOf input then some (input.drop 1) else none) := by
  have look : PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 4)
      (.notPred (.ref "NumberOpen" [])) input =
      .ok (if (classExpected "##" [(48, 57)] input).isSome then none else some input) := by
    change (match PegModel.recognizeEnv Generated.pegGrammar [] (fuel + 3) (.ref "NumberOpen" []) input with
      | Except.error reason => if PegModel.isLabelFailure reason then Except.ok (some input) else Except.error reason
      | Except.ok none => Except.ok (some input)
      | Except.ok (some _) => Except.ok none) = _
    rw [generated_number_open]
    cases classExpected "##" [(48, 57)] input <;> rfl
  have lit := literal_total Generated.pegGrammar [] (fuel + 3) "#" "'#'" input
  cases h : (classExpected "##" [(48, 57)] input).isSome <;>
    cases l : "#".toList.isPrefixOf input <;>
    simp [headingStartItems, PegModel.runSequence, look, lit, h, l] <;> rfl

end PrefixBoundaryTotal
