import FigureJobValues
import PriorUnitCounts
namespace BesideClassifiedPrefix
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds

inductive CountSlot where
  | table (fixedCount : Nat)
  | ordinary (fixedCount : Nat)
  | wrapped

private def part (body : Nat → Option α) (skip : Nat → Bool) (index : Nat) : CountSlot → Nat × Option Nat
  | .table fixedCount => (fixedCount, none)
  | .ordinary fixedCount => if skip index || (body index).isSome then (0, none) else (fixedCount, none)
  | .wrapped => if skip index || (body index).isSome then (0, none) else (1, some index)

def classifiedParts (body : Nat → Option α) (skip : Nat → Bool) : Nat → List CountSlot → List (Nat × Option Nat)
  | _, [] => []
  | index, slot :: later => part body skip index slot :: classifiedParts body skip (index + 1) later

theorem root_adr0352_i5_classified_parts_adjust
    (body : Nat → Option α) (skip : Nat → Bool) (change : α → α) (target start : Nat) (slots : List CountSlot) :
    classifiedParts (adjustBeside change target body) skip start slots = classifiedParts body skip start slots := by
  induction slots generalizing start with
  | nil => rfl
  | cons slot later ih =>
    cases slot <;> simp [classifiedParts, part, root_adr0352_i5_adjust_preserves_domain, ih]

private theorem part_owner (body : Nat → Option α) (skip : Nat → Bool) (index owner : Nat) (slot : CountSlot)
    (source : (part body skip index slot).2 = some owner) : owner = index := by
  cases slot with
  | table fixedCount => simp [part] at source
  | ordinary fixedCount =>
    by_cases blocked : (skip index || (body index).isSome) = true <;> simp [part, blocked] at source
  | wrapped =>
    by_cases blocked : (skip index || (body index).isSome) = true
    · simp [part, blocked] at source
    · simpa [part, blocked] using source.symm

theorem root_adr0352_i5_classified_owner_range
    (body : Nat → Option α) (skip : Nat → Bool) (start : Nat) (slots : List CountSlot) (fixed owner : Nat)
    (member : (fixed, some owner) ∈ classifiedParts body skip start slots) :
    start ≤ owner ∧ owner < start + slots.length := by
  induction slots generalizing start with
  | nil => simp [classifiedParts] at member
  | cons slot later ih =>
    rcases List.mem_cons.mp member with atHead | inTail
    · have same := part_owner body skip start owner slot (by simpa using congrArg Prod.snd atHead.symm)
      subst owner
      simp only [List.length_cons]
      exact ⟨Nat.le_refl _, by omega⟩
    · have range := ih (start + 1) inTail
      simp only [List.length_cons]
      exact ⟨by omega, by omega⟩

private theorem take_bound (slots : List CountSlot) (count : Nat) : (slots.take count).length ≤ count := by
  induction count generalizing slots with
  | zero => simp [List.take]
  | succ count ih =>
    cases slots with
    | nil => simp [List.take]
    | cons head later =>
      change (later.take count).length + 1 ≤ count + 1
      exact Nat.succ_le_succ (ih later)

theorem root_adr0352_i5_classified_prior_prefix
    (body : Nat → Option α) (current : Nat → Option Kind) (count owner target : Nat)
    (size : α → Nat) (change : α → α) (skip : Nat → Bool) (slots : List CountSlot)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (figure : current owner = some .figure) (selected : target ∈ candidateKeys body current owner count) :
    unitContributions (adjustBeside change target body) current count size
      (classifiedParts (adjustBeside change target body) skip 0 (slots.take owner)) =
    unitContributions body current count size (classifiedParts body skip 0 (slots.take owner)) := by
  rw [root_adr0352_i5_classified_parts_adjust]
  apply root_adr0352_i5_prior_unit_contributions_unchanged body current count owner target size change _ typed figure _ selected
  intro fixed prior member
  have range := root_adr0352_i5_classified_owner_range body skip 0 (slots.take owner) fixed prior member
  have length := take_bound slots owner
  omega

theorem root_adr0352_i5_reached_classified_prior_prefix
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache) (owner target : Nat)
    (size : α → Nat) (change : α → α) (skip : Nat → Bool) (slots : List CountSlot)
    (figure : cache.kindAt owner = some .figure)
    (selected : target ∈ candidateKeys (fromPairs cache.pairs) cache.kindAt owner cache.count) :
    unitContributions (adjustBeside change target (fromPairs cache.pairs)) cache.kindAt cache.count size
      (classifiedParts (adjustBeside change target (fromPairs cache.pairs)) skip 0 (slots.take owner)) =
    unitContributions (fromPairs cache.pairs) cache.kindAt cache.count size
      (classifiedParts (fromPairs cache.pairs) skip 0 (slots.take owner)) := by
  apply root_adr0352_i5_classified_prior_prefix
  · exact root_adr0352_i5_payload_from_empty_typed rounds cache reached
  · exact figure
  · exact selected

end BesideClassifiedPrefix
