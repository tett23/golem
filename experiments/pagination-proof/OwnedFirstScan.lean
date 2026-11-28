import OwnedFirst
namespace BesideOwnedScan
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideClassifiedPrefix BesideOwnedFirst CausalFirstIds

def numberPairs : List Nat → (Nat → Nat) → Nat → List (Nat × Nat)
  | [], _, _ => []
  | key :: later, countOf, next => (key, next) :: numberPairs later countOf (next + countOf key)

private theorem number_keys (keys : List Nat) (countOf : Nat → Nat) (next : Nat) :
    pairKeys (numberPairs keys countOf next) = keys := by
  induction keys generalizing next with
  | nil => rfl
  | cons key later ih => simp only [numberPairs, pairKeys, ih]

private theorem number_lookup (keys : List Nat) (countOf : Nat → Nat) (target next : Nat)
    (unique : NoRepeat keys) :
    fromPairs (numberPairs keys countOf next) target =
      if target ∈ keys then some ((countsFor (beforeTarget target keys) countOf).foldl Nat.add next) else none := by
  induction keys generalizing next with
  | nil => simp [numberPairs, fromPairs]
  | cons key later ih =>
    by_cases same : target = key
    · subst target
      have missing := root_adr0352_i5_store_missing_key (numberPairs later countOf (next + countOf key)) key
        (by simpa only [number_keys] using unique.1)
      simp [numberPairs, fromPairs, missing, beforeTarget, countsFor]
    · have tail := ih (next + countOf key) unique.2
      simp only [numberPairs, fromPairs, tail]
      by_cases member : target ∈ later
      · simp [member, same, beforeTarget, Ne.symm same, countsFor]
      · simp [member, same]

noncomputable def storedOwnedFirst (body : Nat → Option α) (current : Nat → Option Kind) (count owner target next : Nat)
    (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot) : Option Nat :=
  fromPairs (numberPairs (candidateKeys body current owner count) (rowCount size body)
    ((unitContributions body current count size (classifiedParts body skip 0 (slots.take owner))).foldl Nat.add next + 1)) target

theorem root_adr0352_i5_owned_first_scan (body : Nat → Option α) (current : Nat → Option Kind) (count owner target next : Nat)
    (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot) :
    storedOwnedFirst body current count owner target next size skip slots =
      ownedFirstId body current count owner target next size skip slots := by
  unfold storedOwnedFirst
  have unique : NoRepeat (candidateKeys body current owner count) := root_adr0352_i5_beside_keys_unique _ _
  rw [number_lookup _ _ _ _ unique]
  by_cases member : target ∈ candidateKeys body current owner count
  · simp only [ownedFirstId, member, if_true, root_adr0352_i5_two_pass_first_value]
  · simp only [ownedFirstId, member, if_false]
end BesideOwnedScan

namespace BesideOwnedScan
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideClassifiedPrefix BesideOwnedFirst

theorem root_adr0352_i5_reached_owned_first_store_unchanged
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ) (job : ReuseJob τ)
    (member : job ∈ valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))
    (target next : Nat) (size : α → Nat) (change : α → α) (skip : Nat → Bool) (slots : List CountSlot) :
    storedOwnedFirst (adjustBeside change target (fromPairs cache.pairs)) cache.kindAt cache.count job.owner target next size skip slots =
      storedOwnedFirst (fromPairs cache.pairs) cache.kindAt cache.count job.owner target next size skip slots := by
  rw [root_adr0352_i5_owned_first_scan, root_adr0352_i5_owned_first_scan]
  exact root_adr0352_i5_reached_owned_first_unchanged rounds cache reached place eligible initState job member target next size change skip slots
end BesideOwnedScan
