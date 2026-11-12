import Generated

namespace PegModelTest

private theorem prefix_self_append (xs ys : List Char) : xs.isPrefixOf (xs ++ ys) = true := by
  induction xs with
  | nil => simp [List.isPrefixOf]
  | cons _ rest ih => simp [List.isPrefixOf, ih]

private theorem drop_self_append (xs ys : List Char) : (xs ++ ys).drop xs.length = ys := by
  induction xs with
  | nil => simp
  | cons _ rest ih => simpa using ih

-- The interpretation of an arbitrary literal consumes exactly its printed
-- characters and leaves the following input unchanged.
theorem literal_roundtrip (grammar : PegModel.Grammar) (value written : String)
    (rest : List Char) (fuel : Nat) :
    PegModel.recognize grammar (fuel + 1) (.lit value written) (value.toList ++ rest) =
      .ok (some rest) := by
  simp [PegModel.recognize, PegModel.recognizeEnv, prefix_self_append, drop_self_append, Id.run]
  rfl

theorem ordered_choice_first (grammar : PegModel.Grammar) (value written : String)
    (later : List PegModel.Expr) (input rest : List Char) (fuel : Nat)
    (hit : PegModel.recognize grammar fuel (.lit value written) input = .ok (some rest)) :
    PegModel.recognize grammar (fuel + 1) (.choice [[.lit value written], later]) input =
      .ok (some rest) := by
  simp only [PegModel.recognize] at hit ⊢
  simp [PegModel.recognizeEnv, hit, Id.run]
  rfl

theorem ordered_choice_fallback (grammar : PegModel.Grammar)
    (firstValue firstWritten secondValue secondWritten : String) (input rest : List Char) (fuel : Nat)
    (miss : PegModel.recognize grammar fuel (.lit firstValue firstWritten) input = .ok none)
    (hit : PegModel.recognize grammar fuel (.lit secondValue secondWritten) input = .ok (some rest)) :
    PegModel.recognize grammar (fuel + 1)
      (.choice [[.lit firstValue firstWritten], [.lit secondValue secondWritten]]) input =
      .ok (some rest) := by
  simp only [PegModel.recognize] at miss hit ⊢
  simp [PegModel.recognizeEnv, miss, hit, Id.run]
  rfl

theorem repeated_a_roundtrip (grammar : PegModel.Grammar) (count : Nat) :
    PegModel.recognizeEnv grammar [] (count + 2) (.star (.lit "a" "'a'"))
      (List.replicate count 'a') = .ok (some []) := by
  induction count with
  | zero => rfl
  | succ n ih =>
      rw [PegModel.recognizeEnv]
      simp only [List.replicate]
      have hit : PegModel.recognizeEnv grammar [] (n + 2) (.lit "a" "'a'")
          ('a' :: List.replicate n 'a') = .ok (some (List.replicate n 'a')) := by
        simp [PegModel.recognizeEnv, List.isPrefixOf, List.drop, Id.run]
        rfl
      rw [hit]
      simp [ih, Id.run]

-- These use the rule and ordered escape choice exported from Golem.hpeg.
example : PegModel.recognize Generated.pegGrammar 40 (.ref "StringLit" [])
    "\"a\\\"b\"!".toList = .ok (some ['!']) := by rfl

example : PegModel.recognize Generated.pegGrammar 40 (.ref "StringLit" [])
    "\"a".toList = .ok none := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 50 [] = .ok (some []) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 100 "abc\n".toList =
    .ok (some []) := by rfl

-- The source PEG has direct left recursion in AddExpr and MulExpr.
example : PegModel.recognize Generated.pegGrammar 200 (.ref "AddExpr" [])
    "1!".toList = .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 200 (.ref "AddExpr" [])
    "1+2!".toList = .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 200 (.ref "AddExpr" [])
    "1+2*3!".toList = .ok (some "!".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 200 (.ref "AddExpr" [])
    "1+!".toList = .ok (some "+!".toList) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 300 "@set x = 1\n".toList =
    .ok (some []) := by rfl

-- TableRow returns length cs, which the table passes as h to body rows.
example : PegModel.recognizeStart Generated.pegGrammar 300
    "| a |\n|---|\n".toList = .ok (some []) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 300
    "| a |\n|---|\n| b |\n".toList = .ok (some []) := by rfl

example : PegModel.recognizeStart Generated.pegGrammar 300
    "| a | b |\n|---|---|\n| c | d |\n".toList = .ok (some []) := by rfl

-- Ind(n) consumes exactly n spaces; these are the parameter boundary cases.
example : PegModel.integer [("ind", 1)] "ind + 2" = some 3 := by rfl

example : PegModel.integer [("n", 0)] "n - 1" = none := by rfl

example : PegModel.predicate [("ordered", 1)] " ordered == 1 " = some true := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" ["0"])
    "x".toList = .ok (some "x".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" ["1"])
    " x".toList = .ok (some "x".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" ["2"])
    " x".toList = .ok none := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" ["2"])
    "  x".toList = .ok (some "x".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" [])
    "x".toList = .error "argument count for Ind" := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "Ind" ["unknown"])
    "x".toList = .error "opaque argument for Ind" := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "ListMark" ["0"])
    "-x".toList = .ok (some "x".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "ListMark" ["1"])
    "+x".toList = .ok (some "x".toList) := by rfl

example : PegModel.recognize Generated.pegGrammar 30 (.ref "ListMark" ["1"])
    "-x".toList = .ok none := by rfl

-- Supported Haskell boolean predicates preserve positive and negative tests.
example : PegModel.recognize Generated.pegGrammar 2
    (.semanticPred true " True ") [] = .ok (some []) := by rfl

example : PegModel.recognize Generated.pegGrammar 2
    (.semanticPred false " False ") [] = .ok (some []) := by rfl

example : PegModel.recognize Generated.pegGrammar 2
    (.semanticPred true " False ") [] = .ok none := by rfl

example : PegModel.recognize Generated.pegGrammar 2
    (.semanticPred true " r == h ") [] = .error "opaque semantic predicate" := by rfl

end PegModelTest
