import ArgumentsRoundTrip
namespace WordEof
set_option autoImplicit false
private theorem generated_ordinary_ranges :
    WordRoundTrip.ordinaryWordRanges =
      [(32, 32), (9, 9), (10, 10), (93, 93), (58, 58),
       (124, 124), (61, 61), (91, 91), (34, 34), (92, 92)] := by rfl
private theorem ordinary_permitted_is_allowed :
    PegModelTest.permitted WordRoundTrip.ordinaryWordRanges = WordRoundTrip.allowed := by
  funext c
  simp [PegModelTest.permitted, WordRoundTrip.ordinary_ranges_allowed]
private theorem drop_allowed (chars : List Char)
    (valid : ∀ c ∈ chars, WordRoundTrip.allowed c = true) :
    chars.dropWhile WordRoundTrip.allowed = [] := by
  induction chars with
  | nil => rfl
  | cons first rest ih =>
    have firstHit := valid first (by simp)
    have later := ih (by intro c member; exact valid c (List.mem_cons_of_mem _ member))
    simpa [List.dropWhile,firstHit] using later

theorem I1_word_at_eof (word : WordRoundTrip.Word) (extra : Nat)
    (safe : WordRoundTrip.startsComment word.chars = false) :
    PegModel.recognizeEnv Generated.pegGrammar [] (word.chars.length+8+extra)
      (.ref "Word" []) word.chars = .ok (some []) := by
  have miss := (WordRoundTrip.safe_comment_prefixes word.chars safe).2
  cases chars : word.chars with
  | nil => exact False.elim (word.nonempty chars)
  | cons first rest =>
    have miss' : "%%=".toList.isPrefixOf (first::rest) = false := by simpa [chars] using miss
    have model := PegModelTest.generated_word_ordinary_total (first::rest) extra miss'
    rw [← generated_ordinary_ranges, ordinary_permitted_is_allowed] at model
    have allowed : WordRoundTrip.allowed first = true := word.valid first (by simp [chars])
    have rangeMiss : WordRoundTrip.ordinaryWordRanges.any
        (fun (lo,hi) => lo ≤ first.toNat && first.toNat ≤ hi) = false := by
      rw [WordRoundTrip.ordinary_ranges_allowed,allowed]
      rfl
    have dropped : rest.dropWhile WordRoundTrip.allowed = [] :=
      drop_allowed rest (by intro c member; exact word.valid c (by simp [chars,member]))
    simpa [chars,rangeMiss,dropped] using model
#print axioms I1_word_at_eof
end WordEof
