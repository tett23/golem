import OwnedFirstScan
namespace BesideOwnedRows
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideOwnedScan

def allKeys (body : Nat → Option α) (current : Nat → Option Kind) (count : Nat) : List (ReuseJob σ) → List Nat
  | [] => []
  | job :: later => candidateKeys body current job.owner count ++ allKeys body current count later

private theorem append_member (xs ys : List Nat) (key : Nat) (member : key ∈ xs ++ ys) : key ∈ xs ∨ key ∈ ys := by
  induction xs with
  | nil => exact Or.inr member
  | cons head later ih =>
    rcases List.mem_cons.mp member with first | rest
    · exact Or.inl (List.mem_cons.mpr (Or.inl first))
    · rcases ih rest with here | there
      · exact Or.inl (List.mem_cons.mpr (Or.inr here))
      · exact Or.inr there

private theorem append_increasing (xs ys : List Nat) (left : Increasing xs) (right : Increasing ys)
    (between : ∀ x, x ∈ xs → ∀ y, y ∈ ys → x < y) : Increasing (xs ++ ys) := by
  induction xs with
  | nil => exact right
  | cons head later ih =>
    refine ⟨?_, ih left.2 (fun x member => between x (List.mem_cons_of_mem head member))⟩
    intro key member
    rcases append_member _ _ _ member with here | there
    · exact left.1 key here
    · exact between head (List.mem_cons_self head later) key there

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

theorem root_adr0352_i5_all_owned_keys_increasing
    (body : Nat → Option α) (current : Nat → Option Kind) (count : Nat) (jobs : List (ReuseJob σ))
    (typed : ∀ k, (body k).isSome = true → current k = some .paragraph)
    (ordered : jobsOrdered jobs) (figures : ∀ job, job ∈ jobs → current job.owner = some .figure) :
    Increasing (allKeys body current count jobs) := by
  induction jobs with
  | nil => trivial
  | cons job later ih =>
    apply append_increasing
    · exact root_adr0352_i5_beside_key_order _ _
    · exact ih ordered.2 (fun other belongs => figures other (List.mem_cons_of_mem _ belongs))
    · intro left inLeft right inRight
      rcases belongs_job body current count right later inRight with ⟨other, belongs, selected⟩
      have before : left < other.owner := by
        apply root_adr0352_i5_typed_scan_before_figure body current (job.owner + 1) (count - (job.owner + 1)) other.owner left
          (figures other (List.mem_cons_of_mem _ belongs)) (by have h := ordered.1 other belongs; omega) _ inLeft
        intro key hit
        exact typed key (root_adr0352_i5_candidate_keys_exist body (controlAt current) (job.owner + 1) (count - (job.owner + 1)) key hit)
      have after := root_adr0352_i5_beside_key_range (classes body (controlAt current) (other.owner + 1) (count - (other.owner + 1))) (other.owner + 1) right selected
      omega
end BesideOwnedRows
namespace BesideOwnedRows
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideOwnedFirst

theorem root_adr0352_i5_reached_all_owned_keys_increasing
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ) :
    Increasing (allKeys (fromPairs cache.pairs) cache.kindAt cache.count
      (valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))) := by
  apply root_adr0352_i5_all_owned_keys_increasing
  · exact root_adr0352_i5_payload_from_empty_typed rounds cache reached
  · exact root_adr0352_i5_value_jobs_ordered eligible initState cache.count _
      (BesideFigureWindow.root_adr0352_i5_figure_pairs_keys_increasing cache.kindAt place 0 cache.count)
  · intro job member
    exact root_adr0352_i5_owner_figure_from_job cache.kindAt cache.count place eligible initState job member
end BesideOwnedRows

namespace BesideOwnedRows
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideOwnedScan

noncomputable def allPairs (body : Nat → Option α) (current : Nat → Option Kind) (count : Nat) (size : α → Nat)
    (startOf : Nat → Nat) : List (ReuseJob σ) → List (Nat × Nat)
  | [] => []
  | job :: later => numberPairs (candidateKeys body current job.owner count) (rowCount size body) (startOf job.owner) ++
      allPairs body current count size startOf later

private theorem number_keys (keys : List Nat) (countOf : Nat → Nat) (next : Nat) :
    pairKeys (numberPairs keys countOf next) = keys := by
  induction keys generalizing next with
  | nil => rfl
  | cons key later ih => simp only [numberPairs, pairKeys, ih]

private theorem pairKeys_append (left right : List (Nat × α)) : pairKeys (left ++ right) = pairKeys left ++ pairKeys right := by
  induction left with
  | nil => rfl
  | cons head later ih =>
    rcases head with ⟨key, _value⟩
    change key :: pairKeys (later ++ right) = key :: (pairKeys later ++ pairKeys right)
    rw [ih]

theorem root_adr0352_i5_all_owned_pairs_keys
    (body : Nat → Option α) (current : Nat → Option Kind) (count : Nat) (size : α → Nat)
    (startOf : Nat → Nat) (jobs : List (ReuseJob σ)) :
    pairKeys (allPairs body current count size startOf jobs) = allKeys body current count jobs := by
  induction jobs with
  | nil => rfl
  | cons job later ih => simp only [allPairs, pairKeys_append, number_keys, ih, allKeys]

private theorem increasing_unique (keys : List Nat) (ordered : Increasing keys) : NoRepeat keys := by
  induction keys with
  | nil => trivial
  | cons key later ih =>
    refine ⟨?_, ih ordered.2⟩
    intro member
    exact (Nat.lt_irrefl key) (ordered.1 key member)

theorem root_adr0352_i5_reached_all_owned_pairs_unique
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ) (size : α → Nat) (startOf : Nat → Nat) :
    NoRepeat (pairKeys (allPairs (fromPairs cache.pairs) cache.kindAt cache.count size startOf
      (valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count)))) := by
  rw [root_adr0352_i5_all_owned_pairs_keys]
  exact increasing_unique _ (root_adr0352_i5_reached_all_owned_keys_increasing rounds cache reached place eligible initState)
end BesideOwnedRows

namespace BesideOwnedRows
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable BesideJobValues BesideOwnedScan

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

theorem root_adr0352_i5_reached_owned_pair_retained
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ) (size : α → Nat) (startOf : Nat → Nat)
    (job : ReuseJob τ) (key ident : Nat)
    (member : job ∈ valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))
    (localPair : (key, ident) ∈ numberPairs (candidateKeys (fromPairs cache.pairs) cache.kindAt job.owner cache.count)
      (rowCount size (fromPairs cache.pairs)) (startOf job.owner)) :
    fromPairs (allPairs (fromPairs cache.pairs) cache.kindAt cache.count size startOf
      (valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))) key = some ident := by
  apply root_adr0352_i5_unique_payload_retained
  · exact root_adr0352_i5_reached_all_owned_pairs_unique rounds cache reached place eligible initState size startOf
  · exact member_all_pairs _ _ _ _ _ _ job key ident member localPair
end BesideOwnedRows
