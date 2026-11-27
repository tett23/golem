import Pagination
import Physical

namespace GolemPagination

/-- Obtain the chosen node's source-candidate history from the actual
    pass scan, not from an extra assumption about the returned node. -/
theorem root_adr0352_i4_chosen_break_history (ps : CaptionParams) (items : List CaptionItem)
    (pass : Nat) (node : CaptionActiveNode) (chosen : captionCompared ps items = some (pass, node)) :
    CaptionNodeHistory (captionContext ps items pass).candidates node := by
  have once := captionFirstPass_pass ps items _ pass node chosen
  simp only [captionPass] at once
  split at once
  · simp at once
  · rename_i final ran
    have member := (List.mem_filter.mp (captionPickEnd_member _ node once)).1
    have original : CaptionCandidatesOrdered 0 (captionContext ps items pass).items.length
        (captionContext ps items pass).candidates := by
      simpa only [captionContext, Nat.zero_add] using
        I1_caption_generated_scan_order (pass != 1) false 0 (items.map (·.kind))
    have history := I1_caption_scan_runs_history (captionContext ps items pass) _ final
      (captionScanFuel_runs _ _ _ final ran) original
      (I1_caption_full_scan_start_valid _ original) (I1_caption_scan_history_start _)
    exact (history.1.2 node member).1

private theorem inAppend {α : Type} (x : α) (xs ys : List α) :
    x ∈ xs ++ ys ↔ x ∈ xs ∨ x ∈ ys := by
  induction xs with
  | nil => simp
  | cons head tail ih => simp [List.mem_cons, ih, or_assoc]

private theorem reverseMember {α : Type} {x : α} {xs : List α}
    (member : x ∈ xs.reverse) : x ∈ xs := by
  induction xs with
  | nil => simp at member
  | cons head tail ih =>
    rw [List.reverse_cons] at member
    rcases (inAppend x tail.reverse [head]).mp member with earlier | last
    · exact List.Mem.tail _ (ih earlier)
    · simp only [List.mem_cons, List.not_mem_nil, or_false] at last
      subst last
      exact List.Mem.head _

/-- Every returned break is a real item of the supplied source suffix. -/
theorem root_adr0352_i4_chosen_break_range (ps : CaptionParams) (items : List CaptionItem)
    (pass : Nat) (node : CaptionActiveNode) (chosen : captionCompared ps items = some (pass, node))
    (position : Nat) (member : position ∈ captionComparedBreaks node) :
    position < items.length := by
  have history := root_adr0352_i4_chosen_break_history ps items pass node chosen
  obtain ⟨entry, inReverse, samePosition⟩ := List.mem_map.mp member
  have inHistory : entry ∈ node.history := reverseMember inReverse
  have candidate := history.2.2.1 entry inHistory
  change entry.1 ∈ captionBreakIndices (pass != 1) false 0 (items.map CaptionItem.kind) at candidate
  have range := I1_caption_break_index_range (pass != 1) false 0 entry.1 (items.map CaptionItem.kind) candidate
  simpa only [List.length_map, Nat.zero_add, samePosition] using range.2

/-- Rebreaking the suffix at `start` returns offsets relative to that
    suffix. Adding start and then running after/skip consumes source. -/
theorem root_adr0352_i4_chosen_source_progress (ps : CaptionParams) (source : List CaptionItem)
    (start pass : Nat) (node : CaptionActiveNode)
    (chosen : captionCompared ps (source.drop start) = some (pass, node))
    (position : Nat) (member : position ∈ captionComparedBreaks node) :
    start < captionNextSourceStart (source.map (·.kind)) (start + position + 1) ∧
      captionNextSourceStart (source.map (·.kind)) (start + position + 1) ≤ source.length := by
  have range := root_adr0352_i4_chosen_break_range ps (source.drop start) pass node chosen position member
  simp only [List.length_drop] at range
  have inside : start + position + 1 ≤ (source.map (·.kind)).length := by
    simp only [List.length_map]; omega
  have bound := I1_caption_next_start_bounds (source.map (·.kind)) (start + position + 1) inside
  simp only [List.length_map] at bound
  exact ⟨by omega, bound.2⟩

end GolemPagination

namespace PhysicalPagination

/-- The fallback and selected branches of the modeled trial always consume
    a positive number when they report a placed nonempty segment. -/
theorem root_adr0352_i4_trial_rest_positive (env : Env) (region : Region) (limit : Option Nat)
    (keep : Keep) (isStart : Bool) (cursor : St) (rows : List Line) (firstId count : Nat)
    (placed : St) (relaxed : Keep)
    (result : trialWrapRest env region limit keep isStart cursor rows firstId = .ok (.placed count placed relaxed)) :
    0 < count := by
  exact trialWrapRest_placed env region limit keep isStart cursor rows firstId count placed relaxed result

/-- A successful split trial of nonempty rows cannot return zero and
    then ask the caller to take the last element of an empty prefix. -/
theorem root_adr0352_i4_trial_partial_positive (env : Env) (region : Region) (limit : Option Nat)
    (keep : Keep) (isStart : Bool) (cursor : St) (rows : List Line) (count : Nat)
    (placed : St) (relaxed : Keep)
    (result : trialWrap env region limit keep isStart cursor rows = .ok (.placed count placed relaxed))
    (partialResult : count < rows.length) : 0 < count := by
  unfold trialWrap at result
  split at result
  · cases result
  unfold trialWrapFrom at result
  split at result
  · injection result with same
    injection same with sameCount _ _
    subst count
    simp_all
  · split at result
    · cases result
    · split at result
      · split at result
        · exact root_adr0352_i4_trial_rest_positive _ _ _ _ _ _ _ _ _ _ _ result
        · cases result
      · exact root_adr0352_i4_trial_rest_positive _ _ _ _ _ _ _ _ _ _ _ result

