import Generated

namespace StringRoundTrip

def scanString (escapeFirst : Bool) : List Char → Option (List Char × List Char)
  | [] => none
  | '"' :: rest => some ([], rest)
  | '\\' :: next :: rest =>
      if escapeFirst then
        (scanString escapeFirst rest).map fun (value, suffix) => ('\\' :: next :: value, suffix)
      else
        (scanString escapeFirst (next :: rest)).map fun (value, suffix) => ('\\' :: value, suffix)
  | char :: rest =>
      if char == '\n' then none
      else (scanString escapeFirst rest).map fun (value, suffix) => (char :: value, suffix)

structure Plain where
  char : Char
  notSlash : char ≠ '\\'
  notQuote : char ≠ '"'
  notNewline : char ≠ '\n'

inductive Part where
  | plain (value : Plain)
  | escaped (value : Char)

def spell : List Part → List Char
  | [] => []
  | .plain value :: rest => value.char :: spell rest
  | .escaped value :: rest => '\\' :: value :: spell rest

theorem scan_spell (parts : List Part) (tail : List Char) :
    scanString Generated.stringLitEscapeFirst (spell parts ++ '"' :: tail) =
      some (spell parts, tail) := by
  induction parts with
  | nil => simp [spell, scanString]
  | cons part rest ih =>
      simp [Generated.stringLitEscapeFirst] at ih
      cases part with
      | plain value =>
          rcases value with ⟨c, slash, quote, newline⟩
          simp [spell, scanString, slash, quote, newline, ih,
            Generated.stringLitEscapeFirst]
      | escaped value =>
          simp [spell, scanString, ih, Generated.stringLitEscapeFirst]

end StringRoundTrip
