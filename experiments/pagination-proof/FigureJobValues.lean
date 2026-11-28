import FigureWindow
namespace BesideJobValues
open BesideOwnership BesideReuse BesideStore BesideFigureTable BesideFigureWindow BesidePayloadRounds

def valueJobs (eligible : α → Bool) (initState : Nat → α → σ) (count : Nat) : List (Nat × α) → List (ReuseJob σ)
  | [] => []
  | (key, value) :: later =>
    let rest := valueJobs eligible initState count later
    if eligible value then ⟨key, count - (key + 1), initState key value⟩ :: rest else rest

private theorem pair_member_key (rows : List (Nat × α)) (key : Nat) (value : α) (member : (key, value) ∈ rows) : key ∈ pairKeys rows := by
  induction rows with
  | nil => simp at member
  | cons head later ih =>
    rcases head with ⟨first, item⟩
    rcases List.mem_cons.mp member with atHead | inTail
    · cases atHead; exact List.mem_cons_self _ _
    · exact List.mem_cons_of_mem first (ih inTail)

theorem root_adr0352_i5_value_job_source
    (eligible : α → Bool) (initState : Nat → α → σ) (count : Nat) (rows : List (Nat × α))
    (job : ReuseJob σ) (member : job ∈ valueJobs eligible initState count rows) :
    ∃ value, (job.owner, value) ∈ rows ∧ eligible value = true ∧
      job.fuel = count - (job.owner + 1) ∧ job.state = initState job.owner value := by
  induction rows with
  | nil => simp [valueJobs] at member
  | cons head later ih =>
    rcases head with ⟨key, value⟩
    by_cases chosen : eligible value = true
    · simp only [valueJobs, chosen, if_true] at member
      rcases List.mem_cons.mp member with atHead | inTail
      · cases atHead
        exact ⟨value, List.mem_cons_self _ _, chosen, rfl, rfl⟩
      · rcases ih inTail with ⟨item, belongs, selected, amount, state⟩
        exact ⟨item, List.mem_cons_of_mem _ belongs, selected, amount, state⟩
    · simp only [valueJobs, chosen, if_false] at member
      rcases ih member with ⟨item, belongs, selected, amount, state⟩
      exact ⟨item, List.mem_cons_of_mem _ belongs, selected, amount, state⟩

theorem root_adr0352_i5_value_jobs_ordered
    (eligible : α → Bool) (initState : Nat → α → σ) (count : Nat) (rows : List (Nat × α))
    (ordered : Increasing (pairKeys rows)) : jobsOrdered (valueJobs eligible initState count rows) := by
  induction rows with
  | nil => trivial
  | cons head later ih =>
    rcases head with ⟨key, value⟩
    by_cases chosen : eligible value = true
    · simp only [valueJobs, chosen, if_true, jobsOrdered]
      constructor
      · intro job member
        rcases root_adr0352_i5_value_job_source eligible initState count later job member with ⟨item, belongs, _⟩
        exact ordered.1 job.owner (pair_member_key later job.owner item belongs)
      · exact ih ordered.2
    · simpa [valueJobs, chosen] using ih ordered.2

theorem root_adr0352_i5_figure_value_jobs_legal
    (round : PayloadRound σ β) (place : Nat → Option α) (eligible : α → Bool) (initState : Nat → α → σ) :
    roundJobsLegal {round.control with jobs := (valueJobs eligible initState round.control.count
      (figurePairs round.control.kindAt place 0 round.control.count))} := by
  constructor
  · apply root_adr0352_i5_value_jobs_ordered
    exact root_adr0352_i5_figure_pairs_keys_increasing round.control.kindAt place 0 round.control.count
  · intro job member
    rcases root_adr0352_i5_value_job_source eligible initState round.control.count _ job member with ⟨value, belongs, _⟩
    exact (root_adr0352_i5_figure_pair_source round.control.kindAt place 0 round.control.count job.owner
      (pair_member_key _ job.owner value belongs)).2.2


private theorem increasing_unique (keys : List Nat) (ordered : Increasing keys) : NoRepeat keys := by
  induction keys with
  | nil => trivial
  | cons key later ih =>
    constructor
    · intro member
      exact (Nat.lt_irrefl key) (ordered.1 key member)
    · exact ih ordered.2

theorem root_adr0352_i5_figure_job_value_from_store
    (round : PayloadRound σ β) (place : Nat → Option α) (eligible : α → Bool) (initState : Nat → α → σ)
    (job : ReuseJob σ)
    (member : job ∈ valueJobs eligible initState round.control.count (figurePairs round.control.kindAt place 0 round.control.count)) :
    ∃ value, fromPairs (figurePairs round.control.kindAt place 0 round.control.count) job.owner = some value ∧
      eligible value = true ∧ job.state = initState job.owner value := by
  rcases root_adr0352_i5_value_job_source eligible initState round.control.count _ job member with
    ⟨value, belongs, selected, _amount, state⟩
  refine ⟨value, ?_, selected, state⟩
  apply root_adr0352_i5_unique_payload_retained
  · apply increasing_unique
    exact root_adr0352_i5_figure_pairs_keys_increasing round.control.kindAt place 0 round.control.count
  · exact belongs

end BesideJobValues