end PhysicalPagination

namespace GolemPagination

private theorem getSomeMember {α : Type} (xs : List α) (index : Nat) (inside : index < xs.length) :
    ∃ value, xs.get? index = some value ∧ value ∈ xs := by
  induction xs generalizing index with
  | nil => exact (Nat.not_lt_zero _ inside).elim
  | cons head tail ih =>
    cases index with
    | zero => exact ⟨head, rfl, List.Mem.head _⟩
    | succ index =>
      obtain ⟨value, atIndex, member⟩ := ih index (Nat.lt_of_succ_lt_succ inside)
      exact ⟨value, atIndex, List.Mem.tail _ member⟩

private theorem mappedDropHead {α β : Type} (f : α → β) (xs : List α) (index : Nat) :
    ((xs.map f).drop index).head? = (xs.get? index).map f := by
  induction xs generalizing index with
  | nil => simp
  | cons head tail ih => cases index with
    | zero => rfl
    | succ index => exact ih index

private def plainMap {α β : Type} (f : α → β) : List α → List β
  | [] => []
  | head :: tail => f head :: plainMap f tail

private theorem plainMap_eq_map {α β : Type} (f : α → β) (xs : List α) :
    plainMap f xs = xs.map f := by
  induction xs with
  | nil => rfl
  | cons head tail ih => simp only [plainMap, List.map_cons, ih]

/-- Pair chosen rows with the absolute item-after-break offsets used by
    the `parts` model. The payload is independent of the progress proof. -/
def chosenSourceRows (lineOf : Nat → PhysicalPagination.Line) (source : List CaptionItem)
    (start : Nat) (node : CaptionActiveNode) : List (PhysicalPagination.Line × Nat) :=
  plainMap (fun position =>
    (lineOf position, captionNextSourceStart (plainMap CaptionItem.kind source) (start + position + 1)))
    (captionComparedBreaks node)

/-- This producer's length is the returned node's row count, derived from
    the actual scan history rather than a separate count premise. -/
theorem root_adr0352_i4_chosen_rows_count (ps : CaptionParams) (source : List CaptionItem)
    (start pass : Nat) (node : CaptionActiveNode) (lineOf : Nat → PhysicalPagination.Line)
    (chosen : captionCompared ps (source.drop start) = some (pass, node)) :
    (chosenSourceRows lineOf source start node).length = node.lineCount := by
  have history := root_adr0352_i4_chosen_break_history ps (source.drop start) pass node chosen
  simpa only [chosenSourceRows, plainMap_eq_map, captionComparedBreaks, List.length_map, List.length_reverse] using history.2.1.symm

/-- Positive prefixes of the chosen producer strictly advance the source
    and therefore satisfy both conditions of `parts`'s noProgress guard. -/
theorem root_adr0352_i4_chosen_prefix_progress (ps : CaptionParams) (source : List CaptionItem)
    (start pass count : Nat) (node : CaptionActiveNode) (lineOf : Nat → PhysicalPagination.Line)
    (chosen : captionCompared ps (source.drop start) = some (pass, node))
    (positive : 0 < count) (withinRows : count ≤ node.lineCount) :
    start < PhysicalPagination.nextItem (chosenSourceRows lineOf source start node) count start ∧
      start < source.length := by
  have history := root_adr0352_i4_chosen_break_history ps (source.drop start) pass node chosen
  have length : (captionComparedBreaks node).length = node.lineCount := by
    simpa only [captionComparedBreaks, List.length_map, List.length_reverse] using history.2.1.symm
  obtain ⟨position, atIndex, member⟩ := getSomeMember (captionComparedBreaks node) (count - 1) (by omega)
  have progress := root_adr0352_i4_chosen_source_progress ps source start pass node chosen position member
  have offset : PhysicalPagination.nextItem (chosenSourceRows lineOf source start node) count start =
      captionNextSourceStart (source.map (·.kind)) (start + position + 1) := by
    simp only [PhysicalPagination.nextItem, chosenSourceRows, plainMap_eq_map, mappedDropHead, atIndex]
    rfl
  rw [offset]
  exact ⟨progress.1, by omega⟩

/-- A successful split placement of the rows from the chosen suffix
    discharges the model's source-progress guard without assuming it. -/
theorem root_adr0352_i4_chosen_partial_discharges_progress
    (ps : CaptionParams) (source : List CaptionItem) (start pass : Nat)
    (node : CaptionActiveNode) (lineOf : Nat → PhysicalPagination.Line)
    (chosen : captionCompared ps (source.drop start) = some (pass, node))
    (env : PhysicalPagination.Env) (region : PhysicalPagination.Region) (limit : Option Nat)
    (keep : PhysicalPagination.Keep) (isStart : Bool) (cursor placed : PhysicalPagination.St)
    (count : Nat) (relaxed : PhysicalPagination.Keep)
    (result : PhysicalPagination.trialWrap env region limit keep isStart cursor
      ((chosenSourceRows lineOf source start node).map Prod.fst) = .ok (.placed count placed relaxed))
    (partialResult : count < (chosenSourceRows lineOf source start node).length) :
    start < PhysicalPagination.nextItem (chosenSourceRows lineOf source start node) count start ∧
      start < source.length := by
  have positive := PhysicalPagination.root_adr0352_i4_trial_partial_positive env region limit keep isStart cursor
    ((chosenSourceRows lineOf source start node).map Prod.fst) count placed relaxed result
    (by simpa only [List.length_map] using partialResult)
  have length := root_adr0352_i4_chosen_rows_count ps source start pass node lineOf chosen
  exact root_adr0352_i4_chosen_prefix_progress ps source start pass count node lineOf chosen positive (by omega)

end GolemPagination
