import RetryPrefix
namespace PhysicalPagination

/-- A retry of a proper prefix is smaller whenever it is actually allowed past the
    forced-prefix exit; the source row count bound comes from the trial. -/
theorem root_adr0352_i4_partial_retry_rank
    (env : Env) (region : Region) (limit : Option Nat)
    (positive : ∀ bound, limit = some bound → 0 < bound)
    (keep : Keep) (isStart : Bool) (cursor : St) (rows : List Line)
    (count : Nat) (placed : St) (relaxed : Keep)
    (trial : trialWrap env region limit keep isStart cursor rows = .ok (.placed count placed relaxed))
    (notForced : forcedPrefix limit count = false) :
    count - 1 < limitRank limit rows.length := by
  cases limit with
  | none =>
    have bound := root_adr0352_i4_trial_count_bound env region none keep isStart cursor rows count placed relaxed trial
    simp only [limitRank]
    omega
  | some bound =>
    have pos := positive bound rfl
    have limited : count ≤ bound := by
      simp [forcedPrefix, pos] at notForced
      omega
    simp only [limitRank]
    omega

/-- Read the positive-prefix premise from the already proved entry trace;
    the final inequality is not an input premise. -/
theorem root_adr0352_i4_partial_retry_rank_at_entry
    (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat))
    (items lastWanted : Nat) (follows : St → Bool) (hold : St → St)
    (limit : Option Nat) (keep : Keep) (isStart : Bool) (start before : Nat) (cursor : St)
    (ready : partsRetryEntriesSafe env region breaker items lastWanted follows hold limit keep isStart start before cursor)
    (count : Nat) (placed : St) (relaxed : Keep)
    (trial : trialWrap env region limit keep isStart cursor ((breaker cursor before start).map Prod.fst) = .ok (.placed count placed relaxed))
    (tailCount : Nat)
    (selected : (!forcedPrefix limit count && decide (tailCount < relaxed.last)) = true) :
    count - 1 < limitRank limit (breaker cursor before start).length := by
  have notForced : forcedPrefix limit count = false := by
    cases forced : forcedPrefix limit count
    · rfl
    · simp [forced] at selected
  have positive : ∀ bound, limit = some bound → 0 < bound := by
    rw [partsRetryEntriesSafe] at ready
    exact ready.1.1
  have result := root_adr0352_i4_partial_retry_rank env region limit positive keep isStart cursor
    ((breaker cursor before start).map Prod.fst) count placed relaxed trial notForced
  simpa only [List.length_map] using result

end PhysicalPagination
