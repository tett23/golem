import PosArgTrace
namespace PosArgBracketPrefix
open WordRoundTrip
set_option autoImplicit false
private theorem bracket_miss (word : Word) (c : Char) (member : c ∈ word.chars) :
    ('[' == c) = false := by
  have valid := word.valid c member
  cases equal : ('[' == c) with
  | false => rfl
  | true =>
    have same : '[' = c := eq_of_beq equal
    subst c
    contradiction

theorem I1_no_splat_prefix (word : Word) (tail : List Char)
    (single : word.chars ≠ ['*']) (double : word.chars ≠ ['*','*']) :
    "*[".toList.isPrefixOf (word.chars ++ '[' :: tail) = false ∧
    "**[".toList.isPrefixOf (word.chars ++ '[' :: tail) = false := by
  cases chars : word.chars with
  | nil => exact False.elim (word.nonempty chars)
  | cons first rest =>
    cases rest with
    | nil =>
      have firstNotStar : first ≠ '*' := by intro same; subst first; exact single chars
      have firstMiss : ('*' == first) = false := by
        cases equal : ('*' == first) with
        | false => rfl
        | true => exact False.elim (firstNotStar (eq_of_beq equal).symm)
      simp [List.append,List.isPrefixOf,firstMiss]
    | cons second rest =>
      have secondMiss := bracket_miss word second (by simp [chars])
      cases rest with
      | nil =>
        by_cases firstEq : first = '*'
        · have secondNotStar : second ≠ '*' := by
            intro same
            subst first
            subst second
            exact double chars
          have starSecondMiss : ('*' == second) = false := by
            cases equal : ('*' == second) with
            | false => rfl
            | true => exact False.elim (secondNotStar (eq_of_beq equal).symm)
          simp [List.append,List.isPrefixOf,firstEq,secondMiss,starSecondMiss]
        · have firstMiss : ('*' == first) = false := by
            cases equal : ('*' == first) with
            | false => rfl
            | true => exact False.elim (firstEq (eq_of_beq equal).symm)
          simp [List.append,List.isPrefixOf,firstMiss]
      | cons third rest =>
        have thirdMiss := bracket_miss word third (by simp [chars])
        simp [List.append,List.isPrefixOf,secondMiss,thirdMiss]
#print axioms I1_no_splat_prefix
end PosArgBracketPrefix
