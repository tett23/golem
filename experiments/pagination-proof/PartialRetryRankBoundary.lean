import PartialRetryRank
namespace PhysicalPagination

-- The historical forced-prefix case does not satisfy the selected retry guard.
example : forcedPrefix (some 2) 3 = true := by decide
example : (!forcedPrefix (some 2) 3 && decide (2 < 4)) = false := by decide
example : ¬ (3 - 1 < limitRank (some 2) 5) := by decide

-- Boundary arithmetic for admissible retries, including an empty accepted prefix.
example : 0 - 1 < limitRank none 0 := by decide
example : 3 - 1 < limitRank none 3 := by decide
example : 0 - 1 < limitRank (some 1) 0 := by decide
example : 1 - 1 < limitRank (some 1) 1 := by decide
example : 3 - 1 < limitRank (some 3) 5 := by decide
example : ¬ (0 - 1 < limitRank (some 0) 0) := by decide

example := root_adr0352_i4_partial_retry_rank
example := root_adr0352_i4_partial_retry_rank_at_entry
end PhysicalPagination
