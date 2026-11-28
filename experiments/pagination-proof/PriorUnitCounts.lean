import BesideReuseOrder
import SelectedCountPrefix

namespace BesideReuse
open BesideOwnership BesideProducer CausalFirstIds

private theorem rowCounts_unchanged (keys : List Nat) (size : α → Nat)
    (body : Nat → Option α) (change : α → α) (target : Nat)
    (absent : ∀ key, key ∈ keys → key ≠ target) :
    countsFor keys (rowCount size (adjustBeside change target body)) = countsFor keys (rowCount size body) := by
  induction keys with
  | nil => rfl
  | cons head later ih =>
    have different := absent head (List.mem_cons_self head later)
    have tail : ∀ key, key ∈ later → key ≠ target := fun key member => absent key (List.mem_cons_of_mem head member)
    simp [countsFor, rowCount, adjustBeside, different, ih tail]

theorem root_adr0352_i5_earlier_owner_avoids_current
    (body : Nat → Option α) (current : Nat → Option Kind) (count earlierOwner owner target key : Nat)
    (typed : ∀ k, (body k).isSome = true → current k = some .paragraph)
    (figure : current owner = some .figure) (earlier : earlierOwner < owner)
    (targetSelected : target ∈ candidateKeys body current owner count)
    (keySelected : key ∈ candidateKeys body current earlierOwner count) : key ≠ target := by
  have before := root_adr0352_i5_typed_scan_before_figure body current (earlierOwner + 1)
    (count - (earlierOwner + 1)) owner key figure (by omega) (fun k member => typed k
      (root_adr0352_i5_candidate_keys_exist body (BesideProducer.controlAt current) _ _ k member)) keySelected
  have after := root_adr0352_i5_beside_key_range
    (classes body (BesideProducer.controlAt current) (owner + 1) (count - (owner + 1))) (owner + 1) target targetSelected
  omega

def unitContributions (body : Nat → Option α) (current : Nat → Option Kind)
    (count : Nat) (size : α → Nat) : List (Nat × Option Nat) → List Nat
  | [] => []
  | (fixed, none) :: later => fixed :: unitContributions body current count size later
  | (fixed, some owner) :: later =>
      (fixed + ownedRows (countsFor (candidateKeys body current owner count) (rowCount size body))) ::
      unitContributions body current count size later

theorem root_adr0352_i5_prior_unit_contributions_unchanged
    (body : Nat → Option α) (current : Nat → Option Kind) (count owner target : Nat)
    (size : α → Nat) (change : α → α) (parts : List (Nat × Option Nat))
    (typed : ∀ k, (body k).isSome = true → current k = some .paragraph)
    (figure : current owner = some .figure)
    (earlier : ∀ fixed prior, (fixed, some prior) ∈ parts → prior < owner)
    (targetSelected : target ∈ candidateKeys body current owner count) :
    unitContributions (adjustBeside change target body) current count size parts =
      unitContributions body current count size parts := by
  induction parts with
  | nil => rfl
  | cons part later ih =>
    have rest := ih (fun fixed prior member => earlier fixed prior (List.mem_cons_of_mem part member))
    rcases part with ⟨fixed, source⟩
    cases source with
    | none => simp only [unitContributions, rest]
    | some prior =>
      have before := earlier fixed prior (List.mem_cons_self (fixed, some prior) later)
      have sameKeys : candidateKeys (adjustBeside change target body) current prior count = candidateKeys body current prior count := by
        exact root_adr0352_i5_rebreak_preserves_selected_keys change target (prior + 1) (count - (prior + 1))
          body (BesideProducer.controlAt current)
      have counts := rowCounts_unchanged (candidateKeys body current prior count) size body change target
        (fun key selected => root_adr0352_i5_earlier_owner_avoids_current body current count prior owner target key
          typed figure before targetSelected selected)
      simp only [unitContributions, sameKeys, counts, rest]

theorem root_adr0352_i5_two_pass_derived_outer_prefix
    (body : Nat → Option α) (current : Nat → Option Kind) (count owner target next : Nat)
    (size : α → Nat) (change : α → α) (before after oldAfterUnits newAfterUnits : List Nat) (parts : List (Nat × Option Nat))
    (typed : ∀ k, (body k).isSome = true → current k = some .paragraph)
    (figure : current owner = some .figure) (earlier : ∀ fixed prior, (fixed, some prior) ∈ parts → prior < owner)
    (selected : candidateKeys body current owner count = before ++ target :: after) :
    besideFromTwoPass (unitContributions (adjustBeside change target body) current count size parts) newAfterUnits
      (countsFor before (rowCount size (adjustBeside change target body)))
      (countsFor after (rowCount size (adjustBeside change target body)))
      (rowCount size (adjustBeside change target body) target) next =
    besideFromTwoPass (unitContributions body current count size parts) oldAfterUnits
      (countsFor before (rowCount size body)) (countsFor after (rowCount size body)) (rowCount size body target) next := by
  have member : target ∈ candidateKeys body current owner count := by
    rw [selected]
    exact List.mem_append_of_mem_right before (List.mem_cons_self target after)
  have outer := root_adr0352_i5_prior_unit_contributions_unchanged body current count owner target size change
    parts typed figure earlier member
  have inner := root_adr0352_i5_selected_count_prefix
    (classes body (BesideProducer.controlAt current) (owner + 1) (count - (owner + 1))) (owner + 1)
    target before after size body change selected
  rw [root_adr0352_i5_two_pass_first_value, root_adr0352_i5_two_pass_first_value, outer, inner]

end BesideReuse
