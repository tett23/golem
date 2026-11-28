import CausalFirstIds

namespace CausalFirstIds

/-- The second component of a `mapAccumL` numbering scan, discarding keys.
    Zero rows still receive their current ID in `besideFirsts`. -/
def scanFirsts : List Nat → Nat → List Nat
  | [], _ => []
  | count :: later, next => next :: scanFirsts later (next + count)

/-- The modeled scan emits exactly the arithmetic `firstId` at each valid
    position. This connects the scan result to the existing prefix lemma. -/
theorem root_adr0352_i5_scan_firstId (counts : List Nat) (index next : Nat)
    (valid : index < counts.length) :
    (scanFirsts counts next).get? index = some (firstId counts index next) := by
  induction counts generalizing index next with
  | nil => exact (Nat.not_lt_zero _ valid).elim
  | cons head tail ih =>
    cases index with
    | zero => rfl
    | succ index =>
      simpa [scanFirsts, firstId] using ih index (next + head) (Nat.lt_of_succ_lt_succ valid)

/-- The total number of rows owned by a figure. -/
def ownedRows : List Nat → Nat
  | [] => 0
  | n :: ns => n + ownedRows ns

/-- The outer unit scan counts the owning figure and all its paragraph
    rows. The inner scan starts at the owner's first ID plus one. -/
def besideFromTwoPass (beforeUnits afterUnits beforeRows afterRows : List Nat)
    (rows next : Nat) : Option Nat :=
  let contribution := 1 + ownedRows (beforeRows ++ rows :: afterRows)
  match (scanFirsts (beforeUnits ++ contribution :: afterUnits) next).get? beforeUnits.length with
  | none => none
  | some owner => (scanFirsts (beforeRows ++ rows :: afterRows) (owner + 1)).get? beforeRows.length

/-- Both valid positions exist even when this paragraph has zero rows.
    The result depends on the outer prefix and the preceding owned rows. -/
theorem root_adr0352_i5_two_pass_first_value
    (beforeUnits afterUnits beforeRows afterRows : List Nat) (rows next : Nat) :
    besideFromTwoPass beforeUnits afterUnits beforeRows afterRows rows next =
      some (beforeRows.foldl Nat.add (beforeUnits.foldl Nat.add next + 1)) := by
  simp only [besideFromTwoPass]
  rw [root_adr0352_i5_scan_firstId _ _ _
        (by simp only [List.length_append, List.length_cons]; exact Nat.lt_add_of_pos_right (Nat.succ_pos _)),
      root_adr0352_i5_firstId_after_prefix]
  dsimp only
  rw [root_adr0352_i5_scan_firstId _ _ _
        (by simp only [List.length_append, List.length_cons]; exact Nat.lt_add_of_pos_right (Nat.succ_pos _)),
      root_adr0352_i5_firstId_after_prefix]

/-- Changing the current paragraph changes its owner's total contribution,
    but neither the owner's first ID nor this paragraph's first ID. -/
theorem root_adr0352_i5_two_pass_rebreak_first
    (beforeUnits afterUnits beforeRows afterRows : List Nat) (oldRows newRows next : Nat) :
    besideFromTwoPass beforeUnits afterUnits beforeRows afterRows oldRows next =
      besideFromTwoPass beforeUnits afterUnits beforeRows afterRows newRows next := by
  rw [root_adr0352_i5_two_pass_first_value, root_adr0352_i5_two_pass_first_value]

/-- Comparison for finite execution, without changing the proof statements. -/
def sameFirst : Option Nat → Option Nat → Bool
  | none, none => true
  | some a, some b => a == b
  | _, _ => false

/-- Direct execution boundaries, separate from the general theorems. -/
def twoPassBoundaries : Bool :=
  [[], [0], [2, 0]].all fun beforeUnits =>
  [[], [0, 3]].all fun afterUnits =>
  [[], [0], [2, 0]].all fun beforeRows =>
  [[], [0, 2]].all fun afterRows =>
  [0, 1, 4].all fun oldRows =>
  [0, 2, 5].all fun newRows =>
  [0, 7].all fun next =>
    sameFirst (besideFromTwoPass beforeUnits afterUnits beforeRows afterRows oldRows next)
      (besideFromTwoPass beforeUnits afterUnits beforeRows afterRows newRows next)

#eval twoPassBoundaries &&
  (sameFirst ((scanFirsts [] 9).get? 0) none) &&
  (!(sameFirst (besideFromTwoPass [] [] [0] [] 1 0) (besideFromTwoPass [] [] [2] [] 1 0)))

end CausalFirstIds
