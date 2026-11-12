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

-- The two substitutions in Golem.Fmt.formatTable, in application order.
def replaceCRLF : List Char → List Char
  | [] => []
  | c :: rest =>
      if c = '\r' ∧ rest.head? = some '\n' then replaceCRLF rest
      else c :: replaceCRLF rest

def replaceCR (c : Char) : Char := if c = '\r' then '\n' else c

theorem twoPassEqualsModel (input : List Char) :
    (replaceCRLF input).map replaceCR = newlines false input := by
  induction input with
  | nil => rfl
  | cons c rest ih =>
      by_cases cr : c = '\r'
      · subst c
        cases rest with
        | nil => rfl
        | cons d tail =>
            by_cases lf : d = '\n'
            · subst d
              simp [replaceCRLF, replaceCR, newlines] at ih ⊢
              exact ih
            · simpa [replaceCRLF, replaceCR, newlines, lf] using ih
      · simp [replaceCRLF, cr, replaceCR, ih, newlines]

-- In particular, quotes, delimiters, spaces and every scalar in a cell
-- other than its line endings keep their original order and multiplicity.
def nonNewline (c : Char) : Bool := c != '\r' && c != '\n'

theorem preserveNonNewlines (input : List Char) (skipLF : Bool) :
    (newlines skipLF input).filter nonNewline = input.filter nonNewline := by
  induction input generalizing skipLF with
  | nil => rfl
  | cons c rest ih =>
      by_cases cr : c = '\r'
      · subst c; simp [newlines, nonNewline, ih]
      · by_cases lf : c = '\n'
        · subst c; cases skipLF <;> simp [newlines, nonNewline, ih]
        · simp [newlines, cr, lf, List.filter, ih]

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

-- A writer can choose LF or CRLF separately for every newline, even
-- inside a quoted CSV field. All other scalar values are copied.
inductive LineEncoding : List Char → List Char → Prop where
  | empty : LineEncoding [] []
  | scalar (c : Char) (ordinary : c ≠ '\r') (rest : LineEncoding xs ys) :
      LineEncoding (c :: xs) (c :: ys)
  | crlf (rest : LineEncoding xs ys) :
      LineEncoding ('\n' :: xs) ('\r' :: '\n' :: ys)

theorem decodeLineEncoding (encoded : LineEncoding canonical bytes) :
    newlines false bytes = canonical := by
  induction encoded with
  | empty => rfl
  | scalar c ordinary _ ih => simp [newlines, ordinary, ih]
  | crlf _ ih => simp [newlines, ih]

theorem newlineIdempotent (input : List Char) :
    newlines false (newlines false input) = newlines false input :=
  cleanFixed _ (noCR _ _)

-- Golem ADR 0354 applies only to table files.
def bom : Char := Char.ofNat 0xFEFF

def stripBOM : List Char → List Char
  | [] => []
  | c :: rest => if c = bom then stripBOM rest else c :: rest

def formatTable (input : List Char) := newlines false (stripBOM input)

theorem stripLeadingRun (count : Nat) (contents : List Char) :
    stripBOM (List.replicate count bom ++ contents) = stripBOM contents := by
  induction count with
  | zero => rfl
  | succ n ih => simpa [List.replicate, stripBOM] using ih

theorem formatEncodedTable (encoded : LineEncoding canonical contents)
    (first : canonical.head? ≠ some bom) (count : Nat) :
    formatTable (List.replicate count bom ++ contents) = canonical := by
  unfold formatTable
  rw [stripLeadingRun]
  have clean : stripBOM contents = contents := by
    cases encoded with
    | empty => rfl
    | scalar c _ _ =>
        have h : c ≠ bom := by simpa using first
        simp [stripBOM, h]
    | crlf _ => simp [stripBOM, bom]
  rw [clean]
  exact decodeLineEncoding encoded

theorem stripAfterFormat (input : List Char) :
    stripBOM (formatTable input) = formatTable input := by
  induction input with
  | nil => rfl
  | cons c rest ih =>
      by_cases b : c = bom
      · simpa [formatTable, stripBOM, b] using ih
      · by_cases cr : c = '\r'
        · subst c; simp [formatTable, stripBOM, newlines, bom]
        · simp [formatTable, stripBOM, newlines, b, cr]

theorem tableIdempotent (input : List Char) :
    formatTable (formatTable input) = formatTable input := by
  unfold formatTable at *
  rw [show stripBOM (newlines false (stripBOM input)) = newlines false (stripBOM input)
      from stripAfterFormat input]
  exact newlineIdempotent _

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

-- Even when earlier rows mix LF and CRLF, fixing one lone CR leaves
-- the decoded prefix unchanged. The suffix can use either encoding too.
theorem decodeWithSuffix (encoded : LineEncoding canonical bytes) (suffix : List Char) :
    newlines false (bytes ++ suffix) = canonical ++ newlines false suffix := by
  induction encoded with
  | empty => rfl
  | scalar c ordinary _ ih => simp [newlines, ordinary, ih]
  | crlf _ ih => simp [newlines, ih]

theorem repairEncodedLoneCR (leftEncoding : LineEncoding before encodedBefore)
    (suffix : LineEncoding after encodedAfter) (lone : encodedAfter.head? ≠ some '\n') :
    newlines false (encodedBefore ++ '\r' :: encodedAfter) = before ++ '\n' :: after := by
  rw [decodeWithSuffix leftEncoding]
  have resume : newlines true encodedAfter = newlines false encodedAfter := by
    cases encodedAfter with
    | nil => rfl
    | cons c rest =>
        have lf : c ≠ '\n' := by simpa using lone
        simp [newlines, lf]
  simp [newlines, resume, decodeLineEncoding suffix]

example : newlines false "a\r\r\nb\r".toList = "a\n\nb\n".toList := by decide

def firstLoneCR : List Char → Nat → Option Nat
  | [], _ => none
  | c :: rest, offset =>
      if c = '\r' ∧ rest.head? ≠ some '\n' then some offset
      else firstLoneCR rest (offset + c.utf8Size.toNat)

def byteLength : List Char → Nat
  | [] => 0
  | c :: rest => c.utf8Size.toNat + byteLength rest

theorem scanEncodedPrefix (encoded : LineEncoding canonical bytes)
    (tail : List Char) (offset : Nat) :
    firstLoneCR (bytes ++ tail) offset = firstLoneCR tail (offset + byteLength bytes) := by
  induction encoded generalizing offset with
  | empty => simp [byteLength]
  | scalar c ordinary _ ih => simp [firstLoneCR, ordinary, byteLength, ih, Nat.add_assoc]
  | crlf _ ih => simp [firstLoneCR, byteLength, ih, Nat.add_assoc]

theorem I10_loneCRByteOffset (encoded : LineEncoding canonical bytes)
    (tail : List Char) (lone : tail.head? ≠ some '\n') :
    firstLoneCR (bytes ++ '\r' :: tail) 0 = some (byteLength bytes) := by
  rw [scanEncodedPrefix encoded]
  simp [firstLoneCR, lone]

-- The diagnostic reports a byte offset, including after multibyte cell text.
example : firstLoneCR "名\r\n甲\rb".toList 0 = some 8 := by decide

end TableFormat
