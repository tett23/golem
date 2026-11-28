import BesideReuseOrder
import BesideReuseRounds

namespace BesideReuse
open BesideOwnership BesideProducer

def jobsOrdered : List (ReuseJob σ) → Prop
  | [] => True
  | job :: later => (∀ next, next ∈ later → job.owner < next.owner) ∧ jobsOrdered later

private theorem append_member (xs ys : List Nat) (key : Nat) (member : key ∈ xs ++ ys) :
    key ∈ xs ∨ key ∈ ys := by
  induction xs with
  | nil => exact Or.inr member
  | cons head later ih =>
    rcases List.mem_cons.mp member with first | rest
    · exact Or.inl (List.mem_cons.mpr (Or.inl first))
    · rcases ih rest with left | right
      · exact Or.inl (List.mem_cons.mpr (Or.inr left))
      · exact Or.inr right

private theorem increasing_append (xs ys : List Nat) (left : Increasing xs) (right : Increasing ys)
    (between : ∀ x, x ∈ xs → ∀ y, y ∈ ys → x < y) : Increasing (xs ++ ys) := by
  induction xs with
  | nil => exact right
  | cons head later ih =>
    constructor
    · intro key member
      rcases append_member later ys key member with here | there
      · exact left.1 key here
      · exact between head (List.mem_cons_self head later) key there
    · exact ih left.2 (fun x member => between x (List.mem_cons_of_mem head member))

private theorem increasing_unique (keys : List Nat) (ordered : Increasing keys) : NoRepeat keys := by
  induction keys with
  | nil => trivial
  | cons head later ih =>
    constructor
    · intro member
      exact (Nat.lt_irrefl head) (ordered.1 head member)
    · exact ih ordered.2

theorem root_adr0352_i5_mixed_key_has_job
    (available widthsSame : Bool) (oldCount count key : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (jobs : List (ReuseJob σ))
    (member : key ∈ chooseAll available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep jobs) :
    ∃ job, job ∈ jobs ∧ key ∈ chooseKeys available widthsSame oldCount count job.owner body before current extra
      free halt allowed paraStep controlStep job.fuel job.state := by
  induction jobs with
  | nil => simp [chooseAll] at member
  | cons job later ih =>
    rcases append_member _ _ key member with here | there
    · exact ⟨job, List.mem_cons_self job later, here⟩
    · rcases ih there with ⟨next, belongs, selected⟩
      exact ⟨next, List.mem_cons_of_mem job belongs, selected⟩

theorem root_adr0352_i5_mixed_round_keys_increasing
    (available widthsSame : Bool) (oldCount count : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (jobs : List (ReuseJob σ))
    (oldTyped : available = true → ∀ k, (body k).isSome = true → before k = some .paragraph)
    (ordered : jobsOrdered jobs)
    (figures : ∀ job, job ∈ jobs → current job.owner = some .figure) :
    Increasing (chooseAll available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep jobs) := by
  induction jobs with
  | nil => trivial
  | cons job later ih =>
    apply increasing_append
    · exact root_adr0352_i5_chosen_keys_increasing available widthsSame oldCount count job.owner body before current extra
        free halt allowed paraStep controlStep job.fuel job.state
    · exact ih ordered.2 (fun next member => figures next (List.mem_cons_of_mem job member))
    · intro left inLeft right inRight
      rcases root_adr0352_i5_mixed_key_has_job available widthsSame oldCount count right body before current extra
        free halt allowed paraStep controlStep later inRight with ⟨next, member, selected⟩
      exact root_adr0352_i5_ordered_chosen_jobs_separate available widthsSame oldCount count job.owner next.owner left right
        job.fuel next.fuel body before current extra free halt allowed paraStep controlStep job.state next.state
        oldTyped (figures next (List.mem_cons_of_mem job member)) (ordered.1 next member) inLeft selected

theorem root_adr0352_i5_mixed_round_keys_unique
    (available widthsSame : Bool) (oldCount count : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (jobs : List (ReuseJob σ))
    (oldTyped : available = true → ∀ k, (body k).isSome = true → before k = some .paragraph)
    (ordered : jobsOrdered jobs)
    (figures : ∀ job, job ∈ jobs → current job.owner = some .figure) :
    NoRepeat (chooseAll available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep jobs) := by
  exact increasing_unique _ (root_adr0352_i5_mixed_round_keys_increasing available widthsSame oldCount count body before current extra
    free halt allowed paraStep controlStep jobs oldTyped ordered figures)

def roundJobsLegal (round : Round σ) : Prop :=
  jobsOrdered round.jobs ∧ ∀ job, job ∈ round.jobs → round.kindAt job.owner = some .figure

def cacheOrdered (cache : Cache) : Prop := Increasing cache.keys

theorem root_adr0352_i5_next_cache_ordered (previous : Option Cache) (round : Round σ)
    (old : ∀ cache, previous = some cache → cacheTyped cache)
    (legal : roundJobsLegal round) : cacheOrdered (nextCache previous round) := by
  apply root_adr0352_i5_mixed_round_keys_increasing
  · intro available key present
    cases previous with
    | none => contradiction
    | some cache =>
      apply old cache rfl key
      by_cases found : key ∈ cache.keys
      · exact found
      · simp [bodyOf, found] at present
  · exact legal.1
  · exact legal.2

theorem root_adr0352_i5_all_rounds_cache_ordered (rounds : List (Round σ)) (previous : Option Cache)
    (oldTyped : ∀ cache, previous = some cache → cacheTyped cache)
    (oldOrdered : ∀ cache, previous = some cache → cacheOrdered cache)
    (legal : ∀ round, round ∈ rounds → roundJobsLegal round) :
    ∀ cache, runRounds previous rounds = some cache → cacheOrdered cache := by
  induction rounds generalizing previous with
  | nil => exact oldOrdered
  | cons round later ih =>
    apply ih (some (nextCache previous round))
    · intro cache same
      cases same
      exact root_adr0352_i5_next_cache_typed previous round oldTyped
    · intro cache same
      cases same
      exact root_adr0352_i5_next_cache_ordered previous round oldTyped (legal round (List.mem_cons_self round later))
    · intro next member
      exact legal next (List.mem_cons_of_mem round member)

theorem root_adr0352_i5_from_no_cache_ordered (rounds : List (Round σ))
    (legal : ∀ round, round ∈ rounds → roundJobsLegal round) :
    ∀ cache, runRounds none rounds = some cache → cacheOrdered cache := by
  apply root_adr0352_i5_all_rounds_cache_ordered rounds none _ _ legal
  all_goals intro cache impossible; contradiction

theorem root_adr0352_i5_from_no_cache_unique (rounds : List (Round σ))
    (legal : ∀ round, round ∈ rounds → roundJobsLegal round) :
    ∀ cache, runRounds none rounds = some cache → NoRepeat cache.keys := by
  intro cache reached
  exact increasing_unique _ (root_adr0352_i5_from_no_cache_ordered rounds legal cache reached)

end BesideReuse
