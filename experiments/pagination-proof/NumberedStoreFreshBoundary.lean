import NumberedStoreFresh
open NumberedStoreFresh NumberedPayload BesideStore BesideWrappedRowFold
private def state : RowState Nat := ⟨4, []⟩
private def blocks : List (List Nat) := [[1], [], [2, 2]]
example : (runChunks state blocks).next = 7 := by decide
example : fromPairs (runChunks state blocks).rows 4 = some 1 := by decide
example : fromPairs (runChunks state blocks).rows 5 = some 2 := by decide
example : fromPairs (runChunks state blocks).rows 6 = some 2 := by decide
example : fromPairs (runChunks state blocks).rows 3 = none := by decide
example : fromPairs (runChunks state blocks).rows 7 = none := by decide
example : 6 < (runChunks state blocks).next := by decide
example : ¬ (7 < (runChunks state blocks).next) := by decide
example : fromPairs (runChunks (⟨5, [(99, 1)]⟩ : RowState Nat) [[]]).rows 99 = some 1 ∧
    ¬(99 < (runChunks (⟨5, [(99, 1)]⟩ : RowState Nat) [[]]).next) := by decide
example (before after : List (List Nat)) (seed key : Nat) :=
  root_adr0352_i5_initial_fold_left_union before after seed key
