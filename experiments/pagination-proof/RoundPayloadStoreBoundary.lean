import RoundPayloadStore

open BesideStore BesideOwnership

example : fromPairs ([] : List (Nat × String)) 0 = none := by decide
example : fromPairs [(1, "first"), (3, "last")] 1 = some "first" := by decide
example : fromPairs [(1, "first"), (3, "last")] 2 = none := by decide
example : fromPairs [(0, "first"), (0, "last")] 0 = some "last" := by decide
example : fromPairs ([(0, 1), (0, 0)] : List (Nat × Nat)) 0 = some 0 := by decide
example : readPairs [1, 3] (fromPairs [(1, "first"), (3, "last")]) = [(1, "first"), (3, "last")] := by decide
example : readPairs [3, 1] (fromPairs [(3, "first"), (1, "last")]) = [(3, "first"), (1, "last")] := by decide
example : readPairs [1, 9] (fromPairs [(1, "first")]) = [(1, "first")] := by decide
example : readPairs [] (fromPairs [(1, "first")]) = [] := by decide
example : readPairs (pairKeys [(1, "first"), (3, "last")]) (fromPairs [(1, "first"), (3, "last")]) =
    [(1, "first"), (3, "last")] := by
  apply root_adr0352_i5_unique_readback
  simp [pairKeys, NoRepeat]
-- Repeated input keys do not meet the payload-preservation premise.
example : readPairs [0, 0] (fromPairs ([(0, 1), (0, 2)] : List (Nat × Nat))) ≠ [(0, 1), (0, 2)] := by decide
