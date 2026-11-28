import HistoryFirst
namespace BesideSuffixCountPrefix
open BesideOwnership BesideProducer BesideReuse BesideClassifiedPrefix BesideOwnedFirst BesideOwnedScan BesideOwnedGlobal BesideOwnedUnion BesideJobValues BesideFigureTable BesideHistoryFirst CausalFirstIds

private theorem prefix_below (before after : List Nat) (target key : Nat)
    (ordered : Increasing (before ++ target :: after)) (member : key ∈ before) : key < target := by
  induction before with
  | nil => simp at member
  | cons head later ih =>
    simp only [List.cons_append, Increasing] at ordered
    rcases List.mem_cons.mp member with same | tail
    · subst key
      exact ordered.1 target (List.mem_append_of_mem_right later (List.mem_cons_self target after))
    · exact ih ordered.2 tail

private theorem counts_avoid (keys : List Nat) (size : α → Nat) (body : Nat → Option α)
    (change : α → α) (changed : Nat) (absent : ∀ key ∈ keys, key ≠ changed) :
    countsFor keys (rowCount size (adjustBeside change changed body)) = countsFor keys (rowCount size body) := by
  induction keys with
  | nil => rfl
  | cons head later ih =>
    have different := absent head (List.mem_cons_self head later)
    have tail : ∀ key ∈ later, key ≠ changed := fun key member => absent key (List.mem_cons_of_mem head member)
    simp [countsFor, rowCount, adjustBeside, different, ih tail]

theorem root_adr0352_i5_later_update_preserves_selected_prefix
    (rows : List Class) (start target changed : Nat) (before after : List Nat)
    (size : α → Nat) (body : Nat → Option α) (change : α → α)
    (selected : scan start rows = before ++ target :: after) (notEarlier : target ≤ changed) :
    countsFor before (rowCount size (adjustBeside change changed body)) = countsFor before (rowCount size body) := by
  have ordered := root_adr0352_i5_beside_key_order rows start
  rw [selected] at ordered
  apply counts_avoid
  intro key member same
  have smaller := prefix_below before after target key ordered member
  omega

theorem root_adr0352_i5_later_update_preserves_prior_contributions
    (body : Nat → Option α) (current : Nat → Option Kind) (count owner target changed : Nat)
    (size : α → Nat) (change : α → α) (parts : List (Nat × Option Nat))
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (figure : current owner = some .figure)
    (earlier : ∀ fixed prior, (fixed, some prior) ∈ parts → prior < owner)
    (selected : target ∈ candidateKeys body current owner count) (notEarlier : target ≤ changed) :
    unitContributions (adjustBeside change changed body) current count size parts =
      unitContributions body current count size parts := by
  have targetAfter := root_adr0352_i5_beside_key_range
    (classes body (controlAt current) (owner + 1) (count - (owner + 1))) (owner + 1) target selected
  induction parts with
  | nil => rfl
  | cons part later ih =>
    have rest := ih (fun fixed prior member => earlier fixed prior (List.mem_cons_of_mem part member))
    rcases part with ⟨fixed, source⟩
    cases source with
    | none => simp only [unitContributions, rest]
    | some prior =>
      have before := earlier fixed prior (List.mem_cons_self (fixed, some prior) later)
      have sameKeys : candidateKeys (adjustBeside change changed body) current prior count = candidateKeys body current prior count :=
        root_adr0352_i5_rebreak_preserves_selected_keys change changed (prior + 1) (count - (prior + 1)) body (controlAt current)
      have counts := counts_avoid (candidateKeys body current prior count) size body change changed (by
        intro key member same
        have keyBefore := root_adr0352_i5_typed_scan_before_figure body current (prior + 1)
          (count - (prior + 1)) owner key figure (by omega)
          (fun k belongs => typed k (root_adr0352_i5_candidate_keys_exist body (controlAt current) _ _ k belongs)) member
        omega)
      simp only [unitContributions, sameKeys, counts, rest]

private theorem take_bound (slots : List CountSlot) (count : Nat) : (slots.take count).length ≤ count := by
  induction count generalizing slots with
  | zero => simp [List.take]
  | succ count ih =>
    cases slots with
    | nil => simp [List.take]
    | cons head later => exact Nat.succ_le_succ (ih later)

private theorem split_selected (keys : List Nat) (target : Nat) (member : target ∈ keys) :
    keys = beforeTarget target keys ++ target :: afterTarget target keys := by
  induction keys with
  | nil => simp at member
  | cons key later ih =>
    by_cases same : key = target
    · subst key; simp [beforeTarget, afterTarget]
    · have rest : target ∈ later := by
        rcases List.mem_cons.mp member with first | tail
        · exact (same first.symm).elim
        · exact tail
      simpa [beforeTarget, afterTarget, same] using congrArg (List.cons key) (ih rest)

