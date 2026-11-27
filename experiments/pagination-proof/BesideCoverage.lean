import BesideOwnership

namespace BesideOwnership

def pass (row : Class) : Bool := row.beside || row.control

private theorem selected_first (row : Class) (after : List Class) (start : Nat) :
    (start ∈ scan start (row :: after)) ↔ row.beside = true := by
  cases beside : row.beside with
  | true => simp [scan, beside]
  | false =>
    cases control : row.control with
    | false => simp [scan, beside, control]
    | true =>
      simp only [scan, beside, control, if_false, if_true]
      change (start ∈ scan (start + 1) after) ↔ False
      constructor
      · intro member
        have bound := root_adr0352_i5_beside_key_range after (start + 1) start member
        omega
      · intro impossible
        contradiction

theorem root_adr0352_i5_beside_selected_iff (before after : List Class) (row : Class) (start : Nat) :
    (start + before.length ∈ scan start (before ++ row :: after)) ↔
      before.all pass = true ∧ row.beside = true := by
  induction before generalizing start with
  | nil => simpa using selected_first row after start
  | cons first later ih =>
    have pos : start + (later.length + 1) = (start + 1) + later.length := by omega
    cases beside : first.beside with
    | true =>
      simp only [List.cons_append, List.length_cons, scan, beside, if_true,
        List.mem_cons, List.all_cons, pass, Bool.true_or, Bool.true_and]
      rw [pos]
      have neq : (start + 1) + later.length ≠ start := by omega
      simp only [neq, false_or]
      exact ih (start + 1)
    | false =>
      cases control : first.control with
      | true =>
        simp only [List.cons_append, List.length_cons, scan, beside, control, if_false,
          if_true, List.all_cons, pass, Bool.false_or, Bool.true_and]
        rw [pos]
        exact ih (start + 1)
      | false => simp [scan, beside, control, pass]

/-- If the earlier interval has no barrier, scanning concatenated intervals
    preserves exactly their ordered selected keys. -/
theorem root_adr0352_i5_beside_append (before after : List Class) (start : Nat)
    (clear : before.all pass = true) :
    scan start (before ++ after) = scan start before ++ scan (start + before.length) after := by
  induction before generalizing start with
  | nil => simp [scan]
  | cons row later ih =>
    have pos : start + (later.length + 1) = (start + 1) + later.length := by omega
    cases beside : row.beside with
    | true =>
      have next : later.all pass = true := by simpa [pass, beside] using clear
      simp [scan, beside, pos, ih (start + 1) next]
    | false =>
      cases control : row.control with
      | false => simp [pass, beside, control] at clear
      | true =>
        have next : later.all pass = true := by simpa [pass, beside, control] using clear
        simp [scan, beside, control, pos, ih (start + 1) next]

/-- Controls with no beside row do not become content. No prefix condition
    is needed: either an earlier barrier stops the scan or this row is skipped. -/
theorem root_adr0352_i5_non_beside_not_selected
    (before after : List Class) (row : Class) (start : Nat) (notBeside : row.beside = false) :
    start + before.length ∉ scan start (before ++ row :: after) := by
  rw [root_adr0352_i5_beside_selected_iff]
  simp [notBeside]

/-- Every eligible beside row is selected; this is the completeness half
    of the membership characterization, separate from key uniqueness. -/
theorem root_adr0352_i5_beside_not_lost
    (before after : List Class) (row : Class) (start : Nat)
    (clear : before.all pass = true) (beside : row.beside = true) :
    start + before.length ∈ scan start (before ++ row :: after) :=
  (root_adr0352_i5_beside_selected_iff before after row start).mpr ⟨clear, beside⟩

end BesideOwnership
