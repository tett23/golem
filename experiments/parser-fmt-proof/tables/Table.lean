/- Golem ADR 0351 I9/I10. Work on decoded Unicode scalar values so
   separator, quote and cell characters have the same representation. -/
namespace TableFormat

-- A CR has already emitted LF. Consume the following LF if present.
def newlines : Bool → List Char → List Char
  | _, [] => []
  | skipLF, c :: rest =>
      if c = '\r' then '\n' :: newlines true rest
      else if skipLF && c == '\n' then newlines false rest
      else c :: newlines false rest

theorem noCR (input : List Char) (skipLF : Bool) :
    '\r' ∉ newlines skipLF input := by
  induction input generalizing skipLF with
  | nil => simp [newlines]
  | cons c rest ih =>
      simp only [newlines]
      split <;> simp_all
      split <;> simp_all [eq_comm]

theorem cleanFixed (input : List Char) (clean : '\r' ∉ input) :
    newlines false input = input := by
  induction input with
  | nil => rfl
  | cons c rest ih =>
      have h : c ≠ '\r' := fun eq => clean (eq ▸ List.Mem.head _)
      have tail : '\r' ∉ rest := fun member => clean (List.Mem.tail _ member)
      simp [newlines, h, ih tail]

theorem newlineIdempotent (input : List Char) :
    newlines false (newlines false input) = newlines false input :=
  cleanFixed _ (noCR _ _)

-- Corrupting LF creates a lone CR only when the next scalar is not LF.
theorem repairLoneCR (before after : List Char)
    (cleanBefore : '\r' ∉ before) (cleanAfter : '\r' ∉ after)
    (lone : after.head? ≠ some '\n') :
    newlines false (before ++ '\r' :: after) = before ++ '\n' :: after := by
  induction before with
  | nil =>
      cases after with
      | nil => decide
      | cons c rest =>
          have cr : c ≠ '\r' := fun eq => cleanAfter (eq ▸ List.Mem.head _)
          have lf : c ≠ '\n' := by simpa using lone
          have tail : '\r' ∉ rest := fun member => cleanAfter (List.Mem.tail _ member)
          simp [newlines, cr, lf, cleanFixed rest tail]
  | cons c rest ih =>
      have cr : c ≠ '\r' := fun eq => cleanBefore (eq ▸ List.Mem.head _)
      have tail : '\r' ∉ rest := fun member => cleanBefore (List.Mem.tail _ member)
      simp [newlines, cr, ih tail]

example : newlines false "a\r\r\nb\r".toList = "a\n\nb\n".toList := by decide

end TableFormat
