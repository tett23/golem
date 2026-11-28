import FigureJobValues
open BesideProducer BesideReuse BesideStore BesideFigureTable BesideJobValues

private def rows : List (Nat × (Nat × Bool)) := [(1, (11, true)), (3, (33, true)), (4, (44, false))]
private def eligible (value : Nat × Bool) : Bool := value.2
private def initState (key : Nat) (value : Nat × Bool) : Nat := 100 + key + value.1
private def view (jobs : List (ReuseJob Nat)) : List (Nat × (Nat × Nat)) :=
  jobs.map (fun job => (job.owner, (job.fuel, job.state)))
example : view (valueJobs eligible initState 5 rows) = [(1, (3, 112)), (3, (1, 136))] := by decide

example : view (valueJobs eligible initState 5 []) = [] := by decide
example : view (valueJobs (fun _ => false) initState 5 rows) = [] := by decide
example : view (valueJobs (fun _ => true) initState 5 rows) = [(1, (3, 112)), (3, (1, 136)), (4, (0, 148))] := by decide
example : view (valueJobs (fun value => !value.2) initState 5 rows) = [(4, (0, 148))] := by decide
example : view (valueJobs eligible (fun _ value => value.1) 5 rows) = [(1, (3, 11)), (3, (1, 33))] := by decide
private def kinds : Nat → Option Kind
  | 1 => some .figure
  | 3 => some .figure
  | 4 => some .figure
  | _ => some .paragraph
private def place : Nat → Option (Nat × Bool)
  | 0 => some (99, true)
  | 1 => some (11, true)
  | 3 => some (33, true)
  | 4 => some (44, false)
  | _ => none
example : figurePairs kinds place 0 5 = rows := by decide
example : view (valueJobs eligible initState 5 (figurePairs kinds place 0 5)) = [(1, (3, 112)), (3, (1, 136))] := by decide
example : fromPairs (figurePairs kinds place 0 5) 1 = some (11, true) := by decide
example : fromPairs (figurePairs kinds place 0 5) 3 = some (33, true) := by decide
example : fromPairs (figurePairs kinds place 0 5) 0 = none := by decide
