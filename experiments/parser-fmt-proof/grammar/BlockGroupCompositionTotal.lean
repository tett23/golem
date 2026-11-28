import CachedPayloadCoherence
import LastBoolGuardTotal
import GroupOptionalTotal
namespace BlockGroupCompositionTotal
open PegModel

def finish (ind fuel : Nat) (rest : List Char) (values : List Bool) : ParseResult :=
  if LastBoolGuardTotal.last values then .ok (some rest)
  else match recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+1) (.ref "GroupBody" ["ind"]) rest with
    | .error reason => .error reason
    | .ok none => .ok (some rest)
    | .ok (some next) => .ok (some next)

def group (ind fuel : Nat) (input : List Char) : ParseResult :=
  match CommandCollectionTotal.captured ind (fuel+3) input with
  | .error reason => .error reason
  | .ok none => .ok none
  | .ok (some (rest,values)) => finish ind fuel rest values

def groupItems : List Expr := [.bind (some "cs") (.plus (.ref "BlockCommand" ["ind"])),
  .opt (.choice [[.semanticPred true " not (or (take 1 (reverse cs))) ",.ref "GroupBody" ["ind"]]])]
private def sourceRule : Rule :=
  (Generated.pegGrammar.rules.find? (fun rule => rule.name == "BlockGroup")).getD default
private def layout (line altLine : Nat) (action : Option String) : Rule :=
  {name := "BlockGroup", line := line, params := ["ind"], templateParams := [], resultType := "()",
    alts := [{line := altLine,items := groupItems,action := action,constructor := none}]}
theorem group_ref (grammar : Grammar) (ind fuel : Nat) (input : List Char)
    (line altLine : Nat) (action : Option String)
    (found : grammar.rules.find? (fun rule => rule.name == "BlockGroup") = some (layout line altLine action)) :
    recognizeEnv grammar [("ind",ind)] (fuel+1) (.ref "BlockGroup" ["ind"]) input =
      recognizeEnv grammar [("ind",ind)] fuel (.choice [groupItems]) input := by
  conv => lhs; unfold recognizeEnv; dsimp only; rw [found]

theorem generated (ind fuel : Nat) (input : List Char) :
    recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+5)
      (.ref "BlockGroup" ["ind"]) input = group ind fuel input := by
  rw [group_ref _ _ _ _ sourceRule.line (sourceRule.alts.head?.map (·.line) |>.getD 0)
    (sourceRule.alts.head?.bind (·.action)) (by rfl)]
  change recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+4)
    (.choice [[.bind (some "cs") (.plus (.ref "BlockCommand" ["ind"])),
      .opt (.choice [[.semanticPred true " not (or (take 1 (reverse cs))) ",.ref "GroupBody" ["ind"]]])]]) input = _
  change runChoices (fun xs => runSequence
    (fun env item rest => recognizeEnv Generated.pegGrammar env (fuel+3) item rest)
    _ [("ind",ind)] xs input) [[.bind (some "cs") (.plus (.ref "BlockCommand" ["ind"])),
      .opt (.choice [[.semanticPred true " not (or (take 1 (reverse cs))) ",.ref "GroupBody" ["ind"]]])]] = _
  have raw := CachedPayloadCoherence.erase (fuel+3) ind (fuel+3) input (Nat.le_refl _)
  have typed := CachedPayloadCoherence.captured (fuel+3) ind (fuel+3) input (Nat.le_refl _)
  cases collected : CommandCollectionTotal.captured ind (fuel+3) input with
  | error reason =>
    simp only [collected,BoolRepetitionTotal.eraseValues] at raw typed
    simp only [runChoices,foldChoice,List.foldlM,bind_pure,runSequence,←raw,group,collected,typed]
    rfl
  | ok value => cases value with
    | none =>
      simp only [collected,BoolRepetitionTotal.eraseValues] at raw typed
      simp only [runChoices,foldChoice,List.foldlM,bind_pure,runSequence,←raw,group,collected,typed]
      rfl
    | some pair =>
      rcases pair with ⟨rest,values⟩
      simp only [collected,BoolRepetitionTotal.eraseValues] at raw typed
      simp only [runChoices,foldChoice,List.foldlM,bind_pure,runSequence,←raw,group,collected,typed]
      have supported : BoolPayload.supported Generated.pegGrammar = true := by rfl
      have args : ["ind"].mapM (integer [("ind",ind)]) = some [ind] := by rfl
      simp only [supported,Bool.not_true,if_false,args]
      have payload : BoolPayload.value (CachedPayloadCoherence.cached Generated.pegGrammar (fuel+3)) ind (fuel+3) input =
          .ok (some (if values.reverse.head?.getD false then 1 else 0)) := by
        simp only [BoolPayload.value,typed]
      unfold CachedPayloadCoherence.cached at payload
      rw [payload]
      simp only [Id.run,bind,pure,Option.map,Except.map]
      simp only [Except.bind,Except.pure]
      rw [GroupOptionalTotal.generated]
      change _ = finish ind fuel rest values
      unfold LastBoolGuardTotal.last at *
      cases flag : values.reverse.head?.getD false <;>
        simp only [GroupOptionalTotal.optional,finish,LastBoolGuardTotal.last,flag,if_true,if_false]
      cases result : recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+1) (.ref "GroupBody" ["ind"]) rest with
      | error reason => rfl
      | ok value => cases value <;> rfl
#print axioms generated
end BlockGroupCompositionTotal

namespace BlockGroupCompositionTotal
open PegModel
-- These cover all fuels outside generated's offset domain, without a
-- successful-child assumption or an implicit minimum-fuel restriction.
theorem low_zero (ind : Nat) (input : List Char) :
  recognizeEnv Generated.pegGrammar [("ind",ind)] 0 (.ref "BlockGroup" ["ind"]) input = .error "fuel exhausted" := by rfl
theorem low_one (ind : Nat) (input : List Char) :
  recognizeEnv Generated.pegGrammar [("ind",ind)] 1 (.ref "BlockGroup" ["ind"]) input = .error "fuel exhausted" := by rfl
theorem low_two (ind : Nat) (input : List Char) :
  recognizeEnv Generated.pegGrammar [("ind",ind)] 2 (.ref "BlockGroup" ["ind"]) input = .error "fuel exhausted" := by rfl
theorem low_three (ind : Nat) (input : List Char) :
  recognizeEnv Generated.pegGrammar [("ind",ind)] 3 (.ref "BlockGroup" ["ind"]) input = .error "fuel exhausted" := by rfl
theorem low_four (ind : Nat) (input : List Char) :
  recognizeEnv Generated.pegGrammar [("ind",ind)] 4 (.ref "BlockGroup" ["ind"]) input = .error "fuel exhausted" := by rfl
end BlockGroupCompositionTotal
