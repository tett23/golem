import Lean
import Proof

namespace StringProof

-- These two keyword spellings follow a quoted positional path in @listing.
inductive Arg where
  | lang
  | lines
  deriving DecidableEq, Repr

def spell : Arg → List Char
  | .lang => " lang=haskell".toList
  | .lines => " lines=1...3".toList

def printArgs : List Arg → List Char
  | [] => ['\n']
  | arg :: rest => spell arg ++ printArgs rest

def parseArgs : Nat → List Char → Option (List Arg)
  | _, ['\n'] => some []
  | fuel + 1, ' ' :: 'l' :: 'a' :: 'n' :: 'g' :: '=' :: 'h' :: 'a' :: 's' :: 'k' :: 'e' :: 'l' :: 'l' :: rest =>
      (parseArgs fuel rest).map (Arg.lang :: ·)
  | fuel + 1, ' ' :: 'l' :: 'i' :: 'n' :: 'e' :: 's' :: '=' :: '1' :: '.' :: '.' :: '.' :: '3' :: rest =>
      (parseArgs fuel rest).map (Arg.lines :: ·)
  | _, _ => none

def printListing (args : List Arg) : String :=
  String.mk ("@listing \"a\\\"b\"".toList ++ printArgs args)

-- The quoted positional path is read through the ordered StringLit branch.
def parseListing (fuel : Nat) : List Char → Option (List Arg)
  | '@' :: 'l' :: 'i' :: 's' :: 't' :: 'i' :: 'n' :: 'g' :: ' ' :: '"' :: rest =>
      match Proof.scanString Generated.stringLitEscapeFirst rest with
      | some (['a', '\\', '"', 'b'], suffix) => parseArgs fuel suffix
      | _ => none
  | _ => none

theorem parse_print_args (args : List Arg) : ∀ fuel, args.length ≤ fuel → parseArgs fuel (printArgs args) = some args := by
  induction args with
  | nil => intro fuel _; cases fuel <;> rfl
  | cons arg rest ih =>
      intro fuel enough
      cases fuel with
      | zero => simp at enough
      | succ n =>
          have h : rest.length ≤ n := Nat.le_of_succ_le_succ enough
          cases arg <;> simp [printArgs, spell, parseArgs, ih n h]

theorem toList_mk (chars : List Char) : (String.mk chars).toList = chars := by rfl

theorem enough_input (args : List Arg) : args.length ≤ (printArgs args).length := by
  induction args with
  | nil => decide
  | cons arg rest ih =>
      cases arg <;> simp [printArgs, spell, List.length_append, show " lang=haskell".toList.length = 13 by decide, show " lines=1...3".toList.length = 12 by decide] <;> omega

theorem parse_print_listing (args : List Arg) :
    parseListing (printListing args).toList.length (printListing args).toList = some args := by
  have bound := enough_input args
  simp [printListing, toList_mk, parseListing, Proof.scanString, Generated.stringLitEscapeFirst,
        show "@listing \"a\\\"b\"".toList =
        ['@', 'l', 'i', 's', 't', 'i', 'n', 'g', ' ', '"', 'a', '\\', '"', 'b', '"'] by decide]
  apply parse_print_args
  omega

example : printListing [.lang, .lines] = "@listing \"a\\\"b\" lang=haskell lines=1...3\n" := by decide
example : printListing [.lines, .lang] = "@listing \"a\\\"b\" lines=1...3 lang=haskell\n" := by decide

end StringProof
