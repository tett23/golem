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
  simp [PegModel.recognize, prefix_self_append, drop_self_append, Id.run]
  rfl

theorem ordered_choice_first (grammar : PegModel.Grammar) (first : PegModel.Expr)
    (later : List PegModel.Expr) (input rest : List Char) (fuel : Nat)
    (hit : PegModel.recognize grammar fuel first input = .ok (some rest)) :
    PegModel.recognize grammar (fuel + 1) (.choice [[first], later]) input =
      .ok (some rest) := by
  simp [PegModel.recognize, hit, Id.run]
  rfl

theorem ordered_choice_fallback (grammar : PegModel.Grammar)
    (first second : PegModel.Expr) (input rest : List Char) (fuel : Nat)
    (miss : PegModel.recognize grammar fuel first input = .ok none)
    (hit : PegModel.recognize grammar fuel second input = .ok (some rest)) :
    PegModel.recognize grammar (fuel + 1) (.choice [[first], [second]]) input =
      .ok (some rest) := by
  simp [PegModel.recognize, miss, hit, Id.run]
  rfl

theorem repeated_a_roundtrip (grammar : PegModel.Grammar) (count : Nat) :
    PegModel.recognize grammar (count + 2) (.star (.lit "a" "'a'"))
      (List.replicate count 'a') = .ok (some []) := by
  induction count with
  | zero => rfl
  | succ n ih =>
      rw [PegModel.recognize]
      simp only [List.replicate]
      have hit : PegModel.recognize grammar (n + 2) (.lit "a" "'a'")
          ('a' :: List.replicate n 'a') = .ok (some (List.replicate n 'a')) := by
        simp [PegModel.recognize, List.isPrefixOf, List.drop, Id.run]
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
    .error "parameterized reference Blocks" := by rfl

-- Opaque Haskell predicates cannot become a successful model parse.
example : PegModel.recognize Generated.pegGrammar 2
    (.semanticPred true " True ") [] = .error "opaque semantic predicate" := by rfl

end PegModelTest
