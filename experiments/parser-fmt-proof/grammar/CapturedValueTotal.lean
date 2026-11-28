import CapturedSequenceTotal
namespace CapturedValueTotal
open PegModel
def value (grammar : Grammar) (read : Params → Expr → List Char → ParseResult) (fuel : Nat) (scope : Params) (item : Expr) (before : List Char) : Except String (Option Nat) := Id.run do
  match item with
  | .bind (some _) (.ref target args) =>
      match grammar.rules.find? (fun rule => rule.name == target) with
      | none => return .ok none
      | some rule =>
          match args.mapM (integer scope), rule.alts with
          | some values, [alt] =>
              match alt.items with
              | leading :: .bind (some captured) (.plus child) :: _ =>
                  if alt.action.map String.trim != some ("length " ++ captured) then return .ok none
                  let params := List.zip rule.params values
                  match read params leading before with
                  | .error reason => return .error reason
                  | .ok none => return .error "bound length prefix failed"
                  | .ok (some start) =>
                      let counted := (List.range fuel).foldl (fun (state : Except String (List Char × Nat × Bool)) _ =>
                        match state with
                        | .error reason => .error reason
                        | .ok (rest, count, true) => .ok (rest, count, true)
                        | .ok (rest, count, false) =>
                            match read params child rest with
                            | .error reason => .error reason
                            | .ok none => .ok (rest, count, true)
                            | .ok (some next) =>
                                if next.length < rest.length then .ok (next, count + 1, false)
                                else .error "zero-width repetition") (.ok (start, 0, false))
                      match counted with
                      | .error reason => return .error reason
                      | .ok (_, count, true) => return .ok (some count)
                      | .ok _ => return .error "fuel exhausted"
              | _ => return .ok none
          | _, _ => return .ok none
  | _ => return .ok none
end CapturedValueTotal
