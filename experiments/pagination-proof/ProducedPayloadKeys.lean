import RoundPayloadStore

namespace BesidePayload
open BesideOwnership BesideProducer BesideReuse BesideStore

def composePayloads (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool)
    (paraStep controlStep : Nat → σ → σ) (kindAt : Nat → Option Kind) (payload : Nat → σ → α)
    (start : Nat) (state : σ) : Nat → List (Nat × α)
  | 0 => []
  | fuel + 1 =>
    if halt state then []
    else match kindAt start with
      | some .paragraph => if allowed start state then
          (start, payload start state) :: composePayloads free halt allowed paraStep controlStep kindAt payload
            (start + 1) (paraStep start state) fuel else []
      | some .control => if free then composePayloads free halt allowed paraStep controlStep kindAt payload
          (start + 1) (controlStep start state) fuel else []
      | _ => []

theorem root_adr0352_i5_fresh_payload_keys
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool)
    (paraStep controlStep : Nat → σ → σ) (kindAt : Nat → Option Kind) (payload : Nat → σ → α)
    (start fuel : Nat) (state : σ) :
    pairKeys (composePayloads free halt allowed paraStep controlStep kindAt payload start state fuel) =
      composeKeys free halt allowed paraStep controlStep kindAt start state fuel := by
  induction fuel generalizing start state with
  | zero => rfl
  | succ fuel ih =>
    cases stopped : halt state with
    | true => simp [composePayloads, composeKeys, stopped, pairKeys]
    | false =>
      cases found : kindAt start with
      | none => simp [composePayloads, composeKeys, stopped, found, pairKeys]
      | some kind =>
        cases kind with
        | paragraph =>
          cases grant : allowed start state <;>
            simp [composePayloads, composeKeys, stopped, found, grant, pairKeys, ih]
        | control =>
          cases free <;> simp [composePayloads, composeKeys, stopped, found, pairKeys, ih]
        | figure => simp [composePayloads, composeKeys, stopped, found, pairKeys]
        | other => simp [composePayloads, composeKeys, stopped, found, pairKeys]

private def tracePayload (_ : Nat) (state : σ) : σ := state

def applyPayloads (payload : Nat → σ → α) : List (Nat × σ) → List (Nat × α)
  | [] => []
  | (key, state) :: later => (key, payload key state) :: applyPayloads payload later

theorem root_adr0352_i5_fresh_payload_values
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool)
    (paraStep controlStep : Nat → σ → σ) (kindAt : Nat → Option Kind) (payload : Nat → σ → α)
    (start fuel : Nat) (state : σ) :
    composePayloads free halt allowed paraStep controlStep kindAt payload start state fuel =
      applyPayloads payload (composePayloads free halt allowed paraStep controlStep kindAt tracePayload start state fuel) := by
  induction fuel generalizing start state with
  | zero => rfl
  | succ fuel ih =>
    cases stopped : halt state with
    | true => simp [composePayloads, stopped, applyPayloads]
    | false =>
      cases found : kindAt start with
      | none => simp [composePayloads, stopped, found, applyPayloads]
      | some kind =>
        cases kind with
        | paragraph =>
          cases grant : allowed start state <;>
            simp [composePayloads, stopped, found, grant, applyPayloads, tracePayload, ih]
        | control =>
          cases free <;> simp [composePayloads, stopped, found, applyPayloads, ih]
        | figure => simp [composePayloads, stopped, found, applyPayloads]
        | other => simp [composePayloads, stopped, found, applyPayloads]

private theorem read_existing_keys (keys : List Nat) (body : Nat → Option α)
    (present : ∀ key, key ∈ keys → (body key).isSome = true) : pairKeys (readPairs keys body) = keys := by
  induction keys with
  | nil => rfl
  | cons key later ih =>
    have rest := ih (fun k member => present k (List.mem_cons_of_mem key member))
    cases found : body key with
    | none =>
      have hit := present key (List.mem_cons_self key later)
      rw [found] at hit
      cases hit
    | some value => simp only [readPairs, found, pairKeys, rest]

def choosePayloads (available widthsSame : Bool) (oldCount count owner : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (payload : Nat → σ → α) (fuel : Nat) (state : σ) : List (Nat × α) :=
  if reuseAllowed available widthsSame oldCount count owner body before current extra then
    readPairs (candidateKeys body current owner count) body
  else composePayloads free halt allowed paraStep controlStep current payload (owner + 1) state fuel

theorem root_adr0352_i5_chosen_payload_keys
    (available widthsSame : Bool) (oldCount count owner : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (payload : Nat → σ → α) (fuel : Nat) (state : σ) :
    pairKeys (choosePayloads available widthsSame oldCount count owner body before current extra
      free halt allowed paraStep controlStep payload fuel state) =
    chooseKeys available widthsSame oldCount count owner body before current extra
      free halt allowed paraStep controlStep fuel state := by
  cases gate : reuseAllowed available widthsSame oldCount count owner body before current extra with
  | true =>
    simp only [choosePayloads, chooseKeys, gate, if_true]
    apply read_existing_keys
    intro key member
    exact root_adr0352_i5_candidate_keys_exist body (BesideProducer.controlAt current)
      (owner + 1) (count - (owner + 1)) key member
  | false =>
    simp only [choosePayloads, chooseKeys, gate, if_false]
    exact root_adr0352_i5_fresh_payload_keys free halt allowed paraStep controlStep current payload (owner + 1) fuel state

private theorem pairKeys_append (left right : List (Nat × α)) : pairKeys (left ++ right) = pairKeys left ++ pairKeys right := by
  induction left with
  | nil => rfl
  | cons head later ih =>
    rcases head with ⟨key, _value⟩
    change key :: pairKeys (later ++ right) = key :: (pairKeys later ++ pairKeys right)
    rw [ih]

def collectPayloads (available widthsSame : Bool) (oldCount count : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (payload : Nat → σ → α) : List (ReuseJob σ) → List (Nat × α)
  | [] => []
  | job :: later => choosePayloads available widthsSame oldCount count job.owner body before current extra
      free halt allowed paraStep controlStep payload job.fuel job.state ++
    collectPayloads available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep payload later

theorem root_adr0352_i5_collected_payload_keys
    (available widthsSame : Bool) (oldCount count : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (payload : Nat → σ → α) (jobs : List (ReuseJob σ)) :
    pairKeys (collectPayloads available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep payload jobs) =
    chooseAll available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep jobs := by
  induction jobs with
  | nil => rfl
  | cons job later ih =>
    simp only [collectPayloads, chooseAll, pairKeys_append, root_adr0352_i5_chosen_payload_keys, ih]

theorem root_adr0352_i5_produced_payload_readback
    (available widthsSame : Bool) (oldCount count : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (payload : Nat → σ → α) (jobs : List (ReuseJob σ))
    (oldTyped : available = true → ∀ k, (body k).isSome = true → before k = some .paragraph)
    (ordered : jobsOrdered jobs) (figures : ∀ job, job ∈ jobs → current job.owner = some .figure) :
    let pairs := collectPayloads available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep payload jobs
    readPairs (chooseAll available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep jobs) (fromPairs pairs) = pairs := by
  apply root_adr0352_i5_mixed_round_payload_readback
  · exact oldTyped
  · exact ordered
  · exact figures
  · exact root_adr0352_i5_collected_payload_keys available widthsSame oldCount count body before current extra
      free halt allowed paraStep controlStep payload jobs

end BesidePayload
