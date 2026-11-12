import Table

private def inputs : Nat → List (List Char)
  | 0 => [[]]
  | n + 1 => [TableFormat.bom, '甲', '𠮷', '\r', '\n'].bind fun c => (inputs n).map (c :: ·)

private def scalars (chars : List Char) := String.intercalate "," (chars.map fun c => toString c.toNat)

def main : IO Unit := do
  for n in List.range 8 do
    for input in inputs n do
      let result := TableFormat.formatTable input
      IO.println s!"{scalars input} => {scalars result}"
