/-
Root ADR 0352: the flows of the separators of root ADR 0398 next to
boxes, ruled blocks and book parts.

After the units are numbered, golem-typeset changes the flow three
times before the pagination (modules/golem-typeset/src/Golem/Typeset/Flow.hs:4156,
:4157 and :4203): `joinBoxes` (Flow.hs:3951) makes boxes one after the
other with only spaces and keep-with-next between them one box,
`ruledLinks` (Flow.hs:4655) lets a ruled block share the area of its
rule before with the rule after of the ruled block right before it, and
`markBookParts` (Flow.hs:4531) wraps the flows of each item of a list in
a book part.  This file models the three on the flows of Whole.lean, for
the flows `Separator.separatorFlows` makes.  `spaceAfterCode`
(Flow.hs:3581), between `joinBoxes` and `ruledLinks`, only adds a space
after a code block, and the definition terms and the tables that
`markBookParts` also wraps (its `special`) are not modelled: none is in
these flows.  Every definition is total.

The three changes move no line and no figure (`Nested.blockFlows_eq`),
so invariants 4 and 5 of root ADR 0352 hold of the flows paginate
receives by the theorems of Whole.lean (`I4_blocks_paginate_ends`,
`I5_blocks_text`, `I5_blocks_figures`).
-/
import Whole
import Separator

namespace WholePagination
namespace SeparatorBlocks

/-! ## joinBoxes -/

/-- `passable` of `joinBoxes`: a space or a keep-with-next may go into a
    box. -/
def passable : Flow → Bool
  | .space _ | .keepNext _ _ => true
  | _ => false

/-- `keyOf` of `joinBoxes`: the settings of the box of a boxed flow, by
    its id (`key`), and none for any other flow. -/
def keyOf (key : Nat → Option Nat) : Flow → Option Nat
  | .boxed i _ _ _ => key i
  | _ => none

/-- `bodyOf` of `joinBoxes`. -/
def bodyOf : Flow → List Flow
  | .boxed _ _ _ b => b
  | f => [f]

/-- `joined` of `joinBoxes`: a run of boxes is the first box with the
    bodies of the run, the flows between them in it. -/
def joined : List Flow → List Flow
  | fs@(.boxed i kb ka _ :: _) => [.boxed i kb ka (fs.bind bodyOf)]
  | fs => fs

/-- `groupBoxes` (Box.hs:40) and `joined`, as a pass from the left: the
    run being collected (its key, the flows of the run and the passable
    flows after them), which the next flow of the same key goes on and
    any other flow but a passable one ends; the passable flows after the
    run then stay out of it. -/
def joinGo (key : Nat → Option Nat) : Option (Nat × List Flow × List Flow) → List Flow → List Flow
  | none, [] => []
  | some (_, acc, mid), [] => joined acc ++ mid
  | none, f :: rest =>
    match keyOf key f with
    | some k => joinGo key (some (k, [f], [])) rest
    | none => f :: joinGo key none rest
  | some (k, acc, mid), f :: rest =>
    if keyOf key f == some k then joinGo key (some (k, acc ++ mid ++ [f], [])) rest
    else if passable f && (keyOf key f).isNone then joinGo key (some (k, acc, mid ++ [f])) rest
    else
      joined acc ++ mid ++
        match keyOf key f with
        | some k' => joinGo key (some (k', [f], [])) rest
        | none => f :: joinGo key none rest

/-- `joinBoxes` (Flow.hs:3951), on the flows. -/
def joinBoxes (key : Nat → Option Nat) (flows : List Flow) : List Flow := joinGo key none flows

/-! ## ruledLinks -/

/-- `go` of `ruledLinks` (Flow.hs:4655): a ruled block with a rule
    before, right after a ruled block with a rule after, shares its area.
    The overhang of the line after a block (`frNextOverhang`) is not in
    the flows of Whole.lean. -/
