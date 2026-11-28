import BesideOwnership

namespace BesideProducer

inductive Kind where
  | paragraph
  | control
  | figure
  | other
  deriving DecidableEq

structure Job (σ : Type) where
  start : Nat
  fuel : Nat
  state : σ

def composeKeys (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (kindAt : Nat → Option Kind) (start : Nat) (state : σ) : Nat → List Nat
  | 0 => []
  | fuel + 1 =>
    if halt state then []
    else match kindAt start with
      | some .paragraph => if allowed start state then start :: composeKeys free halt allowed paraStep controlStep kindAt
          (start + 1) (paraStep start state) fuel else []
      | some .control => if free then composeKeys free halt allowed paraStep controlStep kindAt
          (start + 1) (controlStep start state) fuel else []
      | _ => []

theorem root_adr0352_i5_produced_keys_are_paragraphs
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (kindAt : Nat → Option Kind) (start key fuel : Nat) (state : σ)
    (member : key ∈ composeKeys free halt allowed paraStep controlStep kindAt start state fuel) :
    kindAt key = some .paragraph := by
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
            · subst key; exact found
            · exact ih (start + 1) (paraStep start state) later
        | control =>
          cases free with
          | false => simp [composeKeys, stopped, found] at member
          | true =>
            simp only [composeKeys, stopped, if_false, found, if_true] at member
            exact ih (start + 1) (controlStep start state) member
        | figure => simp [composeKeys, stopped, found] at member
        | other => simp [composeKeys, stopped, found] at member

private theorem append_member_cases (before after : List Nat) (key : Nat)
    (member : key ∈ before ++ after) : key ∈ before ∨ key ∈ after := by
  induction before with
  | nil => exact Or.inr member
  | cons head later ih =>
    rcases List.mem_cons.mp member with first | rest
    · exact Or.inl (List.mem_cons.mpr (Or.inl first))
    · rcases ih rest with inBefore | inAfter
      · exact Or.inl (List.mem_cons.mpr (Or.inr inBefore))
      · exact Or.inr inAfter

def gather (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (kindAt : Nat → Option Kind) : List (Job σ) → List Nat
  | [] => []
  | job :: later => composeKeys free halt allowed paraStep controlStep kindAt job.start job.state job.fuel ++
      gather free halt allowed paraStep controlStep kindAt later

theorem root_adr0352_i5_gathered_keys_are_paragraphs
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (kindAt : Nat → Option Kind) (jobs : List (Job σ)) (key : Nat)
    (member : key ∈ gather free halt allowed paraStep controlStep kindAt jobs) :
    kindAt key = some .paragraph := by
  induction jobs with
  | nil => simp [gather] at member
  | cons job later ih =>
    rcases append_member_cases _ _ key member with here | rest
    · exact root_adr0352_i5_produced_keys_are_paragraphs free halt allowed paraStep controlStep kindAt
        job.start key job.fuel job.state here
    · exact ih rest

theorem root_adr0352_i5_figures_are_not_owned
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (kindAt : Nat → Option Kind) (jobs : List (Job σ)) (key : Nat)
    (figure : kindAt key = some .figure) :
    key ∉ gather free halt allowed paraStep controlStep kindAt jobs := by
  intro member
  have para := root_adr0352_i5_gathered_keys_are_paragraphs free halt allowed paraStep controlStep kindAt jobs key member
  rw [figure] at para
  cases para

def controlAt (kindAt : Nat → Option Kind) (key : Nat) : Bool :=
  match kindAt key with
  | some .control => true
  | _ => false

def classAt (keys : List Nat) (kindAt : Nat → Option Kind) (key : Nat) : BesideOwnership.Class :=
  ⟨decide (key ∈ keys), controlAt kindAt key⟩

theorem root_adr0352_i5_produced_figure_is_barrier
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (kindAt : Nat → Option Kind) (jobs : List (Job σ)) (key : Nat)
    (figure : kindAt key = some .figure) :
    (classAt (gather free halt allowed paraStep controlStep kindAt jobs) kindAt key).beside = false ∧
    (classAt (gather free halt allowed paraStep controlStep kindAt jobs) kindAt key).control = false := by
  have absent := root_adr0352_i5_figures_are_not_owned free halt allowed paraStep controlStep kindAt jobs key figure
  simp [classAt, controlAt, figure, absent]

/-- The consumer's barrier hypotheses follow from the fresh producer's
    paragraph-only output and the unit kind at the intervening key. -/
theorem root_adr0352_i5_fresh_figure_separates_ranges
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool)
    (paraStep controlStep : Nat → σ → σ) (kindAt : Nat → Option Kind)
    (jobs : List (Job σ)) (before after : List BesideOwnership.Class)
    (start earlier later : Nat) (figure : kindAt (start + before.length) = some .figure)
    (left : earlier ∈ BesideOwnership.scan start
      (before ++ classAt (gather free halt allowed paraStep controlStep kindAt jobs) kindAt
        (start + before.length) :: after))
    (right : later ∈ BesideOwnership.scan (start + before.length + 1) after) : earlier < later := by
  have guards := root_adr0352_i5_produced_figure_is_barrier free halt allowed paraStep controlStep kindAt
    jobs (start + before.length) figure
  exact BesideOwnership.root_adr0352_i5_owner_ranges_disjoint before after start
    (classAt (gather free halt allowed paraStep controlStep kindAt jobs) kindAt (start + before.length))
    guards.1 guards.2 earlier later left right

end BesideProducer
