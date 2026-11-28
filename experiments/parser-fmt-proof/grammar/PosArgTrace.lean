import ArgumentTrace
import PosArgMetadata
namespace PosArgTrace
open PegModel CstWrapper

def expression (grammar : Grammar) (fuel : Nat) (read : KeywordTrace.Reader) :
    Expr → List Char → KeywordTrace.Result
  | .ref name args,input => read name args input
  | .notPred predicate,input =>
    (recognizeEnv grammar [] fuel (.notPred predicate) input).map
      (fun result => result.map fun rest => (rest,[]))
  | _,_ => .error "unmodeled guarded expression"

def sequence (grammar : Grammar) (fuel : Nat) (read : KeywordTrace.Reader) :
    List Expr → List Char → KeywordTrace.Result
  | [],input => .ok (some (input,[]))
  | item::more,input =>
    match expression grammar fuel read item input with
    | .error reason => .error reason
    | .ok none => .ok none
    | .ok (some (after,first)) =>
      match sequence grammar fuel read more after with
      | .error reason => .error reason
      | .ok none => .ok none
      | .ok (some (rest,last)) => .ok (some (rest,first++last))

def choices (grammar : Grammar) (fuel : Nat) (read : KeywordTrace.Reader) :
    List (List Expr) → List Char → KeywordTrace.Result
  | [],_ => .ok none
  | items::more,input =>
    match sequence grammar fuel read items input with
    | .ok none => choices grammar fuel read more input
    | result => result

def read (grammar : Grammar) (fuel : Nat) (input : List Char) : KeywordTrace.Result :=
  if fuel < 2 then .error "fuel"
  else
    match grammar.rules.find? (fun rule => rule.name == "PosArg") with
    | none => .error "missing guarded trace rule"
    | some rule =>
      if rule.params.isEmpty && rule.templateParams.isEmpty then
        KeywordTrace.finish grammar "PosArg" input
          (choices grammar (fuel-2)
            (fun name args source =>
              if name == "Argument" && args.isEmpty then ArgumentTrace.read grammar (fuel-2) source
              else KeywordTrace.leaf grammar (fuel-2) name args source)
            (rule.alts.map (·.items)) input)
      else .error "unmodeled parameterized guarded trace rule"
end PosArgTrace
