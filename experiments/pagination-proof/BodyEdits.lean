import OwnedUnion
namespace BesideBodyEdits
open BesideOwnership BesideProducer BesideReuse BesideStore BesidePayloadRounds

structure BodyEdit (α : Type) where
  target : Nat
  change : α → α

def applyEdits (body : Nat → Option α) : List (BodyEdit α) → Nat → Option α
  | [] => body
  | edit :: later => applyEdits (adjustBeside edit.change edit.target body) later

theorem root_adr0352_i5_body_edits_domain (edits : List (BodyEdit α)) (body : Nat → Option α) (key : Nat) :
    (applyEdits body edits key).isSome = (body key).isSome := by
  induction edits generalizing body with
  | nil => rfl
  | cons edit later ih =>
    rw [applyEdits, ih, root_adr0352_i5_adjust_preserves_domain]

theorem root_adr0352_i5_body_edits_classes (edits : List (BodyEdit α)) (body : Nat → Option α)
    (control : Nat → Bool) (start count : Nat) :
    classes (applyEdits body edits) control start count = classes body control start count := by
  induction count generalizing start with
  | zero => rfl
  | succ count ih => simp only [classes, root_adr0352_i5_body_edits_domain, ih]

theorem root_adr0352_i5_body_edits_selected (edits : List (BodyEdit α)) (body : Nat → Option α)
    (current : Nat → Option Kind) (owner count : Nat) :
    candidateKeys (applyEdits body edits) current owner count = candidateKeys body current owner count := by
  unfold candidateKeys
  rw [root_adr0352_i5_body_edits_classes]

theorem root_adr0352_i5_reached_body_edits_typed
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α) (reached : runPayloadRounds none rounds = some cache)
    (edits : List (BodyEdit α)) :
    ∀ key, (applyEdits (fromPairs cache.pairs) edits key).isSome = true → cache.kindAt key = some .paragraph := by
  intro key present
  rw [root_adr0352_i5_body_edits_domain] at present
  exact root_adr0352_i5_payload_from_empty_typed rounds cache reached key present
end BesideBodyEdits