def ruledGo : Option Flow → List Flow → List Flow
  | _, [] => []
  | prev, .ruled i b a _ body :: rest =>
    let j := match prev with
      | some (.ruled _ _ true _ _) => b
      | _ => false
    .ruled i b a j body :: ruledGo (some (.ruled i b a j body)) rest
  | _, f :: rest => f :: ruledGo (some f) rest

def ruledLinks (flows : List Flow) : List Flow := ruledGo none flows

/-! ## markBookParts -/

/-- `owner` of `itemOwners` (Flow.hs:4517): the unit of the greatest
    first line not after the first id of the flow; the units are given
    as their first line and their outermost item of a list, if any. -/
def ownerOf (owners : List (Nat × Option Nat)) (f : Flow) : Option (Option Nat) :=
  match flowSlotIds f with
  | [] => none
  | i :: _ => (owners.filter (fun o => o.1 ≤ i)).foldl (fun found o =>
      match found with
      | some (j, _) => if j ≤ o.1 then some o else found
      | none => some o) none |>.map (·.2)

/-- The owner of the nearest flow after each flow (`future` of
    `itemOwners`). -/
def nexts : List (Option (Option Nat)) → List (Option (Option Nat))
  | [] => []
  | _ :: rest => (rest.find? Option.isSome).getD none :: nexts rest

/-- `fill` of `itemOwners`: a flow of no owner between two flows of the
    same outermost item of a list belongs to that item. -/
def fillGo : Option (Option Nat) → List (Option (Option Nat) × Option (Option Nat)) → List (Option (Option Nat))
  | _, [] => []
  | previous, (u, next) :: rest =>
    let inherited := match previous, next with
      | some (some a), some (some b) => if a == b then previous else none
      | _, _ => none
    (u <|> inherited) :: fillGo (u <|> previous) rest

/-- `itemOwners` (Flow.hs:4513), as the key of the outermost item of each
    flow (`key 0`). -/
def itemKeys (owners : List (Nat × Option Nat)) (flows : List Flow) : List (Option Nat) :=
  let raw := flows.map (ownerOf owners)
  (fillGo none (raw.zip (nexts raw))).map (fun o => o.bind id)

mutual
/-- `special` of `markBookParts`, for boxes only. -/
def special : List Flow → List Flow
  | [] => []
  | .boxed i b a body :: rest => .boxed i b a (special body) :: special rest
  | f :: rest => f :: special rest
end

/-- `wrapLists 0` of `markBookParts`, the items one level deep: a run of
    flows of one item is a book part of `unit` of the ids of its flows. -/
def wrapGo (unit : KeepParts) : Option (Nat × List Flow) → List (Option Nat × Flow) → List Flow
  | none, [] => []
  | some (_, acc), [] => [part unit acc]
  | none, (k, f) :: rest =>
    match k with
    | some k => wrapGo unit (some (k, [f])) rest
    | none => f :: wrapGo unit none rest
  | some (k, acc), (k', f) :: rest =>
    if k' == some k then wrapGo unit (some (k, acc ++ [f])) rest
    else part unit acc ::
      match k' with
      | some k' => wrapGo unit (some (k', [f])) rest
      | none => f :: wrapGo unit none rest
where
  part (unit : KeepParts) (inside : List Flow) : Flow :=
    let body := special inside
    .bookPart unit 0 (flowsSlotIds body) body

/-- `markBookParts` (Flow.hs:4531) on items of a list one level deep. -/
def markBookParts (unit : KeepParts) (owners : List (Nat × Option Nat)) (flows : List Flow) : List Flow :=
  special (wrapGo unit none ((itemKeys owners flows).zip flows))

/-- The flows `paginateBuilt` receives (`bRetainedFlow`, Flow.hs:4203):
    the flows of the units after `spaceSeparators` and
    `holdSeparatorNeeds`, then `joinBoxes`, `ruledLinks` and
    `markBookParts`. -/
def blockFlows (key : Nat → Option Nat) (unit : KeepParts) (owners : List (Nat × Option Nat))
    (capacity : Nat) (us : List Separator.Unit) : List Flow :=
  markBookParts unit owners (ruledLinks (joinBoxes key (Separator.separatorFlows capacity us)))

