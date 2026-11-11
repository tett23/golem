import Generated

namespace Proof

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

end Proof
