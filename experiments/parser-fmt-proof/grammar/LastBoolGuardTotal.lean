import PegModelTest
namespace LastBoolGuardTotal

def last (items : List Bool) : Bool := items.reverse.head?.getD false
def guard (items : List Bool) : Bool := !(items.reverse.take 1).foldr Bool.or false

theorem guard_last (items : List Bool) : guard items = !last items := by
  unfold guard last
  cases reversed : items.reverse with
  | nil => rfl
  | cons head tail => cases head <;> rfl

def encode (value : Bool) : Nat := if value then 1 else 0
def decodeGuard (value : Nat) : Option Bool :=
  if value == 0 then some true else if value == 1 then some false else none

theorem projected_guard (items : List Bool) :
    decodeGuard (encode (last items)) = some (guard items) := by
  rw [guard_last]
  cases last items <;> rfl
#print axioms guard_last
#print axioms projected_guard
end LastBoolGuardTotal
