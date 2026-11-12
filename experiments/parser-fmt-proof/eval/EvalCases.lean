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
  let strings := ["", "甲", "𠮷", "a甲", "e\u0301"]
  let appends := strings.bind fun a => strings.map fun b =>
    ("(\"" ++ a ++ "\" ++ \"" ++ b ++ "\")", Expr.append (.literal (.string a)) (.literal (.string b)))
  let suffix := Expr.literal (.string "甲")
  let nested := (appends.map fun (s, e) => ("(" ++ s ++ " ++ \"甲\")", Expr.append e suffix)) ++
    (appends.map fun (s, e) => ("(\"甲\" ++ " ++ s ++ ")", Expr.append suffix e))
  let inc := fun arg => Expr.call "n" arg (.add (.variable "n") (.literal (.nat 1)))
  let calls := ["inc", "twice"].bind fun name => branches.map fun (s, arg) =>
    ("(" ++ name ++ " " ++ s ++ ")", if name == "inc" then inc arg
      else Expr.call "n" arg (inc (inc (.variable "n"))))
  for (source, expr) in arithmetic 2 ++ choices ++ appends ++ nested ++ calls do
    for budget in List.range 10 do
      let value ← match eval budget ⟨[], []⟩ expr with
        | .ok (.nat n) => pure (toString n)
        | .ok (.string s) => pure ("string " ++ s)
        | .error .overLimit => pure "E04100"
        | .error .divisionByZero => pure "G02003"
        | _ => throw (IO.userError s!"unexpected result for {source} at {budget}")
      IO.println s!"{budget} {source} => {value}"
  for contents in ([none, some "", some "甲𠮷"] : List (Option String)) do
    let files := contents.toList.map fun t => ("input.tsv", t)
    for budget in List.range 5 do
      let expr := Expr.call "n" (.literal (.nat 0)) (.external "input.tsv")
      let value ← match eval budget ⟨[], files⟩ expr with
        | .ok (.string s) => pure ("string " ++ s)
        | .error .overLimit => pure "E04100"
        | .error .missingFile => pure "E05104"
        | _ => throw (IO.userError "unexpected file result")
      let input := contents.elim "missing" ("present " ++ ·)
      IO.println s!"{budget} readInput {input} => {value}"
