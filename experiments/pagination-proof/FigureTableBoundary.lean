import FigureTable
open BesideProducer BesideReuse BesideStore BesidePayloadRounds BesideFigureTable

private def kinds : Nat → Option Kind
  | 0 => some .figure
  | 1 => some .paragraph
  | 2 => some .figure
  | 3 => some .control
  | 4 => some .figure
  | _ => none
private def place : Nat → Option Bool
  | 0 => some true
  | 1 => some true
  | 2 => some false
  | 3 => some true
  | _ => none
private def stateAt (key : Nat) : Nat := key + 10
private def jobView (jobs : List (ReuseJob Nat)) : List (Nat × (Nat × Nat)) :=
  jobs.map (fun job => (job.owner, (job.fuel, job.state)))

example : figurePairs kinds place 0 5 = [(0, true), (2, false)] := by decide

example : figurePairs kinds place 0 0 = [] := by decide
example : figurePairs kinds place 1 3 = [(2, false)] := by decide
example : figurePairs kinds place 4 1 = [] := by decide
example : fromPairs (figurePairs kinds place 0 5) 0 = some true := by decide
example : fromPairs (figurePairs kinds place 0 5) 1 = none := by decide
example : fromPairs (figurePairs kinds place 0 5) 2 = some false := by decide
example : fromPairs (figurePairs kinds place 0 5) 4 = none := by decide
example : jobView (tableJobs (fromPairs (figurePairs kinds place 0 5)) id stateAt 5 0 5) = [(0, (4, 10))] := by decide
example : jobView (tableJobs (fromPairs (figurePairs kinds place 0 5)) not stateAt 5 0 5) = [(2, (2, 12))] := by decide
example : jobView (tableJobs (fromPairs (figurePairs kinds place 0 5)) (fun _ => true) stateAt 5 0 5) = [(0, (4, 10)), (2, (2, 12))] := by decide
