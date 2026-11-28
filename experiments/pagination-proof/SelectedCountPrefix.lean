import BesideAdjustment
import BuiltFirstIds

namespace BesideOwnership

def countsFor : List Nat → (Nat → Nat) → List Nat
  | [], _ => []
  | key :: later, countOf => countOf key :: countsFor later countOf

def rowCount (size : α → Nat) (besides : Nat → Option α) (key : Nat) : Nat :=
  match besides key with
  | none => 0
  | some value => size value

private theorem noRepeat_prefix (before after : List Nat) (target : Nat)
    (unique : NoRepeat (before ++ target :: after)) : target ∉ before := by
  induction before with
  | nil => simp
  | cons head later ih =>
    simp only [List.cons_append, NoRepeat] at unique
    intro member
    rcases List.mem_cons.mp member with same | rest
    · subst head
      exact unique.1 (List.mem_append_of_mem_right later (List.mem_cons_self target after))
    · exact ih unique.2 rest

private theorem countsFor_prefix (before : List Nat) (size : α → Nat)
    (besides : Nat → Option α) (change : α → α) (target : Nat) (absent : target ∉ before) :
    countsFor before (rowCount size (adjustBeside change target besides)) =
      countsFor before (rowCount size besides) := by
  induction before with
  | nil => rfl
  | cons head later ih =>
    have different : head ≠ target := by intro same; subst head; exact absent (List.mem_cons_self target later)
    have tail : target ∉ later := fun member => absent (List.mem_cons_of_mem head member)
    simp [countsFor, rowCount, adjustBeside, different, ih tail]

theorem root_adr0352_i5_selected_count_prefix (rows : List Class) (start target : Nat)
    (before after : List Nat) (size : α → Nat) (besides : Nat → Option α) (change : α → α)
    (selected : scan start rows = before ++ target :: after) :
    countsFor before (rowCount size (adjustBeside change target besides)) =
      countsFor before (rowCount size besides) := by
  have unique := root_adr0352_i5_beside_keys_unique rows start
  rw [selected] at unique
  exact countsFor_prefix before size besides change target (noRepeat_prefix before after target unique)

theorem root_adr0352_i5_selected_two_pass_first (rows : List Class) (start target next : Nat)
    (before after beforeUnits afterUnits : List Nat)
    (size : α → Nat) (besides : Nat → Option α) (change : α → α)
    (selected : scan start rows = before ++ target :: after) :
    CausalFirstIds.besideFromTwoPass beforeUnits afterUnits
      (countsFor before (rowCount size (adjustBeside change target besides)))
      (countsFor after (rowCount size (adjustBeside change target besides)))
      (rowCount size (adjustBeside change target besides) target) next =
    CausalFirstIds.besideFromTwoPass beforeUnits afterUnits
      (countsFor before (rowCount size besides)) (countsFor after (rowCount size besides))
      (rowCount size besides target) next := by
  rw [CausalFirstIds.root_adr0352_i5_two_pass_first_value,
    CausalFirstIds.root_adr0352_i5_two_pass_first_value,
    root_adr0352_i5_selected_count_prefix rows start target before after size besides change selected]

theorem root_adr0352_i5_rebreak_selection_and_first (start target count next : Nat)
    (before after beforeUnits afterUnits : List Nat)
    (size : α → Nat) (besides : Nat → Option α) (change : α → α) (control : Nat → Bool)
    (selected : scan start (classes besides control start count) = before ++ target :: after) :
    scan start (classes (adjustBeside change target besides) control start count) = before ++ target :: after ∧
    CausalFirstIds.besideFromTwoPass beforeUnits afterUnits
      (countsFor before (rowCount size (adjustBeside change target besides)))
      (countsFor after (rowCount size (adjustBeside change target besides)))
      (rowCount size (adjustBeside change target besides) target) next =
    CausalFirstIds.besideFromTwoPass beforeUnits afterUnits
      (countsFor before (rowCount size besides)) (countsFor after (rowCount size besides))
      (rowCount size besides target) next := by
  constructor
  · rw [root_adr0352_i5_rebreak_preserves_selected_keys, selected]
  · exact root_adr0352_i5_selected_two_pass_first (classes besides control start count) start target next
      before after beforeUnits afterUnits size besides change selected

end BesideOwnership
