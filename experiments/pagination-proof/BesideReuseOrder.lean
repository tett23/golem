import BesideReuse
import BesideProducerRange

namespace BesideReuse
open BesideOwnership BesideProducer

theorem root_adr0352_i5_typed_scan_before_figure
    (body : Nat → Option α) (current : Nat → Option Kind) (start count barrier key : Nat)
    (figure : current barrier = some .figure) (ordered : start ≤ barrier)
    (typed : ∀ k, k ∈ scan start (classes body (BesideProducer.controlAt current) start count) → current k = some .paragraph)
    (member : key ∈ scan start (classes body (BesideProducer.controlAt current) start count)) : key < barrier := by
  induction count generalizing start with
  | zero => simp [classes, scan] at member
  | succ count ih =>
    cases present : (body start).isSome with
    | true =>
      have atStart := typed start (by simp [classes, scan, present])
      have strict : start < barrier := by
        have different : start ≠ barrier := by
          intro same; subst barrier; rw [figure] at atStart; cases atStart
        omega
      have tailTyped : ∀ k, k ∈ scan (start + 1) (classes body (BesideProducer.controlAt current) (start + 1) count) →
          current k = some .paragraph := by
        intro k selected
        apply typed k
        simp only [classes, scan, present, if_true, List.mem_cons]
        exact Or.inr selected
      simp only [classes, scan, present, if_true, List.mem_cons] at member
      rcases member with first | rest
      · subst key; exact strict
      · exact ih (start + 1) (by omega) tailTyped rest
    | false =>
      cases isControl : BesideProducer.controlAt current start with
      | false => simp [classes, scan, present, isControl] at member
      | true =>
        have strict : start < barrier := by
          have different : start ≠ barrier := by
            intro same; subst barrier; simp [BesideProducer.controlAt, figure] at isControl
          omega
        have tailTyped : ∀ k, k ∈ scan (start + 1) (classes body (BesideProducer.controlAt current) (start + 1) count) →
            current k = some .paragraph := by
          intro k selected
          apply typed k
          simpa [classes, scan, present, isControl] using selected
        simp only [classes, scan, present, if_false, isControl, if_true] at member
        exact ih (start + 1) (by omega) tailTyped member

theorem root_adr0352_i5_chosen_key_after_owner
    (available widthsSame : Bool) (oldCount count owner key : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (fuel : Nat) (state : σ)
    (member : key ∈ chooseKeys available widthsSame oldCount count owner body before current extra
      free halt allowed paraStep controlStep fuel state) : owner < key := by
  cases gate : reuseAllowed available widthsSame oldCount count owner body before current extra with
  | true =>
    simp only [chooseKeys, gate, if_true] at member
    have lower := root_adr0352_i5_beside_key_range
      (classes body (BesideProducer.controlAt current) (owner + 1) (count - (owner + 1))) (owner + 1) key member
    omega
  | false =>
    simp only [chooseKeys, gate, if_false] at member
    have lower := root_adr0352_i5_produced_key_bounds free halt allowed paraStep controlStep current
      (owner + 1) key fuel state member
    omega

theorem root_adr0352_i5_chosen_before_figure
    (available widthsSame : Bool) (oldCount count owner barrier key : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (fuel : Nat) (state : σ)
    (oldTyped : available = true → ∀ k, (body k).isSome = true → before k = some .paragraph)
    (figure : current barrier = some .figure) (ordered : owner < barrier)
    (member : key ∈ chooseKeys available widthsSame oldCount count owner body before current extra
      free halt allowed paraStep controlStep fuel state) : key < barrier := by
  cases gate : reuseAllowed available widthsSame oldCount count owner body before current extra with
  | true =>
    simp only [chooseKeys, gate, if_true] at member
    have globals := root_adr0352_i5_reuse_global_guards available widthsSame oldCount count owner body before current extra gate
    apply root_adr0352_i5_typed_scan_before_figure body current (owner + 1) (count - (owner + 1)) barrier key
      figure (by omega) _ member
    intro k hit
    exact root_adr0352_i5_reused_keys_current_paragraphs available widthsSame oldCount count owner k
      body before current extra (oldTyped globals.1) gate hit
  | false =>
    simp only [chooseKeys, gate, if_false] at member
    exact root_adr0352_i5_produced_before_figure free halt allowed paraStep controlStep current
      (owner + 1) key barrier fuel state (by omega) figure member

theorem root_adr0352_i5_chosen_keys_increasing
    (available widthsSame : Bool) (oldCount count owner : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (fuel : Nat) (state : σ) :
    Increasing (chooseKeys available widthsSame oldCount count owner body before current extra
      free halt allowed paraStep controlStep fuel state) := by
  cases gate : reuseAllowed available widthsSame oldCount count owner body before current extra with
  | true =>
    simp only [chooseKeys, gate, if_true]
    exact root_adr0352_i5_beside_key_order
      (classes body (BesideProducer.controlAt current) (owner + 1) (count - (owner + 1))) (owner + 1)
  | false =>
    simp only [chooseKeys, gate, if_false]
    exact root_adr0352_i5_produced_keys_increasing free halt allowed paraStep controlStep current (owner + 1) fuel state

theorem root_adr0352_i5_ordered_chosen_jobs_separate
    (available widthsSame : Bool) (oldCount count leftOwner rightOwner leftKey rightKey leftFuel rightFuel : Nat)
    (body : Nat → Option α) (before current : Nat → Option Kind) (extra : Nat → Bool)
    (free : Bool) (halt : σ → Bool) (allowed : Nat → σ → Bool) (paraStep controlStep : Nat → σ → σ)
    (leftState rightState : σ)
    (oldTyped : available = true → ∀ k, (body k).isSome = true → before k = some .paragraph)
    (figure : current rightOwner = some .figure) (ordered : leftOwner < rightOwner)
    (left : leftKey ∈ chooseKeys available widthsSame oldCount count leftOwner body before current extra
      free halt allowed paraStep controlStep leftFuel leftState)
    (right : rightKey ∈ chooseKeys available widthsSame oldCount count rightOwner body before current extra
      free halt allowed paraStep controlStep rightFuel rightState) : leftKey < rightKey := by
  have upper := root_adr0352_i5_chosen_before_figure available widthsSame oldCount count leftOwner rightOwner leftKey
    body before current extra free halt allowed paraStep controlStep leftFuel leftState oldTyped figure ordered left
  have lower := root_adr0352_i5_chosen_key_after_owner available widthsSame oldCount count rightOwner rightKey
    body before current extra free halt allowed paraStep controlStep rightFuel rightState right
  omega

end BesideReuse
