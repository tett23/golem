import CachedPayloadCoherence
import UnboundSequenceTotal
namespace GroupOptionalTotal
open PegModel

def optional (ind fuel : Nat) (flag : Bool) (input : List Char) : ParseResult :=
  if flag then .ok (some input)
  else match recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+1) (.ref "GroupBody" ["ind"]) input with
    | .error reason => Except.error reason
    | .ok none => Except.ok (some input)
    | .ok (some next) => Except.ok (some next)

theorem generated (ind fuel : Nat) (flag : Bool) (input : List Char) :
  recognizeEnv Generated.pegGrammar [("cs",if flag then 1 else 0),("ind",ind)] (fuel+3)
    (.opt (.choice [[.semanticPred true " not (or (take 1 (reverse cs))) ",.ref "GroupBody" ["ind"]]])) input = optional ind fuel flag input := by
  let env : Params := [("cs",if flag then 1 else 0),("ind",ind)]
  have body : ∀ rest, recognizeEnv Generated.pegGrammar env (fuel+1) (.ref "GroupBody" ["ind"]) rest =
      recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+1) (.ref "GroupBody" ["ind"]) rest := by
    intro rest
    rfl
  have pred : ∀ rest, recognizeEnv Generated.pegGrammar env (fuel+1)
      (.semanticPred true " not (or (take 1 (reverse cs))) ") rest =
      .ok (if flag then none else some rest) := by
    intro rest
    cases flag <;> rfl
  have choice : recognizeEnv Generated.pegGrammar env (fuel+2)
      (.choice [[.semanticPred true " not (or (take 1 (reverse cs))) ",.ref "GroupBody" ["ind"]]]) input =
      (if flag then .ok none else recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+1) (.ref "GroupBody" ["ind"]) input) := by
    change runChoices (fun xs => runSequence
      (fun scope item rest => recognizeEnv Generated.pegGrammar scope (fuel+1) item rest)
      _ env xs input) [[.semanticPred true " not (or (take 1 (reverse cs))) ",.ref "GroupBody" ["ind"]]] = _
    simp only [runChoices,foldChoice,List.foldlM,bind_pure]
    rw [UnboundSequenceTotal.sequence _ _ _ _ _ (by simp)]
    simp only [UnboundSequenceTotal.follow,pred,body]
    cases flag <;> simp only [if_false,if_true]
    cases result : recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+1) (.ref "GroupBody" ["ind"]) input with
    | error reason => rfl
    | ok value => cases value <;> rfl
  change (match recognizeEnv Generated.pegGrammar env (fuel+2)
      (.choice [[.semanticPred true " not (or (take 1 (reverse cs))) ",.ref "GroupBody" ["ind"]]]) input with
    | .error reason => Except.error reason
    | .ok none => Except.ok (some input)
    | .ok hit => Except.ok hit) = _
  rw [choice]
  cases flag <;> simp only [optional,if_true,if_false]
  cases result : recognizeEnv Generated.pegGrammar [("ind",ind)] (fuel+1) (.ref "GroupBody" ["ind"]) input with
  | error reason => rfl
  | ok value => cases value <;> rfl
#print axioms generated
end GroupOptionalTotal
