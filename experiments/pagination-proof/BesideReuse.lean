import BesideAdjustment
import BesideProducer

namespace BesideReuse
open BesideOwnership BesideProducer

def lastKey : Nat → List Nat → Nat
  | fallback, [] => fallback
  | _, head :: later => lastKey head later

def allIndices : Nat → (Nat → Bool) → Bool
  | 0, _ => true
  | count + 1, test => allIndices count test && test count

def allBetween (first last count : Nat) (test : Nat → Bool) : Bool :=
  allIndices count (fun key => if first ≤ key ∧ key ≤ last then test key else true)

def candidateKeys (body : Nat → Option α) (current : Nat → Option Kind) (owner count : Nat) : List Nat :=
  scan (owner + 1) (classes body (controlAt current) (owner + 1) (count - (owner + 1)))

def sameAt (before current : Nat → Option Kind) (extra : Nat → Bool) (key : Nat) : Bool :=
  decide (before key = current key) && extra key

def reuseAllowed (available widthsSame : Bool) (oldCount count owner : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool) : Bool :=
  available && (decide (oldCount = count) && (widthsSame &&
    allBetween owner (lastKey (owner + 1) (candidateKeys body current owner count) + 1) count
      (sameAt before current extra)))

private theorem classes_length (body : Nat → Option α) (control : Nat → Bool) (start count : Nat) :
    (classes body control start count).length = count := by
  induction count generalizing start <;> simp [classes, *]

private theorem lastKey_mem (keys : List Nat) (fallback : Nat) (nonempty : keys ≠ []) :
    lastKey fallback keys ∈ keys := by
  induction keys generalizing fallback with
  | nil => contradiction
  | cons head later ih =>
    by_cases empty : later = []
    · subst later; simp [lastKey]
    · exact List.mem_cons_of_mem head (ih head empty)

private theorem member_le_last (keys : List Nat) (key fallback : Nat) (ordered : Increasing keys)
    (member : key ∈ keys) : key ≤ lastKey fallback keys := by
  induction keys generalizing fallback with
  | nil => simp at member
  | cons head later ih =>
    change key ≤ lastKey head later
    rcases List.mem_cons.mp member with same | rest
    · subst key
      by_cases empty : later = []
      · subst later; simp [lastKey]
      · exact Nat.le_of_lt (ordered.1 _ (lastKey_mem later head empty))
    · exact ih head ordered.2 rest

private theorem allIndices_member (count key : Nat) (test : Nat → Bool)
    (valid : key < count) (passed : allIndices count test = true) : test key = true := by
  induction count generalizing key with
  | zero => exact (Nat.not_lt_zero key valid).elim
  | succ count ih =>
    have both : allIndices count test = true ∧ test count = true := by simpa [allIndices] using passed
    by_cases same : key = count
    · subst key; exact both.2
    · exact ih key (by omega) both.1

private theorem allBetween_member (first last count key : Nat) (test : Nat → Bool)
    (valid : key < count) (lower : first ≤ key) (upper : key ≤ last)
    (passed : allBetween first last count test = true) : test key = true := by
  have hit := allIndices_member count key _ valid passed
  simpa [lower, upper] using hit

theorem root_adr0352_i5_candidate_keys_exist (body : Nat → Option α) (control : Nat → Bool)
    (start count key : Nat) (member : key ∈ scan start (classes body control start count)) :
    (body key).isSome = true := by
  induction count generalizing start with
  | zero => simp [classes, scan] at member
  | succ count ih =>
    cases present : (body start).isSome with
    | true =>
      simp only [classes, scan, present, if_true, List.mem_cons] at member
      rcases member with same | rest
      · subst key; exact present
      · exact ih (start + 1) rest
    | false =>
      cases controlHere : control start with
      | true =>
        simp only [classes, scan, present, if_false, controlHere, if_true] at member
        exact ih (start + 1) member
      | false => simp [classes, scan, present, controlHere] at member

