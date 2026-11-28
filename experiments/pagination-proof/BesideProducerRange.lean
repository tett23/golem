import BesideProducer

namespace BesideProducer

theorem root_adr0352_i5_produced_key_bounds
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (kindAt : Nat → Option Kind) (start key fuel : Nat) (state : σ)
    (member : key ∈ composeKeys free halt allowed paraStep controlStep kindAt start state fuel) :
    start ≤ key ∧ key < start + fuel := by
  induction fuel generalizing start state with
  | zero => simp [composeKeys] at member
  | succ fuel ih =>
    cases stopped : halt state with
    | true => simp [composeKeys, stopped] at member
    | false =>
      cases found : kindAt start with
      | none => simp [composeKeys, stopped, found] at member
      | some kind =>
        cases kind with
        | paragraph =>
          cases granted : allowed start state with
          | false => simp [composeKeys, stopped, found, granted] at member
          | true =>
            simp only [composeKeys, stopped, if_false, found, granted, if_true, List.mem_cons] at member
            rcases member with atStart | later
            · subst key; omega
            · have bound := ih (start + 1) (paraStep start state) later
              omega
        | control =>
          cases free with
          | false => simp [composeKeys, stopped, found] at member
          | true =>
            simp only [composeKeys, stopped, if_false, found, if_true] at member
            have bound := ih (start + 1) (controlStep start state) member
            omega
        | figure => simp [composeKeys, stopped, found] at member
        | other => simp [composeKeys, stopped, found] at member

theorem root_adr0352_i5_produced_before_figure
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (kindAt : Nat → Option Kind) (start key barrier fuel : Nat) (state : σ)
    (notAfter : start ≤ barrier) (figure : kindAt barrier = some .figure)
    (member : key ∈ composeKeys free halt allowed paraStep controlStep kindAt start state fuel) :
    key < barrier := by
  induction fuel generalizing start state with
  | zero => simp [composeKeys] at member
  | succ fuel ih =>
    cases stopped : halt state with
    | true => simp [composeKeys, stopped] at member
    | false =>
      cases found : kindAt start with
      | none => simp [composeKeys, stopped, found] at member
      | some kind =>
        cases kind with
        | paragraph =>
          have strict : start < barrier := by
            have different : start ≠ barrier := by
              intro same; subst barrier; rw [found] at figure; cases figure
            omega
          cases granted : allowed start state with
          | false => simp [composeKeys, stopped, found, granted] at member
          | true =>
            simp only [composeKeys, stopped, if_false, found, granted, if_true, List.mem_cons] at member
            rcases member with atStart | later
            · subst key; exact strict
            · exact ih (start + 1) (paraStep start state) (by omega) later
        | control =>
          have strict : start < barrier := by
            have different : start ≠ barrier := by
              intro same; subst barrier; rw [found] at figure; cases figure
            omega
          cases free with
          | false => simp [composeKeys, stopped, found] at member
          | true =>
            simp only [composeKeys, stopped, if_false, found, if_true] at member
            exact ih (start + 1) (controlStep start state) (by omega) member
        | figure => simp [composeKeys, stopped, found] at member
        | other => simp [composeKeys, stopped, found] at member

theorem root_adr0352_i5_ordered_jobs_separate
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (kindAt : Nat → Option Kind) (leftOwner rightOwner leftKey rightKey leftFuel rightFuel : Nat)
    (leftState rightState : σ) (ordered : leftOwner < rightOwner)
    (figure : kindAt rightOwner = some .figure)
    (left : leftKey ∈ composeKeys free halt allowed paraStep controlStep kindAt (leftOwner + 1) leftState leftFuel)
    (right : rightKey ∈ composeKeys free halt allowed paraStep controlStep kindAt (rightOwner + 1) rightState rightFuel) :
    leftKey < rightKey := by
  have before := root_adr0352_i5_produced_before_figure free halt allowed paraStep controlStep kindAt
    (leftOwner + 1) leftKey rightOwner leftFuel leftState (by omega) figure left
  have after := root_adr0352_i5_produced_key_bounds free halt allowed paraStep controlStep kindAt
    (rightOwner + 1) rightKey rightFuel rightState right
  omega

theorem root_adr0352_i5_produced_keys_increasing
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (kindAt : Nat → Option Kind) (start fuel : Nat) (state : σ) :
    BesideOwnership.Increasing (composeKeys free halt allowed paraStep controlStep kindAt start state fuel) := by
  induction fuel generalizing start state with
  | zero => trivial
  | succ fuel ih =>
    cases stopped : halt state with
    | true => simp [composeKeys, stopped, BesideOwnership.Increasing]
    | false =>
      cases found : kindAt start with
      | none => simp [composeKeys, stopped, found, BesideOwnership.Increasing]
      | some kind =>
        cases kind with
        | paragraph =>
          cases granted : allowed start state with
          | false => simp [composeKeys, stopped, found, granted, BesideOwnership.Increasing]
          | true =>
            simp only [composeKeys, stopped, if_false, found, granted, if_true, BesideOwnership.Increasing]
            refine ⟨?_, ih (start + 1) (paraStep start state)⟩
            intro key member
            have bound := root_adr0352_i5_produced_key_bounds free halt allowed paraStep controlStep kindAt
              (start + 1) key fuel (paraStep start state) member
            omega
        | control =>
          cases free with
          | false => simp [composeKeys, stopped, found, BesideOwnership.Increasing]
          | true => simpa [composeKeys, stopped, found] using ih (start + 1) (controlStep start state)
        | figure => simp [composeKeys, stopped, found, BesideOwnership.Increasing]
        | other => simp [composeKeys, stopped, found, BesideOwnership.Increasing]

end BesideProducer