/-! ## The three changes keep the lines and the figures -/

/-- What adds up over the flows and reads a box and a book part by their
    flows and a ruled block whatever area it shares. -/
structure Nested {α : Type} (T : List Flow → List α) extends Separator.Additive T : Prop where
  boxed : ∀ i kb ka body, T [.boxed i kb ka body] = T body
  bookPart : ∀ u k ids body, T [.bookPart u k ids body] = T body
  ruled : ∀ i b a j j' body, T [.ruled i b a j body] = T [.ruled i b a j' body]

theorem Nested.bodies {α : Type} {T : List Flow → List α} (h : Nested T) (fs : List Flow) :
    T (fs.bind bodyOf) = T fs := by
  induction fs with
  | nil => rfl
  | cons f r ih =>
    rw [List.cons_bind, h.append, ih, h.cons f r]
    cases f <;> simp only [bodyOf]
    rw [h.boxed]

theorem Nested.joined {α : Type} {T : List Flow → List α} (h : Nested T) (fs : List Flow) :
    T (joined fs) = T fs := by
  unfold joined
  split
  · rename_i i kb ka _ _
    rw [h.boxed, h.bodies]
  · rfl

/-- What `joinGo` gives: the run collected, then the flows after it. -/
def runOf {α : Type} (T : List Flow → List α) : Option (Nat × List Flow × List Flow) → List α
  | none => []
  | some (_, acc, mid) => T acc ++ T mid

theorem Nested.joinGo_eq {α : Type} {T : List Flow → List α} (h : Nested T) (key : Nat → Option Nat)
    (run : Option (Nat × List Flow × List Flow)) (fs : List Flow) :
    T (joinGo key run fs) = runOf T run ++ T fs := by
  induction fs generalizing run with
  | nil =>
    cases run with
    | none => simp only [joinGo, runOf, h.nil, List.append_nil]
    | some r =>
      obtain ⟨k, acc, mid⟩ := r
      simp only [joinGo, runOf, h.nil, List.append_nil]; rw [h.append, h.joined]
  | cons f rest ih =>
    cases run with
    | none =>
      simp only [joinGo]
      split
      · rw [ih]; simp only [runOf, h.nil, List.nil_append, List.append_nil]; rw [h.cons f rest]
      · rw [h.cons, ih]; simp only [runOf, List.nil_append]; rw [h.cons f rest]
    | some r =>
      obtain ⟨k, acc, mid⟩ := r
      simp only [joinGo]
      split
      · rw [ih]; simp only [runOf, h.nil, List.append_nil]
        rw [h.append, h.append, h.cons f rest]; simp only [List.append_assoc]
      · split
        · rw [ih]; simp only [runOf, h.nil, List.append_nil]
          rw [h.append, h.cons f rest]; simp only [List.append_assoc]
        · rw [h.append, h.append, h.joined]
          split
          · rw [ih]; simp only [runOf, h.nil, List.append_nil]
            rw [h.cons f rest]
          · rw [h.cons, ih]; simp only [runOf, List.nil_append]
            rw [h.cons f rest]

theorem Nested.ruledGo_eq {α : Type} {T : List Flow → List α} (h : Nested T) (prev : Option Flow) (fs : List Flow) :
    T (ruledGo prev fs) = T fs := by
  induction fs generalizing prev with
  | nil => rfl
  | cons f rest ih =>
    cases f with
    | ruled i b a j body =>
      simp only [ruledGo]
      rw [h.cons, ih, h.cons (.ruled i b a j body) rest, h.ruled]
    | _ => simp only [ruledGo]; rw [h.cons, ih, ← h.cons]

