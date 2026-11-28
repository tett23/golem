import OwnedGlobal
namespace BesideOwnedUnion
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideFigureWindow BesideJobValues BesideClassifiedPrefix BesideOwnedFirst BesideOwnedScan BesideOwnedRows BesideOwnedGlobal CausalFirstIds

def leftUnion (owned base : Nat → Option Nat) (key : Nat) : Option Nat :=
  match owned key with
  | some ident => some ident
  | none => base key

noncomputable def ownedTable (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ) : Nat → Option Nat :=
  fromPairs (allPairs body current count size (derivedStart body current count next size skip slots)
    (valueJobs eligible initState count (figurePairs current place 0 count)))

theorem root_adr0352_i5_selected_union_first_exists_unchanged
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target next : Nat) (size : α → Nat) (change : α → α)
    (skip : Nat → Bool) (slots : List CountSlot) (oldBase newBase : Nat → Option Nat)
    (member : job ∈ valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))
    (selected : target ∈ candidateKeys (fromPairs cache.pairs) cache.kindAt job.owner cache.count) :
    ∃ ident,
      leftUnion (ownedTable (fromPairs cache.pairs) cache.kindAt cache.count next size skip slots place eligible initState) oldBase target = some ident ∧
      leftUnion (ownedTable (adjustBeside change target (fromPairs cache.pairs)) cache.kindAt cache.count next size skip slots place eligible initState) newBase target = some ident := by
  let body := fromPairs cache.pairs
  let ident := (countsFor (beforeTarget target (candidateKeys body cache.kindAt job.owner cache.count)) (rowCount size body)).foldl Nat.add
    (derivedStart body cache.kindAt cache.count next size skip slots job.owner)
  have localSome : storedOwnedFirst body cache.kindAt cache.count job.owner target next size skip slots = some ident := by
    rw [root_adr0352_i5_owned_first_scan]
    simp only [ownedFirstId, selected, if_true, root_adr0352_i5_two_pass_first_value]
    rfl
  have oldSome : ownedTable body cache.kindAt cache.count next size skip slots place eligible initState target = some ident :=
    (root_adr0352_i5_global_lookup_at_owned_target body cache.kindAt cache.count next
      (root_adr0352_i5_payload_from_empty_typed rounds cache reached) place eligible initState size skip slots job target member selected).trans localSome
  have newSome : ownedTable (adjustBeside change target body) cache.kindAt cache.count next size skip slots place eligible initState target = some ident :=
    (root_adr0352_i5_reached_global_first_unchanged rounds cache reached place eligible initState target next size change skip slots).trans oldSome
  exact ⟨ident, by simp only [leftUnion, oldSome], by simp only [leftUnion, newSome]⟩
end BesideOwnedUnion
