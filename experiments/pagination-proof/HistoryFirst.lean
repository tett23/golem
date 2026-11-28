import BodyEdits
namespace BesideHistoryFirst
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideClassifiedPrefix BesideOwnedFirst BesideOwnedScan BesideOwnedRows BesideOwnedGlobal BesideOwnedUnion BesideBodyEdits CausalFirstIds

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

private theorem typed_local_first_stable
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target : Nat) (size : α → Nat) (change : α → α) (skip : Nat → Bool) (slots : List CountSlot)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count) :
    storedOwnedFirst (adjustBeside change target body) current count job.owner target next size skip slots =
      storedOwnedFirst body current count job.owner target next size skip slots := by
  have sameKeys : candidateKeys (adjustBeside change target body) current job.owner count = candidateKeys body current job.owner count :=
    root_adr0352_i5_rebreak_preserves_selected_keys change target (job.owner + 1) (count - (job.owner + 1)) body (controlAt current)
  rw [root_adr0352_i5_owned_first_scan, root_adr0352_i5_owned_first_scan]
  unfold ownedFirstId
  rw [sameKeys]
  simp only [selected, if_true]
  have figure := root_adr0352_i5_owner_figure_from_job current count place eligible initState job member
  have outer := root_adr0352_i5_classified_prior_prefix body current count job.owner target size change skip slots typed figure selected
  have split := split_selected (candidateKeys body current job.owner count) target selected
  have inner := root_adr0352_i5_selected_count_prefix
    (classes body (controlAt current) (job.owner + 1) (count - (job.owner + 1)))
    (job.owner + 1) target (beforeTarget target (candidateKeys body current job.owner count))
    (afterTarget target (candidateKeys body current job.owner count)) size body change split
  rw [root_adr0352_i5_two_pass_first_value, root_adr0352_i5_two_pass_first_value, outer, inner]

private theorem typed_global_first_stable
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target : Nat) (size : α → Nat) (change : α → α) (skip : Nat → Bool) (slots : List CountSlot)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count) :
    ownedTable (adjustBeside change target body) current count next size skip slots place eligible initState target =
      ownedTable body current count next size skip slots place eligible initState target := by
  have changedTyped : ∀ key, (adjustBeside change target body key).isSome = true → current key = some .paragraph := by
    intro key present
    rw [root_adr0352_i5_adjust_preserves_domain] at present
    exact typed key present
  have changedSelected : target ∈ candidateKeys (adjustBeside change target body) current job.owner count := by
    rw [candidateKeys, root_adr0352_i5_rebreak_preserves_selected_keys]
    exact selected
  unfold ownedTable
  rw [root_adr0352_i5_global_lookup_at_owned_target _ _ _ _ changedTyped place eligible initState size skip slots job target member changedSelected,
      root_adr0352_i5_global_lookup_at_owned_target _ _ _ _ typed place eligible initState size skip slots job target member selected]
  exact typed_local_first_stable body current count next typed place eligible initState job target size change skip slots member selected
end BesideHistoryFirst
namespace BesideHistoryFirst
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideClassifiedPrefix BesideOwnedFirst BesideOwnedScan BesideOwnedRows BesideOwnedGlobal BesideOwnedUnion BesideBodyEdits CausalFirstIds

theorem root_adr0352_i5_typed_selected_union_exists_stable
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target : Nat) (size : α → Nat) (change : α → α) (skip : Nat → Bool) (slots : List CountSlot)
    (oldBase newBase : Nat → Option Nat)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count) :
    ∃ ident,
      leftUnion (ownedTable body current count next size skip slots place eligible initState) oldBase target = some ident ∧
      leftUnion (ownedTable (adjustBeside change target body) current count next size skip slots place eligible initState) newBase target = some ident := by
  let ident := (countsFor (beforeTarget target (candidateKeys body current job.owner count)) (rowCount size body)).foldl Nat.add
    (derivedStart body current count next size skip slots job.owner)
  have localSome : storedOwnedFirst body current count job.owner target next size skip slots = some ident := by
    rw [root_adr0352_i5_owned_first_scan]
    simp only [ownedFirstId, selected, if_true, root_adr0352_i5_two_pass_first_value]
    rfl
  have oldSome : ownedTable body current count next size skip slots place eligible initState target = some ident :=
    (root_adr0352_i5_global_lookup_at_owned_target body current count next typed place eligible initState size skip slots job target member selected).trans localSome
  have newSome : ownedTable (adjustBeside change target body) current count next size skip slots place eligible initState target = some ident :=
    (typed_global_first_stable body current count next typed place eligible initState job target size change skip slots member selected).trans oldSome
  exact ⟨ident, by simp only [leftUnion, oldSome], by simp only [leftUnion, newSome]⟩

theorem root_adr0352_i5_history_selected_union_exists_stable
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache) (edits : List (BodyEdit α))
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target next : Nat) (size : α → Nat) (change : α → α)
    (skip : Nat → Bool) (slots : List CountSlot) (oldBase newBase : Nat → Option Nat)
    (member : job ∈ valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))
    (selected : target ∈ candidateKeys (fromPairs cache.pairs) cache.kindAt job.owner cache.count) :
    ∃ ident,
      leftUnion (ownedTable (applyEdits (fromPairs cache.pairs) edits) cache.kindAt cache.count next size skip slots place eligible initState) oldBase target = some ident ∧
      leftUnion (ownedTable (adjustBeside change target (applyEdits (fromPairs cache.pairs) edits)) cache.kindAt cache.count next size skip slots place eligible initState) newBase target = some ident := by
  apply root_adr0352_i5_typed_selected_union_exists_stable
  · exact root_adr0352_i5_reached_body_edits_typed rounds cache reached edits
  · exact member
  · rw [root_adr0352_i5_body_edits_selected]
    exact selected
end BesideHistoryFirst
