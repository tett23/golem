import UnboundSequenceTotal
namespace RecoveryDispatchTotal
open PegModel

def alternatives : List (List Expr) :=
  [[.lit "[!" "'[!'", .ref "ReservedBracketBody" [], .lit "]" "']'"],
   [.lit "[!" "'[!'"],
   [.lit "@!" "'@!'", .star (.choice [[.notPred (.charClass [(10,10)] "[\\n]"), .any]])],
   [.lit ".." "'..'"]]

private def sourceRule : Rule :=
  (Generated.pegGrammar.rules.find? (fun rule => rule.name == "SkippedReserved")).getD default

private def metadata : List (Nat × Option String) := sourceRule.alts.map (fun alt => (alt.line, alt.action))

private def layout (line : Nat) (details : List (Nat × Option String)) : Rule :=
  { name := "SkippedReserved", line := line, params := [], templateParams := [], resultType := "()",
    alts := (List.range 4).map (fun index =>
      let items := alternatives[index]?.getD []
      { line := (details[index]?.getD (0, none)).1, items := items,
        action := (details[index]?.getD (0, none)).2, constructor := none }) }

theorem unit_ref (grammar : Grammar) (env : Params) (fuel : Nat) (input : List Char)
    (line : Nat) (details : List (Nat × Option String))
    (found : grammar.rules.find? (fun rule => rule.name == "SkippedReserved") = some (layout line details)) :
    recognizeEnv grammar env (fuel + 1) (.ref "SkippedReserved" []) input =
      recognizeEnv grammar [] fuel (.choice alternatives) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]

theorem generated (env : Params) (fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar env (fuel + 2) (.ref "SkippedReserved" []) input =
      foldChoice (fun items => UnboundSequenceTotal.follow
        (fun item rest => recognizeEnv Generated.pegGrammar [] fuel item rest) items input)
        alternatives := by
  rw [unit_ref _ _ _ _ sourceRule.line metadata (by rfl)]
  change runChoices (fun items => runSequence
    (fun scope item rest => recognizeEnv Generated.pegGrammar scope fuel item rest)
    _ [] items input) alternatives = _
  simp [runChoices, foldChoice, alternatives, UnboundSequenceTotal.sequence]

#print axioms generated
end RecoveryDispatchTotal