theorem root_adr0352_i5_reuse_guard_covers_keys
    (available widthsSame : Bool) (oldCount count owner key : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (passed : reuseAllowed available widthsSame oldCount count owner body before current extra = true)
    (member : key ∈ candidateKeys body current owner count) : sameAt before current extra key = true := by
  have guard : allBetween owner (lastKey (owner + 1) (candidateKeys body current owner count) + 1) count
      (sameAt before current extra) = true := by
    simpa [reuseAllowed] using (show available = true ∧ oldCount = count ∧ widthsSame = true ∧
      allBetween owner (lastKey (owner + 1) (candidateKeys body current owner count) + 1) count
        (sameAt before current extra) = true from by simpa [reuseAllowed] using passed).2.2.2
  have bounds := root_adr0352_i5_beside_key_range
    (classes body (controlAt current) (owner + 1) (count - (owner + 1))) (owner + 1) key member
  rw [classes_length] at bounds
  have inBounds : key < count := by omega
  have ordered := root_adr0352_i5_beside_key_order
    (classes body (controlAt current) (owner + 1) (count - (owner + 1))) (owner + 1)
  have upper := member_le_last (candidateKeys body current owner count) key (owner + 1) ordered member
  exact allBetween_member owner _ count key _ inBounds (by omega) (by omega) guard

theorem root_adr0352_i5_reused_keys_current_paragraphs
    (available widthsSame : Bool) (oldCount count owner key : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (oldTyped : ∀ k, (body k).isSome = true → before k = some .paragraph)
    (passed : reuseAllowed available widthsSame oldCount count owner body before current extra = true)
    (member : key ∈ candidateKeys body current owner count) : current key = some .paragraph := by
  have hit := root_adr0352_i5_reuse_guard_covers_keys available widthsSame oldCount count owner key body before current extra passed member
  have equal : before key = current key := by simpa [sameAt] using (show before key = current key ∧ extra key = true from by simpa [sameAt] using hit).1
  have old := oldTyped key (root_adr0352_i5_candidate_keys_exist body (controlAt current)
    (owner + 1) (count - (owner + 1)) key member)
  rw [← equal]
  exact old

theorem root_adr0352_i5_reuse_global_guards
    (available widthsSame : Bool) (oldCount count owner : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (passed : reuseAllowed available widthsSame oldCount count owner body before current extra = true) :
    available = true ∧ oldCount = count ∧ widthsSame = true := by
  have all : available = true ∧ oldCount = count ∧ widthsSame = true ∧
      allBetween owner (lastKey (owner + 1) (candidateKeys body current owner count) + 1) count
        (sameAt before current extra) = true := by simpa [reuseAllowed] using passed
  exact ⟨all.1, all.2.1, all.2.2.1⟩

structure ReuseJob (σ : Type) where
  owner : Nat
  fuel : Nat
  state : σ

def chooseKeys (available widthsSame : Bool) (oldCount count owner : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (fuel : Nat) (state : σ) : List Nat :=
  if reuseAllowed available widthsSame oldCount count owner body before current extra then
    candidateKeys body current owner count
  else composeKeys free halt allowed paraStep controlStep current (owner + 1) state fuel

theorem root_adr0352_i5_chosen_keys_current_paragraphs
    (available widthsSame : Bool) (oldCount count owner key : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (fuel : Nat) (state : σ)
    (oldTyped : available = true → ∀ k, (body k).isSome = true → before k = some .paragraph)
    (member : key ∈ chooseKeys available widthsSame oldCount count owner body before current extra
      free halt allowed paraStep controlStep fuel state) : current key = some .paragraph := by
  cases gate : reuseAllowed available widthsSame oldCount count owner body before current extra with
  | true =>
    simp only [chooseKeys, gate, if_true] at member
    have globals := root_adr0352_i5_reuse_global_guards available widthsSame oldCount count owner body before current extra gate
    exact root_adr0352_i5_reused_keys_current_paragraphs available widthsSame oldCount count owner key
      body before current extra (oldTyped globals.1) gate member
  | false =>
    simp only [chooseKeys, gate, if_false] at member
    exact root_adr0352_i5_produced_keys_are_paragraphs free halt allowed paraStep controlStep current
      (owner + 1) key fuel state member

private theorem append_member_cases (xs ys : List Nat) (key : Nat) (member : key ∈ xs ++ ys) :
    key ∈ xs ∨ key ∈ ys := by
  induction xs with
  | nil => exact Or.inr member
  | cons head later ih =>
    rcases List.mem_cons.mp member with first | rest
    · exact Or.inl (List.mem_cons.mpr (Or.inl first))
    · rcases ih rest with left | right
      · exact Or.inl (List.mem_cons.mpr (Or.inr left))
      · exact Or.inr right

def chooseAll (available widthsSame : Bool) (oldCount count : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ) :
    List (ReuseJob σ) → List Nat
  | [] => []
  | job :: later => chooseKeys available widthsSame oldCount count job.owner body before current extra
      free halt allowed paraStep controlStep job.fuel job.state ++
    chooseAll available widthsSame oldCount count body before current extra free halt allowed paraStep controlStep later

theorem root_adr0352_i5_chosen_round_keys_current_paragraphs
    (available widthsSame : Bool) (oldCount count key : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (jobs : List (ReuseJob σ))
    (oldTyped : available = true → ∀ k, (body k).isSome = true → before k = some .paragraph)
    (member : key ∈ chooseAll available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep jobs) : current key = some .paragraph := by
  induction jobs with
  | nil => simp [chooseAll] at member
  | cons job later ih =>
    rcases append_member_cases _ _ key member with here | rest
    · exact root_adr0352_i5_chosen_keys_current_paragraphs available widthsSame oldCount count job.owner key
        body before current extra free halt allowed paraStep controlStep job.fuel job.state oldTyped here
    · exact ih rest

end BesideReuse
