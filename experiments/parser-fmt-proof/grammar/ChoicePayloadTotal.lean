import PegModelTest
namespace ChoicePayloadTotal
open PegModel
private theorem folded {α β γ : Type} (read : α → Except String (Option β))
    (project : β → γ) (items : List α) (state : Option β) :
    ((items.foldlM (fun found item => match found with
      | some _ => pure found
      | none => read item) state : Except String (Option β)).map (Option.map project)) =
    (items.foldlM (fun found item => match found with
      | some _ => pure found
      | none => (read item).map (Option.map project)) (state.map project) : Except String (Option γ)) := by
  induction items generalizing state with
  | nil => rfl
  | cons item items ih =>
      cases state with
      | some value => exact ih (some value)
      | none =>
          simp only [List.foldlM]
          cases read item with
          | error reason => rfl
          | ok value => exact ih value

theorem choice_map {α β γ : Type} (read : α → Except String (Option β))
    (project : β → γ) (items : List α) :
    (foldChoice read items).map (Option.map project) =
      foldChoice (fun item => (read item).map (Option.map project)) items := by
  exact folded read project items none
#print axioms choice_map
end ChoicePayloadTotal
