import StructuralCoherence
import CorePayloadCoherence
namespace CachedPayloadCoherence
open PegModel

def cached (grammar : Grammar) (cap : Nat) : BoolPayload.Read :=
  fun bindings n item rest => FuelTable.get (cap+1)
    (PProd.mk (FuelTable.pack (interpreterStep grammar) cap) PUnit.unit)
    (min n cap) (Nat.lt_succ_of_le (Nat.min_le_right _ _)) bindings item rest

theorem cached_clip (grammar : Grammar) (cap : Nat) :
    cached grammar cap = GenericBoolPayloadTotal.clip
      (fun env n item rest => recognizeEnv grammar env n item rest) cap := by
  funext bindings n item rest
  exact stored_recognizer grammar (cap+1) (min n cap)
    (Nat.lt_succ_of_le (Nat.min_le_right _ _)) bindings item rest

theorem captured (cap ind fuel : Nat) (input : List Char) (bound : fuel ≤ cap) :
    BoolPayload.captured (cached Generated.pegGrammar cap) ind fuel input =
      CommandCollectionTotal.captured ind fuel input := by
  rw [CorePayloadCoherence.captured,cached_clip,
      GenericBoolPayloadTotal.captured_clip _ cap ind fuel input bound,
      GenericBoolPayloadTotal.actual]

theorem erase (cap ind fuel : Nat) (input : List Char) (bound : fuel ≤ cap) :
    BoolRepetitionTotal.eraseValues
      (BoolPayload.captured (cached Generated.pegGrammar cap) ind fuel input) =
      recognizeEnv Generated.pegGrammar [("ind",ind)] fuel
        (.bind (some "cs") (.plus (.ref "BlockCommand" ["ind"]))) input := by
  rw [captured cap ind fuel input bound]
  exact CommandCollectionTotal.erase_captured ind fuel input

#print axioms captured
#print axioms erase
end CachedPayloadCoherence
