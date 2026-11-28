import BesideOwnership

namespace BesideOwnership

def adjustBeside (change : α → α) (target : Nat) (besides : Nat → Option α) (key : Nat) : Option α :=
  if key = target then (besides key).map change else besides key

def classes (besides : Nat → Option α) (control : Nat → Bool) (start : Nat) : Nat → List Class
  | 0 => []
  | count + 1 => ⟨(besides start).isSome, control start⟩ :: classes besides control (start + 1) count

theorem root_adr0352_i5_adjust_preserves_domain (change : α → α) (target key : Nat)
    (besides : Nat → Option α) :
    (adjustBeside change target besides key).isSome = (besides key).isSome := by
  by_cases same : key = target
  · subst target
    cases value : besides key <;> simp [adjustBeside, value]
  · simp [adjustBeside, same]

theorem root_adr0352_i5_adjust_preserves_classes (change : α → α) (target start count : Nat)
    (besides : Nat → Option α) (control : Nat → Bool) :
    classes (adjustBeside change target besides) control start count = classes besides control start count := by
  induction count generalizing start with
  | zero => rfl
  | succ count ih =>
    simp only [classes, root_adr0352_i5_adjust_preserves_domain, ih]

theorem root_adr0352_i5_rebreak_preserves_selected_keys (change : α → α) (target start count : Nat)
    (besides : Nat → Option α) (control : Nat → Bool) :
    scan start (classes (adjustBeside change target besides) control start count) =
      scan start (classes besides control start count) := by
  rw [root_adr0352_i5_adjust_preserves_classes]

end BesideOwnership
