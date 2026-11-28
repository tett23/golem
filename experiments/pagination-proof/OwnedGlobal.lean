import OwnedRows
namespace BesideOwnedGlobal
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideFigureWindow BesideJobValues BesideClassifiedPrefix BesideOwnedFirst BesideOwnedScan BesideOwnedRows CausalFirstIds

private theorem increasing_unique (keys : List Nat) (ordered : Increasing keys) : NoRepeat keys := by
  induction keys with
  | nil => trivial
  | cons key later ih =>
    refine ⟨?_, ih ordered.2⟩
    intro member
    exact (Nat.lt_irrefl key) (ordered.1 key member)

private theorem member_all_pairs
    (body : Nat → Option α) (current : Nat → Option Kind) (count : Nat) (size : α → Nat)
    (startOf : Nat → Nat) (jobs : List (ReuseJob σ)) (job : ReuseJob σ) (key ident : Nat)
    (member : job ∈ jobs)
    (localPair : (key, ident) ∈ numberPairs (candidateKeys body current job.owner count) (rowCount size body) (startOf job.owner)) :
    (key, ident) ∈ allPairs body current count size startOf jobs := by
  induction jobs with
  | nil => simp at member
  | cons head later ih =>
    rcases List.mem_cons.mp member with first | rest
    · subst head
      exact List.mem_append_of_mem_left _ localPair
    · exact List.mem_append_of_mem_right _ (ih rest)

private theorem typed_global_retains
    (body : Nat → Option α) (current : Nat → Option Kind) (count : Nat)
    (typed : ∀ k, (body k).isSome = true → current k = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ) (size : α → Nat) (startOf : Nat → Nat)
    (job : ReuseJob τ) (key ident : Nat)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (localPair : (key, ident) ∈ numberPairs (candidateKeys body current job.owner count) (rowCount size body) (startOf job.owner)) :
    fromPairs (allPairs body current count size startOf (valueJobs eligible initState count (figurePairs current place 0 count))) key = some ident := by
  apply root_adr0352_i5_unique_payload_retained
  · rw [root_adr0352_i5_all_owned_pairs_keys]
    apply increasing_unique
    apply root_adr0352_i5_all_owned_keys_increasing body current count _ typed
    · exact root_adr0352_i5_value_jobs_ordered eligible initState count _ (root_adr0352_i5_figure_pairs_keys_increasing current place 0 count)
    · intro other belongs
      exact root_adr0352_i5_owner_figure_from_job current count place eligible initState other belongs
  · exact member_all_pairs _ _ _ _ _ _ job key ident member localPair

private theorem lookup_member (pairs : List (Nat × Nat)) (key ident : Nat)
    (found : fromPairs pairs key = some ident) : (key, ident) ∈ pairs := by
  induction pairs with
  | nil => cases found
  | cons head later ih =>
    rcases head with ⟨first, value⟩
    cases tailValue : fromPairs later key with
    | some last =>
      simp only [fromPairs, tailValue] at found
      cases found
      exact List.mem_cons_of_mem _ (ih tailValue)
    | none =>
      by_cases same : key = first
      · subst key
        simp only [fromPairs, tailValue, if_true] at found
        cases found
        exact List.mem_cons_self _ _
      · simp only [fromPairs, tailValue, same, if_false] at found

noncomputable def derivedStart (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot) (owner : Nat) : Nat :=
  (unitContributions body current count size (classifiedParts body skip 0 (slots.take owner))).foldl Nat.add next + 1
end BesideOwnedGlobal
namespace BesideOwnedGlobal
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideFigureWindow BesideJobValues BesideClassifiedPrefix BesideOwnedFirst BesideOwnedScan BesideOwnedRows CausalFirstIds

