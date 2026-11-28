import CacheNumberedRows
namespace BesideCacheBreaker
open BesideOwnership BesideProducer BesideReuse BesideFigureTable BesideJobValues BesideClassifiedPrefix BesideOwnedUnion BesideBodyEdits BesideOwnedFirst BesideLaterEdits BesidePayloadRounds BesideStore BesideSuffixCountPrefix BesideCacheNumberedRows NumberedPayload PhysicalPagination

noncomputable def physicalRows (tagged : List (Nat × (Line × Nat))) : List (Line × Nat) :=
  tagged.map (fun row => ({row.2.1 with id := row.1}, row.2.2))

noncomputable def cachedBreaker (tables : St → Nat → Nat → Nat → Option Nat) (target : Nat)
    (raw : St → Nat → Nat → List (Line × Nat)) (at' : St) (before start : Nat) : List (Line × Nat) :=
  physicalRows ((numberedFrom (tables at' before start) target before (raw at' before start)).getD [])

private theorem physical_ids (rows : List (Line × Nat)) (next : Nat) :
    lineIds ((physicalRows (numberRows next rows)).map Prod.fst) = ids next rows.length := by
  induction rows generalizing next with
  | nil => rfl
  | cons row later ih =>
    rcases row with ⟨line, position⟩
    simp only [physicalRows, numberRows, List.map_cons, lineIds, ids, List.length_cons, Line.id]
    simpa only [physicalRows, lineIds] using congrArg (List.cons next) (ih (next + 1))

private theorem physical_length (rows : List (Line × Nat)) (next : Nat) :
    (physicalRows (numberRows next rows)).length = rows.length := by
  induction rows generalizing next with
  | nil => rfl
  | cons row later ih =>
    simp only [physicalRows, numberRows, List.map_cons, List.length_cons]
    simpa only [physicalRows] using congrArg Nat.succ (ih (next + 1))

private theorem physical_metadata (rows : List (Line × Nat)) (next : Nat) :
    (physicalRows (numberRows next rows)).map (fun row => (row.1.notes, row.1.overhang, row.2)) =
      rows.map (fun row => (row.1.notes, row.1.overhang, row.2)) := by
  induction rows generalizing next with
  | nil => rfl
  | cons row later ih =>
    rcases row with ⟨line, position⟩
    simp only [physicalRows, numberRows, List.map_cons]
    simpa only [physicalRows] using congrArg (List.cons (line.notes, line.overhang, position)) (ih (next + 1))

private theorem breaker_numbered (tables : St → Nat → Nat → Nat → Option Nat) (target ident : Nat)
    (raw : St → Nat → Nat → List (Line × Nat))
    (present : ∀ at' before start, tables at' before start target = some ident) :
    ∀ at' before start, lineIds ((cachedBreaker tables target raw at' before start).map Prod.fst) =
      ids (ident + before) (cachedBreaker tables target raw at' before start).length := by
  intro at' before start
  simp only [cachedBreaker, numberedFrom, present, Option.map, Option.getD]
  rw [physical_ids, physical_length]

private theorem breaker_metadata (tables : St → Nat → Nat → Nat → Option Nat) (target ident : Nat)
    (raw : St → Nat → Nat → List (Line × Nat))
    (present : ∀ at' before start, tables at' before start target = some ident) :
    ∀ at' before start,
      (cachedBreaker tables target raw at' before start).map (fun row => (row.1.notes, row.1.overhang, row.2)) =
      (raw at' before start).map (fun row => (row.1.notes, row.1.overhang, row.2)) := by
  intro at' before start
  simp only [cachedBreaker, numberedFrom, present, Option.map, Option.getD]
  exact physical_metadata _ _

noncomputable def recomputedTables (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ) (target : Nat)
    (change : St → Nat → Nat → α → α) (base : St → Nat → Nat → Nat → Option Nat) : St → Nat → Nat → Nat → Option Nat :=
  fun at' before start => leftUnion (ownedTable (adjustBeside (change at' before start) target body) current count next size skip slots place eligible initState) (base at' before start)

private theorem uniform_first
    (body : Nat → Option α) (current : Nat → Option Kind) (count next : Nat)
    (typed : ∀ key, (body key).isSome = true → current key = some .paragraph)
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target : Nat) (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot)
    (beginBase : Nat → Option Nat) (base : St → Nat → Nat → Nat → Option Nat) (change : St → Nat → Nat → α → α)
    (member : job ∈ valueJobs eligible initState count (figurePairs current place 0 count))
    (selected : target ∈ candidateKeys body current job.owner count) :
    ∃ ident, leftUnion (ownedTable body current count next size skip slots place eligible initState) beginBase target = some ident ∧
      ∀ at' before start, recomputedTables body current count next size skip slots place eligible initState target change base at' before start target = some ident := by
  rcases root_adr0352_i5_later_update_preserves_existing_union_first body current count next typed place eligible initState job target target size id skip slots beginBase beginBase member selected (Nat.le_refl target) with ⟨ident, oldSome, _⟩
  refine ⟨ident, oldSome, ?_⟩
  intro at' before start
  rcases root_adr0352_i5_later_update_preserves_existing_union_first body current count next typed place eligible initState job target target size (change at' before start) skip slots beginBase (base at' before start) member selected (Nat.le_refl target) with ⟨other, otherOld, otherNew⟩
  have same : other = ident := Option.some.inj (otherOld.symm.trans oldSome)
  simpa only [recomputedTables, same] using otherNew

