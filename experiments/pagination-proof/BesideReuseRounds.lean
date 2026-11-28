import BesideReuse

namespace BesideReuse
open BesideProducer

structure Cache where
  kindAt : Nat → Option Kind
  count : Nat
  keys : List Nat

def cacheTyped (cache : Cache) : Prop :=
  ∀ key, key ∈ cache.keys → cache.kindAt key = some .paragraph

def bodyOf (keys : List Nat) (key : Nat) : Option Unit :=
  if key ∈ keys then some () else none

structure Round (σ : Type) where
  kindAt : Nat → Option Kind
  count : Nat
  widthsSame : Bool
  extra : Nat → Bool
  free : Bool
  halt : σ → Bool
  allowed : Nat → σ → Bool
  paraStep : Nat → σ → σ
  controlStep : Nat → σ → σ
  jobs : List (ReuseJob σ)

private def noKind (_ : Nat) : Option Kind := none
private def emptyCache : Cache := ⟨noKind, 0, []⟩
private def currentKind (round : Round σ) (key : Nat) : Option Kind := round.kindAt key

noncomputable def nextCache (previous : Option Cache) (round : Round σ) : Cache :=
  let cache := previous.getD emptyCache
  ⟨currentKind round, round.count,
    chooseAll previous.isSome round.widthsSame cache.count round.count
      (bodyOf cache.keys) cache.kindAt (currentKind round) round.extra
      round.free round.halt round.allowed round.paraStep round.controlStep round.jobs⟩

theorem root_adr0352_i5_next_cache_typed (previous : Option Cache) (round : Round σ)
    (old : ∀ cache, previous = some cache → cacheTyped cache) : cacheTyped (nextCache previous round) := by
  intro key member
  apply root_adr0352_i5_chosen_round_keys_current_paragraphs
    previous.isSome round.widthsSame (previous.getD emptyCache).count round.count key
    (bodyOf (previous.getD emptyCache).keys) (previous.getD emptyCache).kindAt
    round.kindAt round.extra round.free round.halt round.allowed round.paraStep round.controlStep round.jobs
    _ member
  intro available oldKey present
  cases previous with
  | none => contradiction
  | some cache =>
    apply old cache rfl oldKey
    by_cases found : oldKey ∈ cache.keys
    · exact found
    · simp [bodyOf, found] at present

noncomputable def runRounds : Option Cache → List (Round σ) → Option Cache
  | previous, [] => previous
  | previous, round :: later => runRounds (some (nextCache previous round)) later

theorem root_adr0352_i5_all_rounds_cache_typed (rounds : List (Round σ)) (previous : Option Cache)
    (old : ∀ cache, previous = some cache → cacheTyped cache) :
    ∀ cache, runRounds previous rounds = some cache → cacheTyped cache := by
  induction rounds generalizing previous with
  | nil => exact old
  | cons round _later ih =>
    apply ih (some (nextCache previous round))
    intro cache same
    cases same
    exact root_adr0352_i5_next_cache_typed previous round old

theorem root_adr0352_i5_from_no_cache_typed (rounds : List (Round σ)) :
    ∀ cache, runRounds none rounds = some cache → cacheTyped cache := by
  apply root_adr0352_i5_all_rounds_cache_typed rounds none
  intro cache impossible
  contradiction

def cacheBounded (cache : Cache) : Prop :=
  ∀ key, key ∈ cache.keys → key < cache.count

def kindBounded (round : Round σ) : Prop :=
  ∀ key, round.count ≤ key → round.kindAt key = none

theorem root_adr0352_i5_next_cache_bounded (previous : Option Cache) (round : Round σ)
    (old : ∀ cache, previous = some cache → cacheTyped cache)
    (bounded : kindBounded round) : cacheBounded (nextCache previous round) := by
  intro key member
  have typed := root_adr0352_i5_next_cache_typed previous round old key member
  by_cases valid : key < round.count
  · exact valid
  · have missing := bounded key (by omega)
    change round.kindAt key = some .paragraph at typed
    rw [missing] at typed
    cases typed

theorem root_adr0352_i5_all_rounds_cache_bounded (rounds : List (Round σ)) (previous : Option Cache)
    (oldTyped : ∀ cache, previous = some cache → cacheTyped cache)
    (oldBounded : ∀ cache, previous = some cache → cacheBounded cache)
    (bounded : ∀ round, round ∈ rounds → kindBounded round) :
    ∀ cache, runRounds previous rounds = some cache → cacheBounded cache := by
  induction rounds generalizing previous with
  | nil => exact oldBounded
  | cons round later ih =>
    apply ih (some (nextCache previous round))
    · intro cache same
      cases same
      exact root_adr0352_i5_next_cache_typed previous round oldTyped
    · intro cache same
      cases same
      exact root_adr0352_i5_next_cache_bounded previous round oldTyped (bounded round (by simp))
    · intro laterRound member
      exact bounded laterRound (List.mem_cons_of_mem round member)

theorem root_adr0352_i5_from_no_cache_bounded (rounds : List (Round σ))
    (bounded : ∀ round, round ∈ rounds → kindBounded round) :
    ∀ cache, runRounds none rounds = some cache → cacheBounded cache := by
  apply root_adr0352_i5_all_rounds_cache_bounded rounds none _ _ bounded
  all_goals intro cache impossible; contradiction

end BesideReuse
