import FigureWindow
open BesideProducer BesideReuse BesideStore BesideFigureTable BesideFigureWindow

private def table : Nat → Option Nat
  | 1 => some 11
  | 3 => some 33
  | _ => none
example : readWindow table 0 5 = [(1, 11), (3, 33)] := by decide

example : readWindow table 0 0 = [] := by decide
example : readWindow table 0 1 = [] := by decide
example : readWindow table 1 3 = [(1, 11), (3, 33)] := by decide
example : readWindow table 2 2 = [(3, 33)] := by decide
example : readWindow table 4 4 = [] := by decide
example : readWindow table 1 2 = [(1, 11)] := by decide
private def kinds : Nat → Option Kind
  | 1 => some .figure
  | 3 => some .figure
  | _ => some .paragraph
example : readWindow (fromPairs (figurePairs kinds table 0 5)) 0 5 = [(1, 11), (3, 33)] := by decide
private def stateAt (key : Nat) : Nat := key + 10
private def jobView (jobs : List (ReuseJob Nat)) : List (Nat × (Nat × Nat)) :=
  jobs.map (fun job => (job.owner, (job.fuel, job.state)))
example : jobView (rowJobs (fun _ => true) stateAt 5 [(1, 11), (3, 33)]) = [(1, (3, 11)), (3, (1, 13))] := by decide
example : jobView (rowJobs (fun value => decide (value > 20)) stateAt 5 [(1, 11), (3, 33)]) = [(3, (1, 13))] := by decide
example : jobView (tableJobs table (fun value => decide (value > 20)) stateAt 5 0 5) = [(3, (1, 13))] := by decide