theorem Nested.special_eq {α : Type} {T : List Flow → List α} (h : Nested T) (fs : List Flow) :
    T (special fs) = T fs := by
  match fs with
  | [] => simp only [special]
  | f :: rest =>
    have e2 := h.special_eq rest
    cases f with
    | boxed i b a body =>
      have e1 := h.special_eq body
      simp only [special]
      rw [h.cons, h.boxed, e1, e2, h.cons (.boxed i b a body) rest, h.boxed]
    | _ => simp only [special]; rw [h.cons, e2, ← h.cons]
termination_by sizeOf fs
decreasing_by all_goals simp_wf <;> omega

/-- What `wrapGo` gives: the flows of the item collected, then the rest. -/
def itemOf {α : Type} (T : List Flow → List α) : Option (Nat × List Flow) → List α
  | none => []
  | some (_, acc) => T acc

theorem Nested.part_eq {α : Type} {T : List Flow → List α} (h : Nested T) (unit : KeepParts) (inside : List Flow) :
    T [wrapGo.part unit inside] = T inside := by
  simp only [wrapGo.part]; rw [h.bookPart, h.special_eq]

theorem Nested.wrapGo_eq {α : Type} {T : List Flow → List α} (h : Nested T) (unit : KeepParts)
    (item : Option (Nat × List Flow)) (ps : List (Option Nat × Flow)) :
    T (wrapGo unit item ps) = itemOf T item ++ T (ps.map (·.2)) := by
  induction ps generalizing item with
  | nil =>
    cases item with
    | none => simp only [wrapGo, itemOf, List.map, h.nil, List.append_nil]
    | some r => obtain ⟨k, acc⟩ := r; simp only [wrapGo, itemOf, List.map, h.nil, List.append_nil]; rw [h.part_eq]
  | cons q rest ih =>
    obtain ⟨k', f⟩ := q
    have hf := h.cons f (List.map (fun x => x.snd) rest)
    cases item with
    | none =>
      cases k' with
      | some k =>
        simp only [wrapGo]; rw [ih]; simp only [itemOf, List.map, hf, List.nil_append]
      | none =>
        simp only [wrapGo]; rw [h.cons, ih]; simp only [itemOf, List.map, List.nil_append, hf]
    | some r =>
      obtain ⟨k, acc⟩ := r
      simp only [wrapGo]
      split
      · rw [ih]; simp only [itemOf, List.map]; rw [h.append, hf]; simp only [List.append_assoc]
      · rw [h.cons, h.part_eq]
        cases k' with
        | some k2 =>
          simp only []; rw [ih]; simp only [itemOf, List.map, hf]
        | none =>
          simp only []; rw [h.cons, ih]; simp only [itemOf, List.map, List.nil_append, hf]

theorem length_nexts (raw : List (Option (Option Nat))) : (nexts raw).length = raw.length := by
  induction raw with
  | nil => rfl
  | cons _ r ih => simp [nexts, ih]

theorem length_fillGo (prev : Option (Option Nat)) (ps : List (Option (Option Nat) × Option (Option Nat))) :
    (fillGo prev ps).length = ps.length := by
  induction ps generalizing prev with
  | nil => rfl
  | cons q r ih => obtain ⟨u, n⟩ := q; simp [fillGo, ih]

theorem length_zip_eq {α β : Type} (a : List α) (b : List β) (h : a.length = b.length) : (a.zip b).length = a.length := by
  induction a generalizing b with
  | nil => rfl
  | cons x xs ih => cases b with
    | nil => simp at h
    | cons y ys => simp only [List.zip_cons_cons, List.length_cons]; rw [ih ys (by simp at h; exact h)]

theorem length_itemKeys (owners : List (Nat × Option Nat)) (flows : List Flow) :
    (itemKeys owners flows).length = flows.length := by
  simp only [itemKeys, List.length_map, length_fillGo]
  rw [length_zip_eq _ _ (by rw [length_nexts]), List.length_map]

theorem map_snd_zip' {α β : Type} (a : List α) (b : List β) (h : a.length = b.length) : (a.zip b).map (·.2) = b := by
  induction a generalizing b with
  | nil => cases b with
    | nil => rfl
    | cons _ _ => simp at h
  | cons x xs ih => cases b with
    | nil => simp at h
    | cons y ys => simp only [List.zip_cons_cons, List.map_cons]; rw [ih ys (by simp at h; exact h)]

