import SuffixCountPrefix
namespace BesideLaterEdits
open BesideOwnership BesideProducer BesideReuse BesideFigureTable BesideJobValues BesideClassifiedPrefix BesideOwnedUnion BesideBodyEdits BesideOwnedFirst BesideSuffixCountPrefix BesidePayloadRounds BesideStore

private theorem union_none (table : Nat → Option Nat) (target : Nat) : leftUnion table (fun _ => none) target = table target := by
  cases value : table target <;> simp only [leftUnion, value]

private theorem one_same
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target : Nat) (edit : BodyEdit α) (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count) (notEarlier : target ≤ edit.target) :
    ownedTable (adjustBeside edit.change edit.target body) current count next size skip slots place eligible initState target =
      ownedTable body current count next size skip slots place eligible initState target := by
  rcases root_adr0352_i5_later_update_preserves_existing_union_first body current count next typed place eligible initState job target edit.target size edit.change skip slots
    (fun _ => none) (fun _ => none) member selected notEarlier with ⟨ident, oldSome, newSome⟩
  rw [union_none] at oldSome newSome
  exact newSome.trans oldSome.symm

theorem root_adr0352_i5_later_edit_histories_first_same
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target : Nat) (edits : List (BodyEdit α)) (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count)
    (notEarlier : ∀ edit ∈ edits, target ≤ edit.target) :
    ownedTable (applyEdits body edits) current count next size skip slots place eligible initState target =
      ownedTable body current count next size skip slots place eligible initState target := by
  induction edits generalizing body with
  | nil => rfl
  | cons edit later ih =>
    have changedTyped : ∀ key, (adjustBeside edit.change edit.target body key).isSome = true → current key = some .paragraph := by
      intro key present
      rw [root_adr0352_i5_adjust_preserves_domain] at present
      exact typed key present
    have changedSelected : target ∈ candidateKeys (adjustBeside edit.change edit.target body) current job.owner count := by
      rw [candidateKeys, root_adr0352_i5_rebreak_preserves_selected_keys]
      exact selected
    have rest : ∀ other ∈ later, target ≤ other.target := fun other belongs => notEarlier other (List.mem_cons_of_mem edit belongs)
    change ownedTable (applyEdits (adjustBeside edit.change edit.target body) later) current count next size skip slots place eligible initState target = _
    exact (ih _ changedTyped changedSelected rest).trans (one_same body current count next typed place eligible initState job target edit size skip slots member selected (notEarlier edit (List.mem_cons_self edit later)))

private theorem after_above (keys : List Nat) (target key : Nat) (ordered : Increasing keys)
    (member : key ∈ afterTarget target keys) : target < key := by
  induction keys with
  | nil => simp [afterTarget] at member
  | cons head later ih =>
    by_cases same : head = target
    · subst head
      exact ordered.1 key (by simpa [afterTarget] using member)
    · exact ih ordered.2 (by simpa [afterTarget, same] using member)

private theorem member_take (keys : List Nat) (count key : Nat) (member : key ∈ keys.take count) : key ∈ keys := by
  induction count generalizing keys with
  | zero => simp [List.take] at member
  | succ count ih =>
    cases keys with
    | nil => simp [List.take] at member
    | cons head later =>
      change key ∈ head :: later.take count at member
      rcases List.mem_cons.mp member with first | rest
      · exact List.mem_cons.mpr (Or.inl first)
      · exact List.mem_cons.mpr (Or.inr (ih later rest))

noncomputable def suffixPrefixEdits (keys : List Nat) (target count : Nat) (changeAt : Nat → α → α) : List (BodyEdit α) :=
  ((target :: afterTarget target keys).take count).map (fun key => ⟨key, changeAt key⟩)

theorem root_adr0352_i5_selected_suffix_prefix_first_same
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target attempts : Nat) (changeAt : Nat → α → α) (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count) :
    ownedTable (applyEdits body (suffixPrefixEdits (candidateKeys body current job.owner count) target attempts changeAt)) current count next size skip slots place eligible initState target =
      ownedTable body current count next size skip slots place eligible initState target := by
  apply root_adr0352_i5_later_edit_histories_first_same body current count next typed place eligible initState job target _ size skip slots member selected
  intro edit belongs
  rcases List.mem_map.mp belongs with ⟨key, inTake, equal⟩
  subst edit
  have keysMember := member_take (target :: afterTarget target (candidateKeys body current job.owner count)) attempts key inTake
  rcases List.mem_cons.mp keysMember with first | later
  · subst key; exact Nat.le_refl target
  · have ordered := root_adr0352_i5_beside_key_order (classes body (controlAt current) (job.owner + 1) (count - (job.owner + 1))) (job.owner + 1)
    have laterBound := after_above (candidateKeys body current job.owner count) target key ordered later
    exact Nat.le_of_lt laterBound

theorem root_adr0352_i5_history_suffix_prefix_exists_same
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache) (prior : List (BodyEdit α))
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target next attempts : Nat) (changeAt : Nat → α → α)
    (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot) (beginBase endBase : Nat → Option Nat)
    (member : job ∈ valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))
    (selected : target ∈ candidateKeys (fromPairs cache.pairs) cache.kindAt job.owner cache.count) :
    let body := applyEdits (fromPairs cache.pairs) prior
    ∃ ident,
      leftUnion (ownedTable body cache.kindAt cache.count next size skip slots place eligible initState) beginBase target = some ident ∧
      leftUnion (ownedTable (applyEdits body (suffixPrefixEdits (candidateKeys body cache.kindAt job.owner cache.count) target attempts changeAt)) cache.kindAt cache.count next size skip slots place eligible initState) endBase target = some ident := by
  let body := applyEdits (fromPairs cache.pairs) prior
  have typed : ∀ key, (body key).isSome = true → cache.kindAt key = some .paragraph := root_adr0352_i5_reached_body_edits_typed rounds cache reached prior
  have currentSelected : target ∈ candidateKeys body cache.kindAt job.owner cache.count := by
    rw [root_adr0352_i5_body_edits_selected]
    exact selected
  rcases root_adr0352_i5_later_update_preserves_existing_union_first body cache.kindAt cache.count next typed place eligible initState job target target size id skip slots
    (fun _ => none) (fun _ => none) member currentSelected (Nat.le_refl target) with ⟨ident, firstSome, _⟩
  rw [union_none] at firstSome
  have endSome := (root_adr0352_i5_selected_suffix_prefix_first_same body cache.kindAt cache.count next typed place eligible initState job target attempts changeAt size skip slots member currentSelected).trans firstSome
  exact ⟨ident, by simp only [leftUnion, firstSome], by simp only [leftUnion, endSome]⟩
end BesideLaterEdits