theorem root_adr0352_i5_global_lookup_at_owned_target
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ k, (body k).isSome = true → current k = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ) (size : α → Nat)
    (skip : Nat → Bool) (slots : List CountSlot) (job : ReuseJob τ) (target : Nat)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count) :
    fromPairs (allPairs body current count size (derivedStart body current count next size skip slots)
      (valueJobs eligible initState count (figurePairs current place 0 count))) target =
      storedOwnedFirst body current count job.owner target next size skip slots := by
  let ident := (countsFor (beforeTarget target (candidateKeys body current job.owner count)) (rowCount size body)).foldl Nat.add
    (derivedStart body current count next size skip slots job.owner)
  have localSome : storedOwnedFirst body current count job.owner target next size skip slots = some ident := by
    rw [root_adr0352_i5_owned_first_scan]
    simp only [ownedFirstId, selected, if_true, root_adr0352_i5_two_pass_first_value]
    rfl
  have localPair : (target, ident) ∈ numberPairs (candidateKeys body current job.owner count) (rowCount size body)
      (derivedStart body current count next size skip slots job.owner) :=
    lookup_member _ _ _ localSome
  exact (typed_global_retains body current count typed place eligible initState size _ job target ident member localPair).trans localSome.symm
end BesideOwnedGlobal
namespace BesideOwnedGlobal
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideFigureWindow BesideJobValues BesideClassifiedPrefix BesideOwnedFirst BesideOwnedScan BesideOwnedRows CausalFirstIds

private theorem selected_global_first_unchanged
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target next : Nat) (size : α → Nat) (change : α → α)
    (skip : Nat → Bool) (slots : List CountSlot)
    (member : job ∈ valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))
    (selected : target ∈ candidateKeys (fromPairs cache.pairs) cache.kindAt job.owner cache.count) :
    fromPairs (allPairs (adjustBeside change target (fromPairs cache.pairs)) cache.kindAt cache.count size
      (derivedStart (adjustBeside change target (fromPairs cache.pairs)) cache.kindAt cache.count next size skip slots)
      (valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))) target =
    fromPairs (allPairs (fromPairs cache.pairs) cache.kindAt cache.count size
      (derivedStart (fromPairs cache.pairs) cache.kindAt cache.count next size skip slots)
      (valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))) target := by
  let body := fromPairs cache.pairs
  have typed : ∀ k, (body k).isSome = true → cache.kindAt k = some .paragraph :=
    root_adr0352_i5_payload_from_empty_typed rounds cache reached
  have changedTyped : ∀ k, (adjustBeside change target body k).isSome = true → cache.kindAt k = some .paragraph := by
    intro key present
    rw [root_adr0352_i5_adjust_preserves_domain] at present
    exact typed key present
  have changedSelected : target ∈ candidateKeys (adjustBeside change target body) cache.kindAt job.owner cache.count := by
    rw [candidateKeys, root_adr0352_i5_rebreak_preserves_selected_keys]
    exact selected
  rw [root_adr0352_i5_global_lookup_at_owned_target _ _ _ _ changedTyped place eligible initState size skip slots job target member changedSelected,
      root_adr0352_i5_global_lookup_at_owned_target _ _ _ _ typed place eligible initState size skip slots job target member selected]
  exact root_adr0352_i5_reached_owned_first_store_unchanged rounds cache reached place eligible initState job member target next size change skip slots
end BesideOwnedGlobal

namespace BesideOwnedGlobal
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideFigureWindow BesideJobValues BesideClassifiedPrefix BesideOwnedFirst BesideOwnedScan BesideOwnedRows CausalFirstIds

private theorem append_member (xs ys : List Nat) (key : Nat) (member : key ∈ xs ++ ys) : key ∈ xs ∨ key ∈ ys := by
  induction xs with
  | nil => exact Or.inr member
  | cons head later ih =>
    rcases List.mem_cons.mp member with first | rest
    · exact Or.inl (List.mem_cons.mpr (Or.inl first))
    · rcases ih rest with here | there
      · exact Or.inl (List.mem_cons.mpr (Or.inr here))
      · exact Or.inr there

