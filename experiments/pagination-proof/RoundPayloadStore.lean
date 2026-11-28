import MixedRoundOrder

namespace BesideStore
open BesideOwnership BesideProducer BesideReuse

def pairKeys : List (Nat × α) → List Nat
  | [] => []
  | (key, _) :: later => key :: pairKeys later

-- Repeated keys take their last value, matching the observed container API.
def fromPairs : List (Nat × α) → Nat → Option α
  | [], _ => none
  | (key, value) :: later, wanted =>
    match fromPairs later wanted with
    | some last => some last
    | none => if wanted = key then some value else none

def readPairs : List Nat → (Nat → Option α) → List (Nat × α)
  | [], _ => []
  | key :: later, table =>
    match table key with
    | none => readPairs later table
    | some value => (key, value) :: readPairs later table

theorem root_adr0352_i5_store_missing_key (pairs : List (Nat × α)) (key : Nat)
    (absent : key ∉ pairKeys pairs) : fromPairs pairs key = none := by
  induction pairs with
  | nil => rfl
  | cons pair later ih =>
    rcases pair with ⟨head, value⟩
    have different : key ≠ head := by
      intro same; subst key; exact absent (List.mem_cons_self head (pairKeys later))
    have rest : key ∉ pairKeys later := fun member => absent (List.mem_cons_of_mem head member)
    simp only [fromPairs, ih rest, different, if_false]

theorem root_adr0352_i5_unique_payload_retained (pairs : List (Nat × α)) (key : Nat) (value : α)
    (unique : NoRepeat (pairKeys pairs)) (member : (key, value) ∈ pairs) : fromPairs pairs key = some value := by
  induction pairs with
  | nil => simp at member
  | cons pair later ih =>
    rcases pair with ⟨head, first⟩
    rcases List.mem_cons.mp member with same | rest
    · cases same
      have absent := root_adr0352_i5_store_missing_key later key unique.1
      simp [fromPairs, absent]
    · have found := ih unique.2 rest
      simp only [fromPairs, found]

private theorem read_known (pairs : List (Nat × α)) (table : Nat → Option α)
    (known : ∀ key value, (key, value) ∈ pairs → table key = some value) : readPairs (pairKeys pairs) table = pairs := by
  induction pairs with
  | nil => rfl
  | cons pair later ih =>
    rcases pair with ⟨key, value⟩
    have head := known key value (List.mem_cons_self _ later)
    have rest := ih (fun k v member => known k v (List.mem_cons_of_mem (key, value) member))
    simp only [pairKeys, readPairs, head, rest]

theorem root_adr0352_i5_unique_readback (pairs : List (Nat × α)) (unique : NoRepeat (pairKeys pairs)) :
    readPairs (pairKeys pairs) (fromPairs pairs) = pairs := by
  apply read_known
  intro key value member
  exact root_adr0352_i5_unique_payload_retained pairs key value unique member

theorem root_adr0352_i5_mixed_round_payload_readback
    (available widthsSame : Bool) (oldCount count : Nat)
    (body : Nat → Option β) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (jobs : List (ReuseJob σ)) (pairs : List (Nat × α))
    (oldTyped : available = true → ∀ k, (body k).isSome = true → before k = some .paragraph)
    (ordered : jobsOrdered jobs) (figures : ∀ job, job ∈ jobs → current job.owner = some .figure)
    (keys : pairKeys pairs = chooseAll available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep jobs) :
    readPairs (chooseAll available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep jobs) (fromPairs pairs) = pairs := by
  have unique : NoRepeat (pairKeys pairs) := by
    rw [keys]
    exact root_adr0352_i5_mixed_round_keys_unique available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep jobs oldTyped ordered figures
  rw [← keys]
  exact root_adr0352_i5_unique_readback pairs unique

theorem root_adr0352_i5_cached_payload_readback (rounds : List (Round σ))
    (legal : ∀ round, round ∈ rounds → roundJobsLegal round) (cache : Cache)
    (reached : runRounds none rounds = some cache) (pairs : List (Nat × α))
    (keys : pairKeys pairs = cache.keys) : readPairs cache.keys (fromPairs pairs) = pairs := by
  have unique : NoRepeat (pairKeys pairs) := by
    rw [keys]
    exact root_adr0352_i5_from_no_cache_unique rounds legal cache reached
  rw [← keys]
  exact root_adr0352_i5_unique_readback pairs unique

end BesideStore
