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
  for supplied in [0, 1, 2] do
    for ordinal in positionalMissing supplied 3 do
      IO.println s!"missing-{supplied}\t{ordinal}\tG02120\t{ordinal}"
