import Eval

open GolemEval

private def arithmetic : Nat → List (String × Expr)
  | 0 => [("0", .literal (.nat 0)), ("1", .literal (.nat 1))]
  | depth + 1 =>
    let children := arithmetic depth
    arithmetic 0 ++ children.bind fun (a, x) => children.bind fun (b, y) =>
      [("(" ++ a ++ " + " ++ b ++ ")", .add x y), ("(div " ++ a ++ " " ++ b ++ ")", .quotient x y)]

def main : IO Unit := do
  let branches := arithmetic 1
  let choices := [true, false].bind fun c => branches.bind fun (a, x) => branches.map fun (b, y) =>
    ("(" ++ (if c then "True" else "False") ++ " ? " ++ a ++ " : " ++ b ++ ")",
     Expr.ternary (.literal (.boolean c)) x y)
  for (source, expr) in arithmetic 2 ++ choices do
    for budget in List.range 5 do
      let value ← match eval budget ⟨[], []⟩ expr with
        | .ok (.nat n) => pure (toString n)
        | .error .overLimit => pure "E04100"
        | .error .divisionByZero => pure "G02003"
        | _ => throw (IO.userError s!"unexpected result for {source} at {budget}")
      IO.println s!"{budget} {source} => {value}"
