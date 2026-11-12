import Arguments

open ArgumentDiagnostics

private def code : Error → String
  | .unknown => "G02119"
  | .duplicate => "G02077"
  | .wrongType => "G02121"
  | .missing => "G02120"

def main : IO Unit := do
  let args : List Argument :=
    [ ⟨"x", .nat⟩, ⟨"x", .nat⟩, ⟨"tax", .bool⟩,
      ⟨"tax", .string⟩, ⟨"unit", .string⟩ ]
  for finding in check bookPrice args do
    IO.println s!"price\t{finding.position}\t{code finding.error}\t{finding.name}"
  for ordinal in positionalMissing 1 3 do
    IO.println s!"missing\t{ordinal}\tG02120\t{ordinal}"
