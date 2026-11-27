/- Root ADR 0352: the document-order ID scan used by numberComposedFlow.
   A count is the change in nuNext caused by one numberUnit call. -/

namespace CausalFirstIds

/-- The first ID of the unit at `index` in a document-order numbering pass.
    A unit with no numbered object contributes zero. -/
def firstId : List Nat → Nat → Nat → Nat
  | [], _, next => next
  | _ :: _, 0, next => next
  | count :: later, index + 1, next => firstId later index (next + count)

/-- `firstId` is the `nuNext` value passed by the document-order fold to a
    unit after all preceding units have contributed their counts. -/
theorem root_adr0352_i5_firstId_after_prefix (before after : List Nat) (own next : Nat) :
    firstId (before ++ own :: after) before.length next =
      before.foldl Nat.add next := by
  induction before generalizing next with
  | nil => rfl
  | cons head tail ih => simpa [firstId] using ih (next + head)

/-- Replacing only a unit's own contribution cannot change its first ID. -/
theorem root_adr0352_i5_firstId_set_self (counts : List Nat) (index count next : Nat) :
    firstId (counts.set index count) index next = firstId counts index next := by
  induction counts generalizing index next with
  | nil => simp [firstId]
  | cons head tail ih =>
    cases index with
    | zero => simp [firstId]
    | succ index => simpa [firstId, Nat.add_assoc] using ih index (next + head)

/-- The arithmetic component of a retry's numbering premise: when all
    preceding units keep their contributions, changing the current unit's
    count preserves its first ID.  Connecting this scan to the complete
    parts/rebuild model remains a separate obligation. -/
theorem root_adr0352_i5_rebreak_preserves_unit_first (before after : List Nat)
    (oldCount newCount next : Nat) :
    firstId (before ++ newCount :: after) before.length next =
      firstId (before ++ oldCount :: after) before.length next := by
  rw [root_adr0352_i5_firstId_after_prefix, root_adr0352_i5_firstId_after_prefix]

/-- `besideFirsts` starts after the wrapped figure, then advances by each
    preceding paragraph's row count. Rebreaking the current paragraph leaves
    its own first ID fixed. -/
theorem root_adr0352_i5_rebreak_preserves_beside_first (figureFirst : Nat)
    (before after : List Nat) (oldRows newRows : Nat) :
    firstId (before ++ newRows :: after) before.length (figureFirst + 1) =
      firstId (before ++ oldRows :: after) before.length (figureFirst + 1) := by
  exact root_adr0352_i5_rebreak_preserves_unit_first before after oldRows newRows (figureFirst + 1)

end CausalFirstIds
