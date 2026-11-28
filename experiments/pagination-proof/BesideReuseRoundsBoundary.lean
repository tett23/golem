import BesideReuseRounds

open BesideProducer BesideReuse

private def paragraph : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | _ => none
private def figure : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .figure
  | _ => none
private def yes (_ : Nat) : Bool := true
private def no (_ : Unit) : Bool := false
private def allowed (_ : Nat) (_ : Unit) : Bool := true
private def step (_ : Nat) (s : Unit) : Unit := s
private noncomputable def paragraphRound : Round Unit :=
  ⟨paragraph, 2, true, yes, true, no, allowed, step, step, [⟨0, 2, ()⟩]⟩
private noncomputable def figureRound : Round Unit :=
  ⟨figure, 2, true, yes, true, no, allowed, step, step, [⟨0, 2, ()⟩]⟩
private def keysOf : Option Cache → List Nat
  | none => []
  | some cache => cache.keys

example : runRounds (σ := Unit) none [] = none := by rfl
example : keysOf (runRounds none [paragraphRound]) = [1] := by decide
example : keysOf (runRounds none [paragraphRound, paragraphRound]) = [1] := by decide
example : keysOf (runRounds none [paragraphRound, figureRound]) = [] := by decide
example : keysOf (runRounds none [paragraphRound, figureRound, paragraphRound]) = [1] := by decide
example : keysOf (runRounds none [figureRound, paragraphRound, figureRound]) = [] := by decide
example : ∀ cache, runRounds none [paragraphRound, figureRound, paragraphRound] = some cache →
    cacheTyped cache := root_adr0352_i5_from_no_cache_typed _
example : ∀ cache, runRounds none [paragraphRound, figureRound, paragraphRound] = some cache →
    cacheBounded cache := by
  apply root_adr0352_i5_from_no_cache_bounded
  intro round member
  simp only [List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with same | same | same
  all_goals subst round; intro key outside
  all_goals change 2 ≤ key at outside
  all_goals cases key with
    | zero => exact False.elim ((by decide : ¬ (2 ≤ 0)) outside)
    | succ key => cases key with
      | zero => exact False.elim ((by decide : ¬ (2 ≤ 1)) outside)
      | succ key => rfl
