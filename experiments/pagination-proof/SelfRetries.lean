import HistoryFirst
namespace BesideSelfRetries
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideClassifiedPrefix BesideOwnedUnion BesideBodyEdits BesideHistoryFirst

def selfEdits (target : Nat) : List (α → α) → List (BodyEdit α)
  | [] => []
  | change :: later => ⟨target, change⟩ :: selfEdits target later

private theorem union_none (table : Nat → Option Nat) (target : Nat) : leftUnion table (fun _ => none) target = table target := by
  cases value : table target <;> simp only [leftUnion, value]

private theorem typed_step_same
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target : Nat) (size : α → Nat) (change : α → α) (skip : Nat → Bool) (slots : List CountSlot)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count) :
    ownedTable (adjustBeside change target body) current count next size skip slots place eligible initState target =
      ownedTable body current count next size skip slots place eligible initState target := by
  rcases root_adr0352_i5_typed_selected_union_exists_stable body current count next typed place eligible initState job target size change skip slots
    (fun _ => none) (fun _ => none) member selected with ⟨ident, oldSome, newSome⟩
  rw [union_none] at oldSome newSome
  exact newSome.trans oldSome.symm

theorem root_adr0352_i5_typed_self_retry_id_same
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target : Nat) (size : α → Nat) (changes : List (α → α)) (skip : Nat → Bool) (slots : List CountSlot)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count) :
    ownedTable (applyEdits body (selfEdits target changes)) current count next size skip slots place eligible initState target =
      ownedTable body current count next size skip slots place eligible initState target := by
  induction changes generalizing body with
  | nil => rfl
  | cons change later ih =>
    have changedTyped : ∀ key, (adjustBeside change target body key).isSome = true → current key = some .paragraph := by
      intro key present
      rw [root_adr0352_i5_adjust_preserves_domain] at present
      exact typed key present
    have changedSelected : target ∈ candidateKeys (adjustBeside change target body) current job.owner count := by
      rw [candidateKeys, root_adr0352_i5_rebreak_preserves_selected_keys]
      exact selected
    change ownedTable (applyEdits (adjustBeside change target body) (selfEdits target later)) current count next size skip slots place eligible initState target = _
    exact (ih _ changedTyped changedSelected).trans (typed_step_same body current count next typed place eligible initState job target size change skip slots member selected)

theorem root_adr0352_i5_history_then_self_retries_id_exists_same
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache) (prior : List (BodyEdit α))
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target next : Nat) (size : α → Nat) (changes : List (α → α))
    (skip : Nat → Bool) (slots : List CountSlot) (beginBase endBase : Nat → Option Nat)
    (member : job ∈ valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))
    (selected : target ∈ candidateKeys (fromPairs cache.pairs) cache.kindAt job.owner cache.count) :
    ∃ ident,
      leftUnion (ownedTable (applyEdits (fromPairs cache.pairs) prior) cache.kindAt cache.count next size skip slots place eligible initState) beginBase target = some ident ∧
      leftUnion (ownedTable (applyEdits (applyEdits (fromPairs cache.pairs) prior) (selfEdits target changes)) cache.kindAt cache.count next size skip slots place eligible initState) endBase target = some ident := by
  let body := applyEdits (fromPairs cache.pairs) prior
  have typed : ∀ key, (body key).isSome = true → cache.kindAt key = some .paragraph := root_adr0352_i5_reached_body_edits_typed rounds cache reached prior
  have currentSelected : target ∈ candidateKeys body cache.kindAt job.owner cache.count := by
    rw [root_adr0352_i5_body_edits_selected]
    exact selected
  rcases root_adr0352_i5_typed_selected_union_exists_stable body cache.kindAt cache.count next typed place eligible initState job target size id skip slots
    (fun _ => none) (fun _ => none) member currentSelected with ⟨ident, beginSome, _⟩
  rw [union_none] at beginSome
  have endSome := (root_adr0352_i5_typed_self_retry_id_same body cache.kindAt cache.count next typed place eligible initState job target size changes skip slots member currentSelected).trans beginSome
  exact ⟨ident, by simp only [leftUnion, beginSome], by simp only [leftUnion, endSome]⟩
end BesideSelfRetries
