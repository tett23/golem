import Table

private def inputs (alphabet : List Char) : Nat → List (List Char)
  | 0 => [[]]
  | n + 1 => alphabet.bind fun c => (inputs alphabet n).map (c :: ·)

private def scalars (chars : List Char) := String.intercalate "," (chars.map fun c => toString c.toNat)

def main : IO Unit := do
  for n in List.range 8 do
    for input in inputs [TableFormat.bom, '甲', '𠮷', '\r', '\n'] n do
      let result := TableFormat.formatTable input
      IO.println s!"{scalars input} => {scalars result}"

  for (label, separator) in [("csv", ','), ("tsv", '\t')] do
    for n in List.range 6 do
      for input in inputs [TableFormat.bom, '甲', separator, '\n', '\r', '"'] n do
        let output := match TableFormat.checkedTableRows (separator == ',') input with
          | .ok rows => (reprStr (rows.map (List.map (List.map Char.toNat)))).replace " " ""
          | .error code => code
        IO.println s!"{label} {scalars input} => {output}"

  for n in List.range 7 do
    for input in inputs "甲𠮷,\n\r".toList n do
      let report := match TableFormat.firstLoneCR input 0 with
        | none => ""
        | some i => s!"G02082 {i} {i+1}"
      IO.println s!"span {scalars input} => {report}"
