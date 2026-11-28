import ProducedPayloadKeys

namespace BesidePayloadRounds
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayload

structure PayloadCache (α : Type) where
  kindAt : Nat → Option BesideProducer.Kind
  count : Nat
  pairs : List (Nat × α)

structure PayloadRound (σ α : Type) where
  control : Round σ
  payload : Nat → σ → α

def payloadTyped (cache : PayloadCache α) : Prop :=
  ∀ key, (fromPairs cache.pairs key).isSome = true → cache.kindAt key = some .paragraph

def payloadUnique (cache : PayloadCache α) : Prop := NoRepeat (pairKeys cache.pairs)

private def noKind (_ : Nat) : Option BesideProducer.Kind := none
private def emptyPayloadCache : PayloadCache α := ⟨noKind, 0, []⟩
private def currentKind (round : PayloadRound σ α) (key : Nat) : Option BesideProducer.Kind := round.control.kindAt key

noncomputable def nextPayloadCache (previous : Option (PayloadCache α)) (round : PayloadRound σ α) : PayloadCache α :=
  let cache := previous.getD emptyPayloadCache
  let r := round.control
  ⟨currentKind round, r.count,
    collectPayloads previous.isSome r.widthsSame cache.count r.count
      (fromPairs cache.pairs) cache.kindAt (currentKind round) r.extra
      r.free r.halt r.allowed r.paraStep r.controlStep round.payload r.jobs⟩

private theorem present_member (pairs : List (Nat × α)) (key : Nat)
    (present : (fromPairs pairs key).isSome = true) : key ∈ pairKeys pairs := by
  by_cases member : key ∈ pairKeys pairs
  · exact member
  · have missing := root_adr0352_i5_store_missing_key pairs key member
    rw [missing] at present
    cases present

theorem root_adr0352_i5_next_payload_typed (previous : Option (PayloadCache α)) (round : PayloadRound σ α)
    (old : ∀ cache, previous = some cache → payloadTyped cache) : payloadTyped (nextPayloadCache previous round) := by
  intro key present
  have member := present_member (nextPayloadCache previous round).pairs key present
  change key ∈ pairKeys (collectPayloads previous.isSome round.control.widthsSame
    (previous.getD emptyPayloadCache).count round.control.count
    (fromPairs (previous.getD emptyPayloadCache).pairs) (previous.getD emptyPayloadCache).kindAt
    (currentKind round) round.control.extra round.control.free round.control.halt round.control.allowed
    round.control.paraStep round.control.controlStep round.payload round.control.jobs) at member
  rw [root_adr0352_i5_collected_payload_keys] at member
  apply root_adr0352_i5_chosen_round_keys_current_paragraphs
    previous.isSome round.control.widthsSame (previous.getD emptyPayloadCache).count round.control.count key
    (fromPairs (previous.getD emptyPayloadCache).pairs) (previous.getD emptyPayloadCache).kindAt
    (currentKind round) round.control.extra round.control.free round.control.halt round.control.allowed
    round.control.paraStep round.control.controlStep round.control.jobs _ member
  intro available oldKey found
  cases previous with
  | none => contradiction
  | some cache => exact old cache rfl oldKey found

theorem root_adr0352_i5_next_payload_unique (previous : Option (PayloadCache α)) (round : PayloadRound σ α)
    (old : ∀ cache, previous = some cache → payloadTyped cache)
    (legal : roundJobsLegal round.control) : payloadUnique (nextPayloadCache previous round) := by
  change NoRepeat (pairKeys (collectPayloads previous.isSome round.control.widthsSame
    (previous.getD emptyPayloadCache).count round.control.count
    (fromPairs (previous.getD emptyPayloadCache).pairs) (previous.getD emptyPayloadCache).kindAt
    (currentKind round) round.control.extra round.control.free round.control.halt round.control.allowed
    round.control.paraStep round.control.controlStep round.payload round.control.jobs))
  rw [root_adr0352_i5_collected_payload_keys]
  apply root_adr0352_i5_mixed_round_keys_unique
  · intro available oldKey found
    cases previous with
    | none => contradiction
    | some cache => exact old cache rfl oldKey found
  · exact legal.1
  · exact legal.2

noncomputable def runPayloadRounds : Option (PayloadCache α) → List (PayloadRound σ α) → Option (PayloadCache α)
  | previous, [] => previous
  | previous, round :: later => runPayloadRounds (some (nextPayloadCache previous round)) later

theorem root_adr0352_i5_payload_rounds_typed (rounds : List (PayloadRound σ α)) (previous : Option (PayloadCache α))
    (old : ∀ cache, previous = some cache → payloadTyped cache) :
    ∀ cache, runPayloadRounds previous rounds = some cache → payloadTyped cache := by
  induction rounds generalizing previous with
  | nil => exact old
  | cons round _later ih =>
    apply ih (some (nextPayloadCache previous round))
    intro cache same
    cases same
    exact root_adr0352_i5_next_payload_typed previous round old

theorem root_adr0352_i5_payload_rounds_unique (rounds : List (PayloadRound σ α)) (previous : Option (PayloadCache α))
    (oldTyped : ∀ cache, previous = some cache → payloadTyped cache)
    (oldUnique : ∀ cache, previous = some cache → payloadUnique cache)
    (legal : ∀ round, round ∈ rounds → roundJobsLegal round.control) :
    ∀ cache, runPayloadRounds previous rounds = some cache → payloadUnique cache := by
  induction rounds generalizing previous with
  | nil => exact oldUnique
  | cons round later ih =>
    apply ih (some (nextPayloadCache previous round))
    · intro cache same
      cases same
      exact root_adr0352_i5_next_payload_typed previous round oldTyped
    · intro cache same
      cases same
      exact root_adr0352_i5_next_payload_unique previous round oldTyped (legal round (List.mem_cons_self round later))
    · intro next member
      exact legal next (List.mem_cons_of_mem round member)

theorem root_adr0352_i5_payload_from_empty_typed (rounds : List (PayloadRound σ α)) :
    ∀ cache, runPayloadRounds none rounds = some cache → payloadTyped cache := by
  apply root_adr0352_i5_payload_rounds_typed rounds none
  intro cache impossible
  contradiction

theorem root_adr0352_i5_payload_from_empty_readback (rounds : List (PayloadRound σ α))
    (legal : ∀ round, round ∈ rounds → roundJobsLegal round.control) :
    ∀ cache, runPayloadRounds none rounds = some cache → readPairs (pairKeys cache.pairs) (fromPairs cache.pairs) = cache.pairs := by
  intro cache reached
  apply root_adr0352_i5_unique_readback
  apply root_adr0352_i5_payload_rounds_unique rounds none _ _ legal cache reached
  all_goals intro old impossible; contradiction

end BesidePayloadRounds