theorem root_adr0352_i5_cache_backed_parts_lines
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache) (prior : List (BodyEdit α))
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target next : Nat) (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot)
    (beginBase : Nat → Option Nat) (base : St → Nat → Nat → Nat → Option Nat) (change : St → Nat → Nat → α → α)
    (env : Env) (region : Region) (raw : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St) (hh : ∀ st, Step st (hold st) [] [])
    (member : job ∈ valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))
    (selected : target ∈ candidateKeys (fromPairs cache.pairs) cache.kindAt job.owner cache.count) :
    let body := applyEdits (fromPairs cache.pairs) prior
    let breaker := cachedBreaker (recomputedTables body cache.kindAt cache.count next size skip slots place eligible initState target change base) target raw
    ∃ ident, leftUnion (ownedTable body cache.kindAt cache.count next size skip slots place eligible initState) beginBase target = some ident ∧
      (∀ at' before start,
        lineIds ((breaker at' before start).map Prod.fst) = ids (ident + before) (breaker at' before start).length ∧
        (breaker at' before start).map (fun row => (row.1.notes, row.1.overhang, row.2)) =
          (raw at' before start).map (fun row => (row.1.notes, row.1.overhang, row.2))) ∧
      ∀ limit k isStart start before at' final,
      parts env region breaker items lastWanted follows hold limit k isStart start before at' = .ok final →
      ∃ consumed, Step at' final (ids (ident + before) consumed) [] := by
  let body := applyEdits (fromPairs cache.pairs) prior
  have typed : ∀ key, (body key).isSome = true → cache.kindAt key = some .paragraph := root_adr0352_i5_reached_body_edits_typed rounds cache reached prior
  have currentSelected : target ∈ candidateKeys body cache.kindAt job.owner cache.count := by
    rw [root_adr0352_i5_body_edits_selected]
    exact selected
  rcases uniform_first body cache.kindAt cache.count next typed place eligible initState job target size skip slots beginBase base change member currentSelected with ⟨ident, oldSome, present⟩
  have hb := breaker_numbered _ target ident raw present
  have hm := breaker_metadata _ target ident raw present
  refine ⟨ident, oldSome, ?_, ?_⟩
  · intro at' before start
    exact ⟨hb at' before start, hm at' before start⟩
  · exact I5_parts_lines env region _ items lastWanted follows hold ident hb hh
end BesideCacheBreaker
