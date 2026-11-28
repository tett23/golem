import ClassifiedPrefix
namespace BesideOwnedFirst
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideClassifiedPrefix CausalFirstIds

def beforeTarget (target : Nat) : List Nat → List Nat
  | [] => []
  | key :: later => if key = target then [] else key :: beforeTarget target later

def afterTarget (target : Nat) : List Nat → List Nat
  | [] => []
  | key :: later => if key = target then later else afterTarget target later

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

private theorem pair_member_key (rows : List (Nat × α)) (key : Nat) (value : α) (member : (key, value) ∈ rows) : key ∈ pairKeys rows := by
  induction rows with
  | nil => simp at member
  | cons head later ih =>
    rcases head with ⟨first, item⟩
    rcases List.mem_cons.mp member with atHead | inTail
    · cases atHead; exact List.mem_cons_self _ _
    · exact List.mem_cons_of_mem first (ih inTail)

theorem root_adr0352_i5_owner_figure_from_job
    (kindAt : Nat → Option Kind) (count : Nat) (place : Nat → Option ρ) (eligible : ρ → Bool)
    (initState : Nat → ρ → τ) (job : ReuseJob τ)
    (member : job ∈ valueJobs eligible initState count (figurePairs kindAt place 0 count)) :
    kindAt job.owner = some .figure := by
  rcases root_adr0352_i5_value_job_source eligible initState count _ job member with ⟨value, belongs, _⟩
  exact (root_adr0352_i5_figure_pair_source kindAt place 0 count job.owner (pair_member_key _ job.owner value belongs)).2.2

def ownedFirstId (body : Nat → Option α) (current : Nat → Option Kind) (count owner target next : Nat)
    (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot) : Option Nat :=
  let keys := candidateKeys body current owner count
  if target ∈ keys then
    besideFromTwoPass (unitContributions body current count size (classifiedParts body skip 0 (slots.take owner))) []
      (countsFor (beforeTarget target keys) (rowCount size body))
      (countsFor (afterTarget target keys) (rowCount size body)) (rowCount size body target) next
  else none

theorem root_adr0352_i5_reached_owned_first_unchanged
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ) (job : ReuseJob τ)
    (member : job ∈ valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))
    (target next : Nat) (size : α → Nat) (change : α → α) (skip : Nat → Bool) (slots : List CountSlot) :
    ownedFirstId (adjustBeside change target (fromPairs cache.pairs)) cache.kindAt cache.count job.owner target next size skip slots =
      ownedFirstId (fromPairs cache.pairs) cache.kindAt cache.count job.owner target next size skip slots := by
  let body := fromPairs cache.pairs
  have sameKeys : candidateKeys (adjustBeside change target body) cache.kindAt job.owner cache.count =
      candidateKeys body cache.kindAt job.owner cache.count :=
    root_adr0352_i5_rebreak_preserves_selected_keys change target (job.owner + 1) (cache.count - (job.owner + 1))
      body (BesideProducer.controlAt cache.kindAt)
  change ownedFirstId (adjustBeside change target body) cache.kindAt cache.count job.owner target next size skip slots =
    ownedFirstId body cache.kindAt cache.count job.owner target next size skip slots
  unfold ownedFirstId
  rw [sameKeys]
  by_cases selected : target ∈ candidateKeys body cache.kindAt job.owner cache.count
  · simp only [selected, if_true]
    have figure := root_adr0352_i5_owner_figure_from_job cache.kindAt cache.count place eligible initState job member
    have outer := root_adr0352_i5_reached_classified_prior_prefix rounds cache reached job.owner target size change skip slots figure selected
    have split := split_selected (candidateKeys body cache.kindAt job.owner cache.count) target selected
    have inner := root_adr0352_i5_selected_count_prefix
      (classes body (BesideProducer.controlAt cache.kindAt) (job.owner + 1) (cache.count - (job.owner + 1)))
      (job.owner + 1) target (beforeTarget target (candidateKeys body cache.kindAt job.owner cache.count))
      (afterTarget target (candidateKeys body cache.kindAt job.owner cache.count)) size body change split
    rw [root_adr0352_i5_two_pass_first_value, root_adr0352_i5_two_pass_first_value, outer, inner]
  · simp only [selected, if_false]

end BesideOwnedFirst
