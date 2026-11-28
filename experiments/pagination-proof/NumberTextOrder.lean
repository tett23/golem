import Physical
namespace NumberTextOrder
open PhysicalPagination
set_option autoImplicit false

/-- Wrapping the newly numbered unit as in `numberText.boxed`. -/
def wrap (box : Option (Nat × Int × Int)) (flows : List Flow) : List Flow :=
  match box with
  | none => flows
  | some (ident, before, after) => [.boxed ident before after flows]

private theorem body_append (left right : List Flow) :
    bodyLines (left ++ right) = bodyLines left ++ bodyLines right := by
  induction left with
  | nil => rfl
  | cons f fs ih => simp only [List.cons_append, bodyLines, ih, List.append_assoc]

private theorem body_wrap (box : Option (Nat × Int × Int)) (flows : List Flow) :
    bodyLines (wrap box flows) = bodyLines flows := by
  cases box with
  | none => rfl
  | some args => cases args with | mk ident rest => cases rest; simp [wrap, bodyLines, flowLines]

private theorem join_append (left right : List (List Line)) :
    (left ++ right).join = left.join ++ right.join := by
  induction left with
  | nil => rfl
  | cons rows rest ih => simp [List.join, ih, List.append_assoc]

/-- The seven source alternatives of `numberText.flowOf`, after style selection. -/
inductive TextForm where
  | paragraph (keep : Keep)
  | heading (recto : Bool) (extent : Int)
  | notesTitle (extent : Int)
  | term
  | ruledHeading (template : Ruled) (recto : Bool) (extent : Int)
  | ruledParagraph (template : Ruled) (keep : Keep)
  | ruledToc (template : Ruled) (keep : Keep)

def ordinary (form : TextForm) (rows : List Line) : List Flow :=
  match form with
  | .paragraph keep => [.paragraph keep rows]
  | .heading recto extent => [.heading recto extent rows]
  | .notesTitle extent => [.heading false extent rows]
  | .term => [.defTerm rows]
  | .ruledHeading template recto extent =>
      [.ruled {template with lines := rows, heading := some (recto, extent)}]
  | .ruledParagraph template keep | .ruledToc template keep =>
      [.ruled {template with lines := rows, keep := keep, heading := none}]

/-- Every ordinary constructor appends precisely the newly numbered rows. -/
theorem root_adr0352_i5_ordinary (prior : List Flow) (form : TextForm)
    (box : Option (Nat × Int × Int)) (rows : List Line) :
    bodyLines (prior ++ wrap box (ordinary form rows)) = bodyLines prior ++ rows := by
  rw [body_append, body_wrap]
  cases form <;> simp [ordinary, bodyLines, flowLines]

/-- The unboxed existing-stanza branch, before its trailing keep marker. -/
theorem root_adr0352_i5_append_stanza (prior : List Flow) (k : Keep)
    (verses : List (List Line)) (rows : List Line) :
    bodyLines (prior ++ [.stanza k (verses ++ [rows])]) =
      bodyLines (prior ++ [.stanza k verses]) ++ rows := by
  simp [body_append, bodyLines, flowLines, join_append, List.append_assoc]

/-- The existing single-stanza box branch preserves all earlier rows. -/
theorem root_adr0352_i5_append_boxed_stanza (prior : List Flow) (k : Keep)
    (ident : Nat) (before after : Int) (verses : List (List Line)) (rows : List Line) :
    bodyLines (prior ++ [.boxed ident before after [.stanza k (verses ++ [rows])]]) =
      bodyLines (prior ++ [.boxed ident before after [.stanza k verses]]) ++ rows := by
  simp [body_append, bodyLines, flowLines, join_append, List.append_assoc]

/-- A new stanza, boxed or unboxed, appends the numbered rows in order. -/
theorem root_adr0352_i5_new_stanza (prior : List Flow) (k : Keep)
    (box : Option (Nat × Int × Int)) (rows : List Line) :
    bodyLines (prior ++ wrap box [.stanza k [rows]]) = bodyLines prior ++ rows := by
  rw [body_append, body_wrap]
  simp [bodyLines, flowLines]

/-- Paragraph-start and keep-next controls contain no line boxes. -/
theorem root_adr0352_i5_start_keep_transparent (body : List Flow)
    (start : Option BreakKind) (keep : Option (Nat × Nat)) :
    bodyLines ((start.toList.map Flow.start) ++ body ++
      (keep.toList.map fun (n, span) => Flow.keepNext n span)) = bodyLines body := by
  cases start <;> cases keep <;> simp [body_append, bodyLines, flowLines]

end NumberTextOrder