private theorem belongs_job (body : Nat → Option α) (current : Nat → Option Kind) (count key : Nat)
    (jobs : List (ReuseJob σ)) (member : key ∈ allKeys body current count jobs) :
    ∃ job, job ∈ jobs ∧ key ∈ candidateKeys body current job.owner count := by
  induction jobs with
  | nil => simp [allKeys] at member
  | cons job later ih =>
    rcases append_member _ _ _ member with here | there
    · exact ⟨job, List.mem_cons_self _ _, here⟩
    · rcases ih there with ⟨other, belongs, selected⟩
      exact ⟨other, List.mem_cons_of_mem _ belongs, selected⟩

private theorem pair_member_key (pairs : List (Nat × Nat)) (key ident : Nat) (member : (key, ident) ∈ pairs) : key ∈ pairKeys pairs := by
  induction pairs with
  | nil => simp at member
  | cons head later ih =>
    rcases head with ⟨first, value⟩
    rcases List.mem_cons.mp member with atHead | inTail
    · cases atHead; exact List.mem_cons_self _ _
    · exact List.mem_cons_of_mem _ (ih inTail)

private theorem global_selected
    (body : Nat → Option α) (current : Nat → Option Kind) (count : Nat)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (size : α → Nat) (startOf : Nat → Nat) (target ident : Nat)
    (found : fromPairs (allPairs body current count size startOf (valueJobs eligible initState count (figurePairs current place 0 count))) target = some ident) :
    ∃ job, job ∈ valueJobs eligible initState count (figurePairs current place 0 count) ∧ target ∈ candidateKeys body current job.owner count := by
  have key := pair_member_key _ target ident (lookup_member _ target ident found)
  rw [root_adr0352_i5_all_owned_pairs_keys] at key
  exact belongs_job _ _ _ _ _ key

theorem root_adr0352_i5_reached_global_first_unchanged
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (target next : Nat) (size : α → Nat) (change : α → α) (skip : Nat → Bool) (slots : List CountSlot) :
    fromPairs (allPairs (adjustBeside change target (fromPairs cache.pairs)) cache.kindAt cache.count size
      (derivedStart (adjustBeside change target (fromPairs cache.pairs)) cache.kindAt cache.count next size skip slots)
      (valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))) target =
    fromPairs (allPairs (fromPairs cache.pairs) cache.kindAt cache.count size
      (derivedStart (fromPairs cache.pairs) cache.kindAt cache.count next size skip slots)
      (valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))) target := by
  let body := fromPairs cache.pairs
  let changed := adjustBeside change target body
  let jobs := valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count)
  let oldPairs := allPairs body cache.kindAt cache.count size (derivedStart body cache.kindAt cache.count next size skip slots) jobs
  let newPairs := allPairs changed cache.kindAt cache.count size (derivedStart changed cache.kindAt cache.count next size skip slots) jobs
  change fromPairs newPairs target = fromPairs oldPairs target
  cases before : fromPairs oldPairs target with
  | some ident =>
    rcases global_selected body cache.kindAt cache.count place eligible initState size _ target ident before with ⟨job, member, selected⟩
    have stable := selected_global_first_unchanged rounds cache reached place eligible initState job target next size change skip slots member selected
    simpa only [before] using stable
  | none =>
    cases after : fromPairs newPairs target with
    | none => rfl
    | some ident =>
      rcases global_selected changed cache.kindAt cache.count place eligible initState size _ target ident after with ⟨job, member, selected⟩
      have oldSelected : target ∈ candidateKeys body cache.kindAt job.owner cache.count := by
        simpa only [changed, candidateKeys, root_adr0352_i5_rebreak_preserves_selected_keys] using selected
      have stable := selected_global_first_unchanged rounds cache reached place eligible initState job target next size change skip slots member oldSelected
      rw [before, after] at stable
      exact stable
end BesideOwnedGlobal