/-- The three changes golem-typeset makes after the separators keep what
    the flows carry. -/
theorem Nested.blockFlows_eq {α : Type} {T : List Flow → List α} (h : Nested T) (key : Nat → Option Nat)
    (unit : KeepParts) (owners : List (Nat × Option Nat)) (capacity : Nat) (us : List Separator.Unit) :
    T (blockFlows key unit owners capacity us) = T (Separator.allFlows us) := by
  rw [blockFlows, markBookParts, h.special_eq, h.wrapGo_eq]
  simp only [itemOf, List.nil_append]
  rw [map_snd_zip' _ _ (length_itemKeys _ _), ruledLinks, h.ruledGo_eq, joinBoxes, h.joinGo_eq]
  simp only [runOf, List.nil_append]
  exact h.separatorFlows_eq capacity us

theorem sourceText_nested : Nested sourceText :=
  { toAdditive := Separator.sourceText_additive
    boxed := fun i kb ka body => by simp [sourceText, flowText]
    bookPart := fun u k ids body => by simp [sourceText, flowText]
    ruled := fun i b a j j' body => by cases body <;> simp [sourceText, flowText] }

theorem sourceFigs_nested : Nested sourceFigs :=
  { toAdditive := Separator.sourceFigs_additive
    boxed := fun i kb ka body => by simp [sourceFigs, flowFigs]
    bookPart := fun u k ids body => by simp [sourceFigs, flowFigs]
    ruled := fun i b a j j' body => by simp [sourceFigs, flowFigs] }

/-! ## Invariants 4 and 5 on the flows paginate receives -/

/-- Root ADR 0352 invariant 4 on the flows after `joinBoxes`,
    `ruledLinks` and `markBookParts`, by `I4_paginate_ends`. -/
theorem I4_blocks_paginate_ends (env : Env) (key : Nat → Option Nat) (unit : KeepParts)
    (owners : List (Nat × Option Nat)) (us : List Separator.Unit) :
    ∃ st, paginate env (blockFlows key unit owners env.capacity.toNat us) = st :=
  I4_paginate_ends env _

/-- Root ADR 0352 invariant 5 for the lines on the flows after the three
    changes: the pages hold the lines of the units once each, in the order
    written, by `I5_paginate_text`; joining boxes, sharing the area of
    rules and wrapping items in book parts move no line. -/
theorem I5_blocks_text (env : Env) (key : Nat → Option Nat) (unit : KeepParts)
    (owners : List (Nat × Option Nat)) (us : List Separator.Unit) :
    pagesText (paginate env (blockFlows key unit owners env.capacity.toNat us)).done = Separator.unitsText us := by
  rw [I5_paginate_text, sourceText_nested.blockFlows_eq]; rfl

/-- Root ADR 0352 invariant 5 for the figures on the flows after the three
    changes, by `I5_paginate_figures`: its hypotheses are on the flows
    paginate receives, and those flows carry the figures of the units in
    the order written. -/
theorem I5_blocks_figures (env : Env) (hc : 1 ≤ env.capacity) (hs : 0 ≤ env.separator) (key : Nat → Option Nat)
    (unit : KeepParts) (owners : List (Nat × Option Nat)) (us : List Separator.Unit)
    (hf : ∀ f ∈ blockFlows key unit owners env.capacity.toNat us, figureOk f)
    (hb : BoxesOk (blockFlows key unit owners env.capacity.toNat us)) :
    pagesFigs (paginate env (blockFlows key unit owners env.capacity.toNat us)).done =
      sourceFigs (Separator.otherFlows us) := by
  rw [I5_paginate_figures env hc hs _ hf hb, sourceFigs_nested.blockFlows_eq,
    Separator.sourceFigs_ins (Separator.allFlows_ins us)]

end SeparatorBlocks
end WholePagination
