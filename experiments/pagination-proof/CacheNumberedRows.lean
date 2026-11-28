import LaterEdits
import NumberedPayload
namespace BesideCacheNumberedRows
open BesideOwnership BesideProducer BesideReuse BesideFigureTable BesideJobValues BesideClassifiedPrefix BesideOwnedUnion BesideBodyEdits BesideOwnedFirst BesideLaterEdits BesidePayloadRounds BesideStore NumberedPayload

noncomputable def numberedFrom (table : Nat → Option Nat) (target before : Nat) (rows : List δ) : Option (List (Nat × δ)) :=
  (table target).map (fun ident => numberRows (ident + before) rows)

private theorem numbered_present (table : Nat → Option Nat) (target before ident : Nat) (rows : List δ)
    (present : table target = some ident) : numberedFrom table target before rows = some (numberRows (ident + before) rows) := by
  simp only [numberedFrom, present, Option.map]

theorem root_adr0352_i5_history_cache_numbered_rows
    (rounds : List (PayloadRound σ α)) (cache : PayloadCache α)
    (reached : runPayloadRounds none rounds = some cache) (prior : List (BodyEdit α))
    (place : Nat → Option ρ) (eligible : ρ → Bool) (initState : Nat → ρ → τ)
    (job : ReuseJob τ) (target next attempts : Nat) (changeAt : Nat → α → α)
    (size : α → Nat) (skip : Nat → Bool) (slots : List CountSlot) (beginBase endBase : Nat → Option Nat)
    (committed tail : List δ)
    (member : job ∈ valueJobs eligible initState cache.count (figurePairs cache.kindAt place 0 cache.count))
    (selected : target ∈ candidateKeys (fromPairs cache.pairs) cache.kindAt job.owner cache.count) :
    let body := applyEdits (fromPairs cache.pairs) prior
    let updated := applyEdits body (suffixPrefixEdits (candidateKeys body cache.kindAt job.owner cache.count) target attempts changeAt)
    let oldTable := leftUnion (ownedTable body cache.kindAt cache.count next size skip slots place eligible initState) beginBase
    let newTable := leftUnion (ownedTable updated cache.kindAt cache.count next size skip slots place eligible initState) endBase
    ∃ ident tagged, oldTable target = some ident ∧ newTable target = some ident ∧
      numberedFrom newTable target committed.length tail = some tagged ∧
      numberRows ident (committed ++ tail) = numberRows ident committed ++ tagged ∧
      tagged.map Prod.fst = PhysicalPagination.ids (ident + committed.length) tail.length ∧
      tagged.map Prod.snd = tail ∧
      (∀ index, tagged.get? index = (tail.get? index).map (fun row => (ident + committed.length + index, row))) := by
  dsimp only
  rcases root_adr0352_i5_history_suffix_prefix_exists_same rounds cache reached prior place eligible initState job target next attempts changeAt size skip slots beginBase endBase member selected with ⟨ident, oldSome, newSome⟩
  refine ⟨ident, numberRows (ident + committed.length) tail, oldSome, newSome, ?_, ?_, ?_, ?_, ?_⟩
  · exact numbered_present _ target committed.length ident tail newSome
  · exact root_adr0352_i5_numbered_row_append committed tail ident
  · exact root_adr0352_i5_numbered_row_ids tail (ident + committed.length)
  · exact root_adr0352_i5_numbered_row_payload tail (ident + committed.length)
  · intro index
    exact root_adr0352_i5_numbered_row_at tail index (ident + committed.length)
end BesideCacheNumberedRows