theorem root_adr0352_i5_later_update_preserves_local_first
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target changed : Nat) (size : α → Nat) (change : α → α) (skip : Nat → Bool) (slots : List CountSlot)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count) (notEarlier : target ≤ changed) :
    storedOwnedFirst (adjustBeside change changed body) current count job.owner target next size skip slots =
      storedOwnedFirst body current count job.owner target next size skip slots := by
  have sameKeys : candidateKeys (adjustBeside change changed body) current job.owner count = candidateKeys body current job.owner count :=
    root_adr0352_i5_rebreak_preserves_selected_keys change changed (job.owner + 1) (count - (job.owner + 1)) body (controlAt current)
  rw [root_adr0352_i5_owned_first_scan, root_adr0352_i5_owned_first_scan]
  unfold ownedFirstId
  rw [sameKeys]
  simp only [selected, if_true]
  have figure := root_adr0352_i5_owner_figure_from_job current count place eligible initState job member
  have outer : unitContributions (adjustBeside change changed body) current count size
      (classifiedParts (adjustBeside change changed body) skip 0 (slots.take job.owner)) =
      unitContributions body current count size (classifiedParts body skip 0 (slots.take job.owner)) := by
    rw [root_adr0352_i5_classified_parts_adjust]
    apply root_adr0352_i5_later_update_preserves_prior_contributions body current count job.owner target changed size change _ typed figure _ selected notEarlier
    intro fixed prior belongs
    have range := root_adr0352_i5_classified_owner_range body skip 0 (slots.take job.owner) fixed prior belongs
    have length := take_bound slots job.owner
    omega
  have split := split_selected (candidateKeys body current job.owner count) target selected
  have inner := root_adr0352_i5_later_update_preserves_selected_prefix
    (classes body (controlAt current) (job.owner + 1) (count - (job.owner + 1)))
    (job.owner + 1) target changed (beforeTarget target (candidateKeys body current job.owner count))
    (afterTarget target (candidateKeys body current job.owner count)) size body change split notEarlier
  rw [root_adr0352_i5_two_pass_first_value, root_adr0352_i5_two_pass_first_value, outer, inner]

theorem root_adr0352_i5_later_update_preserves_existing_union_first
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target changed : Nat) (size : α → Nat) (change : α → α) (skip : Nat → Bool) (slots : List CountSlot)
    (oldBase newBase : Nat → Option Nat)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count) (notEarlier : target ≤ changed) :
    ∃ ident,
      leftUnion (ownedTable body current count next size skip slots place eligible initState) oldBase target = some ident ∧
      leftUnion (ownedTable (adjustBeside change changed body) current count next size skip slots place eligible initState) newBase target = some ident := by
  have changedTyped : ∀ key, (adjustBeside change changed body key).isSome = true → current key = some .paragraph := by
    intro key present
    rw [root_adr0352_i5_adjust_preserves_domain] at present
    exact typed key present
  have changedSelected : target ∈ candidateKeys (adjustBeside change changed body) current job.owner count := by
    rw [candidateKeys, root_adr0352_i5_rebreak_preserves_selected_keys]
    exact selected
  have same : ownedTable (adjustBeside change changed body) current count next size skip slots place eligible initState target =
      ownedTable body current count next size skip slots place eligible initState target := by
    unfold ownedTable
    rw [root_adr0352_i5_global_lookup_at_owned_target _ _ _ _ changedTyped place eligible initState size skip slots job target member changedSelected,
      root_adr0352_i5_global_lookup_at_owned_target _ _ _ _ typed place eligible initState size skip slots job target member selected]
    exact root_adr0352_i5_later_update_preserves_local_first body current count next typed place eligible initState job target changed size change skip slots member selected notEarlier
  rcases root_adr0352_i5_typed_selected_union_exists_stable body current count next typed place eligible initState job target size id skip slots
    (fun _ => none) (fun _ => none) member selected with ⟨ident, oldSome, _⟩
  have present : ownedTable body current count next size skip slots place eligible initState target = some ident := by
    cases found : ownedTable body current count next size skip slots place eligible initState target with
    | none => simp [leftUnion, found] at oldSome
    | some value => simpa [leftUnion, found] using oldSome
  have newSome := same.trans present
  exact ⟨ident, by simp only [leftUnion, present], by simp only [leftUnion, newSome]⟩
end BesideSuffixCountPrefix
