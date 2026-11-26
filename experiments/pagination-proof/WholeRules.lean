/-
Root ADR 0352 invariant 3 for the rules of ruled blocks in the grid mode.

The rules `placeRuled` of Whole.lean places (`sRules` of State.hs) and
the lines of their blocks are put in one column, and each rule placed with
its block lies in the column: its area starts at or after the lines used
before the block and ends before the footnote lines at the end of the
column.  A rule after that waits for the rule before of the next block
(`sJoin`) is placed in the column of the block before when the next block
takes the area with it.  The rule after that `flushJoin` places when the
next block does not share its area lies in the column only when its area
fits the room left; `settleRuled` lets a rule after wait only when the
flows ahead settle it: the next block shares the area in this column, or
the area of its own fits the room (`I3_waiting_rule_in_column`).
-/
import Whole

namespace WholePagination
namespace Rules

/-! ## The lines and the rules of a block -/

theorem mem_app {α : Type} {x : α} : ∀ {a b : List α}, x ∈ a ++ b → x ∈ a ∨ x ∈ b
  | [], _, h => Or.inr h
  | _ :: _, _, h => by
    cases h with
    | head => exact Or.inl (.head _)
    | tail _ h => exact (mem_app h).elim (fun h => Or.inl (.tail _ h)) Or.inr

theorem mem_one {α : Type} {x y : α} (h : x ∈ [y]) : x = y := by
  cases h with
  | head => rfl
  | tail _ h => cases h

theorem mem_two {α : Type} {x y z : α} (h : x ∈ [y, z]) : x = y ∨ x = z := by
  cases h with
  | head => exact Or.inl rfl
  | tail _ h => exact Or.inr (mem_one h)

/-- The slots of lines placed one after another from grid line `u`. -/
def lineSlots (u : Int) : List Line → List (Int × Slot)
  | [] => []
  | l :: ls => (u, .line l.id) :: lineSlots (u + 1) ls

/-- The slots of the lines of a block placed from grid line `u`. -/
def bodySlots (u : Int) : RuledBody → List (Int × Slot)
  | .lines _ ls => lineSlots u ls
  | .heading _ _ [] => []
  | .heading _ _ (l :: ls) => [(u, .heading l.id (ls.length + 1))]

/-- `r` is in the column of `st`: the same page, the same column, and the
    pages closed before it are those of `st`. -/
def SameColumn (st r : St) : Prop := r.page = st.page ∧ r.column = st.column ∧ r.done = st.done

theorem putLineKeeping_keeps (env : Env) (k : Int) (st : St) (l : Line) :
    SameColumn st (putLineKeeping env k st l) ∧ (putLineKeeping env k st l).rules = st.rules
    ∧ (putLineKeeping env k st l).slots = st.slots ++ [(st.used, .line l.id)]
    ∧ (putLineKeeping env k st l).used = st.used + 1 :=
  ⟨⟨rfl, rfl, rfl⟩, rfl, rfl, rfl⟩

theorem putRuledLines_keeps (env : Env) (k2 : Nat) (ls : List Line) (st : St) :
    SameColumn st (putRuledLines env k2 st ls) ∧ (putRuledLines env k2 st ls).rules = st.rules
    ∧ (putRuledLines env k2 st ls).slots = st.slots ++ lineSlots st.used ls
    ∧ (putRuledLines env k2 st ls).used = st.used + ls.length := by
  induction ls generalizing st with
  | nil => exact ⟨⟨rfl, rfl, rfl⟩, rfl, by simp [putRuledLines, lineSlots], by simp [putRuledLines]⟩
  | cons l ls ih =>
    obtain ⟨⟨p1, c1, d1⟩, r1, s1, u1⟩ := putLineKeeping_keeps env (ls.length + k2) st l
    obtain ⟨⟨p2, c2, d2⟩, r2, s2, u2⟩ := ih (putLineKeeping env (ls.length + k2) st l)
    simp only [putRuledLines]
    refine ⟨⟨p2.trans p1, c2.trans c1, d2.trans d1⟩, r2.trans r1, ?_, ?_⟩
    · rw [s2, s1, u1]; simp [lineSlots]
    · rw [u2, u1]; simp; omega

theorem putBlock_keeps (env : Env) (st : St) (n : Nat) (ls : List Line) :
    SameColumn st (putBlock env st n ls) ∧ (putBlock env st n ls).rules = st.rules
    ∧ (putBlock env st n ls).slots = st.slots ++ bodySlots st.used (.heading false n ls) := by
  cases ls with
  | nil => exact ⟨⟨rfl, rfl, rfl⟩, rfl, by simp [putBlock, bodySlots]⟩
  | cons l ls => exact ⟨⟨rfl, rfl, rfl⟩, rfl, by simp [putBlock, bodySlots]⟩

theorem bodySlots_heading (u : Int) (r : Bool) (n : Nat) (ls : List Line) :
    bodySlots u (.heading r n ls) = bodySlots u (.heading false n ls) := by
  cases ls <;> rfl

/-- `commitRuled` places the block in the column it is called in: its rules
    before the block and after it are added to the rules of the column
    (`sRules st <> before`, then `<> after`), and its lines to the slots of
    the column, after the area of the rule before. -/
theorem I3_commitRuled_column (env : Env) (st : St) (body : RuledBody) (p : Plan) :
    SameColumn st (commitRuled env st body p)
    ∧ (commitRuled env st body p).rules = st.rules ++ p.beforeRules ++ p.afterRules
    ∧ (commitRuled env st body p).slots = st.slots ++ bodySlots (st.used + p.before) body := by
  cases body with
  | lines kp ls =>
    obtain ⟨⟨p1, c1, d1⟩, r1, s1, _⟩ :=
      putRuledLines_keeps env p.after ls { st with used := st.used + p.before, join := none }
    simp only [commitRuled]
    exact ⟨⟨p1, c1, d1⟩, by rw [r1], s1⟩
  | heading r n ls =>
    obtain ⟨⟨p1, c1, d1⟩, r1, s1⟩ := putBlock_keeps env { st with used := st.used + p.before, join := none } n ls
    simp only [commitRuled]
    refine ⟨⟨p1, c1, d1⟩, by rw [r1], ?_⟩
    rw [bodySlots_heading (st.used + p.before) r n ls]; exact s1

/-! ## The areas of the rules of a plan -/

/-- A rule lies in the column of `st` from the lines it has used: its area
    starts at or after them and ends before the footnote lines. -/
def InColumn (env : Env) (st : St) (r : PlacedRule) : Prop :=
  st.used ≤ r.first ∧ r.first + r.area ≤ cap env st - st.noteLines

/-- The rules before of `planOf` lie in the column when the area before
    fits; a rule shared with the rule after of the block before starts
    after the last line of that block, the line before the lines used. -/
theorem I3_planOf_before_in_column (env : Env) (st : St) (i : Nat) (before after : Bool) (body : RuledBody)
    (rest : List Flow) (joined : Option (Nat × Int))
    (fit : ((planOf env st i before after body rest joined).before : Int) ≤ free env st)
    (hj : ∀ a l, joined = some (a, l) → st.used = l + 1) :
    ∀ r ∈ (planOf env st i before after body rest joined).beforeRules, InColumn env st r := by
  intro r hr
  simp only [free] at fit
  cases joined with
  | some j =>
    obtain ⟨a, l⟩ := j
    have e := hj a l rfl
    simp only [planOf] at hr fit
    rcases mem_two hr with h | h <;> subst h <;> simp only [InColumn, PlacedRule.first] <;> omega
  | none =>
    cases before with
    | false => simp [planOf] at hr
    | true =>
      simp only [planOf, ↓reduceIte] at hr fit
      split at hr <;> (have hr := mem_one hr; subst hr; simp only [InColumn, PlacedRule.first]; omega)

theorem ite_not_start (c : Prop) [Decidable c] (x o : Bool) :
    (if c then RuleEdge.atEnd x else RuleEdge.inside) ≠ .start o := by
  split <;> intro h <;> cases h

theorem first_of_not_start (r : PlacedRule) (h : ∀ o, r.edge ≠ .start o) : r.first = r.line + 1 := by
  unfold PlacedRule.first
  split
  · rename_i o e; exact absurd e (h o)
  · rfl

/-- The rule after of `planOf` lies in the column when the block with
    both areas fits. -/
theorem I3_planOf_after_in_column (env : Env) (st : St) (i : Nat) (before after : Bool) (body : RuledBody)
    (rest : List Flow) (joined : Option (Nat × Int))
    (fit : ((planOf env st i before after body rest joined).before : Int) + body.size
      + (planOf env st i before after body rest joined).after ≤ free env st) :
    ∀ r ∈ (planOf env st i before after body rest joined).afterRules, InColumn env st r := by
  intro r hr
  simp only [free] at fit
  have hr' := hr
  simp only [planOf] at hr'
  split at hr'
  · rename_i hc
    have e := mem_one hr'
    have hl : r.line = st.used + ((planOf env st i before after body rest joined).before : Int) + body.size - 1 := by
      rw [e]; rfl
    have ha : r.area = (planOf env st i before after body rest joined).after := by rw [e]; simp only [planOf, hc, ↓reduceIte]
    have he : ∃ x, r.edge = if cap env st - st.noteLines
        ≤ st.used + ((planOf env st i before after body rest joined).before : Int) + body.size - 1 + 1
          + env.ruleAfter i then RuleEdge.atEnd x else RuleEdge.inside := ⟨_, by rw [e]; rfl⟩
    obtain ⟨x, he⟩ := he
    have hf : r.first = r.line + 1 := by
      unfold PlacedRule.first
      split
      · rename_i o h; rw [he] at h; split at h <;> cases h
      · rfl
    simp only [InColumn]
    rw [hf, ha]
    omega
  · simp at hr'

/-- `planNeed` counts the grid lines of both areas and of the block. -/
theorem planNeed_ge (env : Env) (hs : 0 ≤ env.separator) (st : St) (body : RuledBody) (p : Plan) :
    (p.before : Int) + body.size + p.after ≤ planNeed env st body p := by
  cases body <;> simp only [planNeed, needIn, planParts, RuledBody.size, noNeed] <;> split <;> push_cast <;> omega

theorem headingNeed_ge (env : Env) (hs : 0 ≤ env.separator) (st : St) (n : Nat) (ls : List Line) :
    (n : Int) ≤ headingNeed env st n ls := by
  simp only [headingNeed, needIn, noNeed]; split <;> push_cast <;> omega

theorem planOf_before_rest (env : Env) (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest rest' : List Flow) :
    (planOf env st i b a body rest none).before = (planOf env st i b a body rest' none).before := rfl

/-- The block of `commitRuled` is placed with rules that each lie in the
    column at the state it is placed from. -/
def Placed (env : Env) (body : RuledBody) (r : St) : Prop :=
  ∃ s p, r = commitRuled env s body p ∧ ∀ x ∈ p.beforeRules ++ p.afterRules, InColumn env s x

theorem placed_of_plan (env : Env) (hs : 0 ≤ env.separator) (s : St) (i : Nat) (b a : Bool) (body : RuledBody)
    (rest : List Flow) (joined : Option (Nat × Int))
    (fit : planNeed env s body (planOf env s i b a body rest joined) ≤ free env s)
    (hj : ∀ x l, joined = some (x, l) → s.used = l + 1) :
    Placed env body (commitRuled env s body (planOf env s i b a body rest joined)) := by
  have g := planNeed_ge env hs s body (planOf env s i b a body rest joined)
  refine ⟨s, _, rfl, fun x hx => ?_⟩
  rcases mem_app hx with h | h
  · exact I3_planOf_before_in_column env s i b a body rest joined (by omega) hj x h
  · exact I3_planOf_after_in_column env s i b a body rest joined (by omega) x h

/-- What `splitRuled` does: a heading placed with its rules that lie in
    the column, or placed without them (`putBlock`), or the lines of a
    paragraph broken as any paragraph's, without its rules (golem-driver
    ADR 0027). -/
def SplitPlaced (env : Env) (body : RuledBody) (r : St) : Prop :=
  Placed env body r ∨ (∃ s kp ls, body = .lines kp ls ∧ r = placeLines env kp s true ls)
    ∨ (∃ s recto n ls, body = .heading recto n ls ∧ r = putBlock env s n ls)

theorem splitRuled_placed (env : Env) (hs : 0 ≤ env.separator) (st0 : St) (i : Nat) (b a : Bool)
    (body : RuledBody) (rest : List Flow) :
    SplitPlaced env body (splitRuled env st0 i b a body rest) := by
  simp only [splitRuled]
  generalize (if isEmpty st0 = true then st0 else nextColumn env st0) = s
  cases body with
  | lines kp ls => exact Or.inr (Or.inl ⟨s, kp, ls, rfl, rfl⟩)
  | heading r n ls =>
    have hn := headingNeed_ge env hs s n ls
    have e := planOf_before_rest env s i b a (.heading r n ls) rest []
    simp only []
    split
    · rename_i fit
      refine Or.inl ⟨s, _, rfl, fun x hx => ?_⟩
      rcases mem_app hx with h | h
      · exact I3_planOf_before_in_column env s i b a (.heading r n ls) rest none (by omega) (fun _ _ h => nomatch h) x h
      · exact I3_planOf_after_in_column env s i b a (.heading r n ls) [] none
          (by simp only [RuledBody.size]; rw [← e]; omega) x h
    · split
      · rename_i _ fit
        refine Or.inl ⟨s, _, rfl, fun x hx => ?_⟩
        rcases mem_app hx with h | h
        · exact I3_planOf_before_in_column env s i b a (.heading r n ls) rest none (by omega) (fun _ _ h => nomatch h) x h
        · simp at h
      · exact Or.inr (Or.inr ⟨s, r, n, ls, rfl, rfl⟩)

/-- `settleRuled` places the block with rules that each lie in the column
    of the state it places them from: the plan that shares the rule after
    with the block ahead and the plan whose rule after takes its own area
    are each committed only when the block with its areas fits the room. -/
theorem I3_settleRuled_rules (env : Env) (hs : 0 ≤ env.separator) (st : St) (i : Nat) (b a : Bool)
    (body : RuledBody) (rest : List Flow) (joined : Option (Nat × Int)) (r : St)
    (h : settleRuled env st i b a body rest joined = some r)
    (hj : ∀ x l, joined = some (x, l) → st.used = l + 1) :
    Placed env body r := by
  obtain ⟨rest', _, fit, hr⟩ := settleRuled_spec env st i b a body rest joined r h
  rw [hr]
  exact placed_of_plan env hs st i b a body rest' joined fit hj

theorem fresh_tail (env : Env) (hs : 0 ≤ env.separator) (i : Nat) (b a : Bool) (body : RuledBody)
    (rest : List Flow) (s2 : St) :
    SplitPlaced env body
      (match settleRuled env s2 i b a body rest none with
        | some placed => placed
        | none =>
          if isEmpty s2 = true then splitRuled env s2 i b a body rest
          else
            match settleRuled env (nextColumn env s2) i b a body rest none with
            | some placed => placed
            | none => splitRuled env (nextColumn env s2) i b a body rest) := by
  apply settle_or (SplitPlaced env body)
  · intro rest' _ fit; exact Or.inl (placed_of_plan env hs _ i b a body rest' none fit (fun _ _ h => nomatch h))
  · split
    · exact splitRuled_placed env hs _ i b a body rest
    · apply settle_or (SplitPlaced env body)
      · intro rest' _ fit; exact Or.inl (placed_of_plan env hs _ i b a body rest' none fit (fun _ _ h => nomatch h))
      · exact splitRuled_placed env hs _ i b a body rest

/-- `placeRuled` with no rule waiting places the block with rules that lie
    in the column of the state it places them from, or splits it without
    its rules (golem-driver ADR 0027). -/
theorem I3_placeRuledFresh_rules (env : Env) (hs : 0 ≤ env.separator) (st : St) (i : Nat) (b a : Bool)
    (body : RuledBody) (rest : List Flow) :
    SplitPlaced env body (placeRuledFresh env st i b a body rest) := by
  unfold placeRuledFresh
  exact fresh_tail env hs i b a body rest _

/-- `placeRuled`: the block shares the area of the rule waiting, placed
    with both rules in the column of the state it is called in, or the rule
    waiting takes its own area (`flushJoin`) and the block is placed as
    `placeRuledFresh` places it.  Either way the block's rules lie in the
    column they are placed from, or it is split without them. -/
theorem I3_placeRuled_rules (env : Env) (hs : 0 ≤ env.separator) (st : St) (i : Nat) (b a j : Bool)
    (body : RuledBody) (rest : List Flow) (hu : ∀ x l, st.join = some (x, l) → st.used = l + 1) :
    SplitPlaced env body (placeRuled env st i b a j body rest) := by
  unfold placeRuled
  split
  · rename_i w hw
    apply joined_or (SplitPlaced env body)
    · intro rest' _ fit
      exact Or.inl (placed_of_plan env hs st i b a body rest' (some w) fit
        (fun x l e => hu x l (by rw [hw, e])))
    · unfold unjoined; split <;> exact I3_placeRuledFresh_rules env hs _ i b a body rest
  · exact I3_placeRuledFresh_rules env hs _ i b a body rest

/-- A block that shares the area of the rule after of the block before
    (`frJoined`) and settles in the column of the state it is called in,
    the column of the block before, is placed there with the rule after of
    that block and its own rule before in the area after the last line of
    that block. -/
theorem I3_placeRuled_joined (env : Env) (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow)
    (x : Nat) (l : Int) (hw : st.join = some (x, l)) (hb : b = true) (hr : body.recto = false) (r : St)
    (hset : settleRuled env st i b a body rest (some (x, l)) = some r) :
    placeRuled env st i b a true body rest = r
    ∧ ∃ rest', r = commitRuled env st body (planOf env st i b a body rest' (some (x, l)))
      ∧ (planOf env st i b a body rest' (some (x, l))).beforeRules
        = [⟨x, false, l, .joinedAfter i, (planOf env st i b a body rest' (some (x, l))).before⟩,
          ⟨i, true, l, .joinedBefore x, (planOf env st i b a body rest' (some (x, l))).before⟩] := by
  subst hb
  obtain ⟨rest', _, _, e⟩ := settleRuled_spec env st i true a body rest (some (x, l)) r hset
  refine ⟨?_, rest', e, rfl⟩
  unfold placeRuled
  rw [hw]
  simp only [settleJoined, hr, Bool.true_and, Bool.not_false, ↓reduceIte, hset]

/-- The rule after that `flushJoin` places when the next block does not
    share its area: it is put in the column of the block before, on the line
    after its last line, and lies in the column exactly when its area fits
    the room left.  When it does not, the lines used are not moved past the
    end of the column (`min k (free env st)` of Paginate.hs), and the rule is
    drawn after the end of the column (README.md). -/
theorem I3_flushJoin_rule (env : Env) (st : St) (x : Nat) (l : Int) (hw : st.join = some (x, l))
    (hu : st.used = l + 1) :
    ∃ r, (flushJoin env st).rules = st.rules ++ [r] ∧ r.id = x ∧ r.before = false ∧ r.line = l
      ∧ SameColumn st (flushJoin env st) ∧ (InColumn env st r ↔ (r.area : Int) ≤ free env st) := by
  unfold flushJoin
  rw [hw]
  refine ⟨_, rfl, rfl, rfl, rfl, ⟨rfl, rfl, rfl⟩, ?_⟩
  have hf : ∀ r : PlacedRule, r.line = l → (∀ o, r.edge ≠ .start o) → (InColumn env st r ↔ (r.area : Int) ≤ free env st) := by
    intro r e h
    simp only [InColumn, free, first_of_not_start r h, e]
    omega
  exact hf _ rfl (fun o => ite_not_start _ _ o)

/-! ## A new column has no rule waiting and no rules -/

theorem carryNote_rules (env : Env) (st : St) (p : NotePart) : (carryNote env st p).rules = st.rules := by
  simp only [carryNote, addUnmet]; split <;> rfl

theorem carryAll_rules (env : Env) (ps : List NotePart) (st : St) :
    (ps.foldl (carryNote env) st).rules = st.rules := by
  induction ps generalizing st with
  | nil => rfl
  | cons p ps ih => simp only [List.foldl]; rw [ih, carryNote_rules]

theorem pageFigures_rules (env : Env) (ts : List Nat) (st : St) :
    (ts.foldl (pageFigure env) st).rules = st.rules := by
  induction ts generalizing st with
  | nil => rfl
  | cons t _ ih => exact ih (pageFigure env st t)

theorem placeDeferred_rules_join (env : Env) (ws : List Deferred) (st : St) :
    (placeDeferred env st ws).rules = st.rules ∧ (placeDeferred env st ws).join = st.join := by
  induction ws generalizing st with
  | nil => exact ⟨rfl, rfl⟩
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · exact ⟨(ih _).1, (ih _).2⟩
      · exact ⟨rfl, rfl⟩
    | pageFigure i => exact ⟨rfl, rfl⟩

/-- Going on to the next column or page (`advance` of State.hs) leaves no
    rule waiting and starts the rules of the new column empty: a rule after
    waiting is placed only in the column of its block. -/
theorem I3_advance_clears (env : Env) (b : Bool) (st : St) :
    (advance env b st).join = none ∧ (advance env b st).rules = [] := by
  have o : ∀ s : St, (openBox s).join = s.join ∧ (openBox s).rules = s.rules := by
    intro s; unfold openBox; split <;> exact ⟨rfl, rfl⟩
  unfold advance advanceIn openColumn
  rw [(o _).1, (o _).2, (placeDeferred_rules_join ..).1, (placeDeferred_rules_join ..).2]
  simp only []
  rw [carryAll_rules, carryAll_join, pageFigures_rules, pageFigures_join]
  exact ⟨rfl, rfl⟩

/-- A set of columns started (`startSet` of State.hs) has no rule waiting
    and no rules. -/
theorem I3_startSet_clears (env : Env) (st : St) (columns : Nat) (first : Int) :
    (startSet env st columns first).join = none ∧ (startSet env st columns first).rules = [] := ⟨rfl, rfl⟩

/-! ## The rule after that waits -/

/-- A block whose rule after waits leaves the lines used at the line after
    its last line, which the waiting rule names. -/
theorem I3_commitRuled_waiting (env : Env) (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow)
    (x : Nat) (l : Int) (hb : body.lines' ≠ [])
    (h : (commitRuled env st body (planOf env st i b a body rest none)).join = some (x, l)) :
    x = i ∧ (commitRuled env st body (planOf env st i b a body rest none)).used = l + 1
    ∧ l = st.used + (planOf env st i b a body rest none).before + body.size - 1 := by
  have hj : (planOf env st i b a body rest none).waiting = some (x, l) := h
  have ha : (planOf env st i b a body rest none).after = 0 := by
    simp only [planOf] at hj ⊢
    split at hj
    · rename_i hn; simp [hn]
    · simp at hj
  simp only [planOf] at hj
  split at hj
  · simp only [Option.some.injEq, Prod.mk.injEq] at hj
    obtain ⟨hx, hl⟩ := hj
    refine ⟨hx.symm, ?_, by rw [← hl]; simp only [planOf]⟩
    have u2 : ∀ s2 : St, s2.used = st.used + (planOf env st i b a body rest none).before + body.size →
        min (s2.used + (planOf env st i b a body rest none).after) (max s2.used (cap env s2 - s2.noteLines))
          = l + 1 := by
      intro s2 hs2
      rw [ha, ← hl]
      have m := Int.le_max_left s2.used (cap env s2 - s2.noteLines)
      simp only [planOf] at hs2
      omega
    simp only [commitRuled]
    apply u2
    cases body with
    | lines kp ls =>
      have := (putRuledLines_keeps env (planOf env st i b a (.lines kp ls) rest none).after ls
        { st with used := st.used + (planOf env st i b a (.lines kp ls) rest none).before, join := none }).2.2.2
      simp only [RuledBody.size]; rw [this]
    | heading r n ls =>
      cases ls with
      | nil => exact absurd rfl hb
      | cons l0 ls => simp [putBlock, RuledBody.size]
  · simp at hj

theorem lineSlots_last (u : Int) (ls : List Line) (h : ls ≠ []) :
    ∃ id v, v = u + ls.length - 1 ∧ (v, Slot.line id) ∈ lineSlots u ls := by
  induction ls generalizing u with
  | nil => exact absurd rfl h
  | cons l ls ih =>
    cases ls with
    | nil => exact ⟨l.id, u, by simp, .head _⟩
    | cons l' ls' =>
      obtain ⟨id, v, e, m⟩ := ih (u + 1) (by intro h; cases h)
      exact ⟨id, v, by rw [e]; simp; omega, .tail _ m⟩

/-- The last line of a paragraph block whose rule after waits is in the
    column, on the grid line the waiting rule names: the rule after and the
    rule before of the next block share the area after that line when they
    are placed (`I3_placeRuled_joined`).  A ruled paragraph has a line
    (golem-typeset breaks every paragraph into one line or more, README.md). -/
theorem I3_commitRuled_waiting_line (env : Env) (st : St) (i : Nat) (b a : Bool) (kp : Keep) (ls : List Line)
    (rest : List Flow) (x : Nat) (l : Int) (hb : ls ≠ [])
    (h : (commitRuled env st (.lines kp ls) (planOf env st i b a (.lines kp ls) rest none)).join = some (x, l)) :
    ∃ id, (l, Slot.line id) ∈ (commitRuled env st (.lines kp ls) (planOf env st i b a (.lines kp ls) rest none)).slots := by
  obtain ⟨_, _, hl⟩ := I3_commitRuled_waiting env st i b a (.lines kp ls) rest x l (by simpa [RuledBody.lines'] using hb) h
  obtain ⟨_, _, hs⟩ := I3_commitRuled_column env st (.lines kp ls) (planOf env st i b a (.lines kp ls) rest none)
  obtain ⟨id, v, e, m⟩ := lineSlots_last (st.used + (planOf env st i b a (.lines kp ls) rest none).before) ls hb
  refine ⟨id, ?_⟩
  rw [hs]
  have : v = l := by rw [e, hl]; simp [RuledBody.size]
  rw [← this]
  exact List.mem_append_of_mem_right _ m

/-! ## The rule after that waits stays in its column (golem-driver ADR 0027) -/

/-- A block `settleRuled` places with its rule after waiting leaves the
    flows ahead settling that rule (`settlesAfter`): `settleRuled` lets the
    rule wait only when it does, and counts the area of the rule after in
    the block otherwise. -/
theorem I3_settleRuled_waiting (env : Env) (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow)
    (j : Option (Nat × Int)) (r : St) (h : settleRuled env st i b a body rest j = some r) (hn : r.join ≠ none) :
    settlesAfter env r rest = true := by
  unfold settleRuled at h
  split at h
  · rename_i c; rw [← Option.some.inj h]; exact c.2
  · split at h
    · exfalso; apply hn; rw [← Option.some.inj h]
      show (planOf env st i b a body [] j).waiting = none
      simp [planOf, joinsNext, flattenParts]
    · cases h

/-- The rule after that waits, placed in its own area by `flushJoin` when
    that area fits the room (`ownFits`), lies in the column. -/
theorem I3_ownFits_flushJoin (env : Env) (st : St) (x : Nat) (l : Int) (hw : st.join = some (x, l))
    (hu : st.used = l + 1) (h : ownFits env st = true) :
    ∃ rr, (flushJoin env st).rules = st.rules ++ [rr] ∧ rr.id = x ∧ rr.before = false ∧ rr.line = l
      ∧ InColumn env st rr := by
  unfold ownFits at h; rw [hw] at h; simp only [decide_eq_true_eq] at h
  unfold flushJoin; rw [hw]
  refine ⟨_, rfl, rfl, rfl, rfl, ?_⟩
  have hf : ∀ r : PlacedRule, r.line = l → (∀ o, r.edge ≠ .start o) → (r.area : Int) ≤ free env st →
      InColumn env st r := by
    intro r e h2 ar
    simp only [InColumn, free, first_of_not_start r h2, e] at ar ⊢
    omega
  exact hf _ rfl (fun o => ite_not_start _ _ o) h

/-- A rule after that waits and that the flows ahead settle
    (`settlesAfter`) is taken into its area by the next block, a block that
    shares it and is placed with it in this column, or lies in this column
    in its own area (`flushJoin`). -/
theorem I3_settlesAfter_rule (env : Env) (st : St) (rest : List Flow) (x : Nat) (l : Int)
    (hw : st.join = some (x, l)) (hu : st.used = l + 1) (h : settlesAfter env st rest = true) :
    (∃ i a body later r, flattenParts rest = .ruled i true a true body :: later ∧ body.recto = false
      ∧ settleRuled env st i true a body later (some (x, l)) = some r)
    ∨ (∃ rr, (flushJoin env st).rules = st.rules ++ [rr] ∧ rr.id = x ∧ rr.before = false ∧ rr.line = l
      ∧ InColumn env st rr) := by
  unfold settlesAfter at h
  generalize e : flattenParts rest = fs at h
  unfold settlesOn at h
  rw [hw] at h
  split at h
  · rename_i hj; cases hj
  · rename_i j i a body later hj
    cases hj
    split at h
    · rename_i c
      simp only [Bool.and_eq_true, Bool.not_eq_true'] at c
      obtain ⟨c1, c2⟩ := c
      cases hs : settleRuled env st i true a body later (some (x, l)) with
      | none => rw [hs] at c2; cases c2
      | some r => exact Or.inl ⟨i, a, body, later, r, rfl, c1, hs⟩
    · exact Or.inr (I3_ownFits_flushJoin env st x l hw hu h)
  · exact Or.inr (I3_ownFits_flushJoin env st x l hw hu h)

/-- `settleRuled` reads the flows ahead with their book parts opened. -/
theorem settleRuled_flatten (env : Env) (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow)
    (j : Option (Nat × Int)) :
    settleRuled env st i b a body (flattenParts rest) j = settleRuled env st i b a body rest j := by
  have hp : ∀ s, planOf env s i b a body (flattenParts rest) j = planOf env s i b a body rest j := by
    intro s; simp only [planOf, joinsNext, flattenParts_flattenParts]
  unfold settleRuled
  simp only [hp, flattenParts_flattenParts]

/-- The rule after of a block that waits for a block sharing its area
    stays in its column: when the flows ahead settle it, the next block
    shares the area and `placeRuled` places it with both rules in this
    column, or `flushJoin` puts the rule in its own area in this column. -/
theorem I3_waiting_rule_in_column (env : Env) (hs : 0 ≤ env.separator) (st : St) (x : Nat) (l : Int)
    (i : Nat) (a : Bool) (body : RuledBody) (later : List Flow)
    (hw : st.join = some (x, l)) (hu : st.used = l + 1)
    (h : settlesAfter env st (.ruled i true a true body :: later) = true) :
    (Placed env body (placeRuled env st i true a true body later)
      ∧ ∃ r, settleRuled env st i true a body later (some (x, l)) = some r
        ∧ placeRuled env st i true a true body later = r)
    ∨ (∃ rr, (flushJoin env st).rules = st.rules ++ [rr] ∧ rr.id = x ∧ rr.before = false ∧ rr.line = l
      ∧ InColumn env st rr) := by
  rcases I3_settlesAfter_rule env st _ x l hw hu h with ⟨i', a', body', later', r, e, hr, hset⟩ | o
  · simp only [flattenParts, List.cons.injEq, Flow.ruled.injEq] at e
    obtain ⟨⟨e1, -, e2, -, e3⟩, e4⟩ := e
    subst e1 e2 e3 e4
    rw [settleRuled_flatten] at hset
    have pj := (I3_placeRuled_joined env st _ true _ _ later x l hw rfl hr r hset).1
    refine Or.inl ⟨?_, r, hset, pj⟩
    rw [pj]
    exact I3_settleRuled_rules env hs st _ true _ _ later (some (x, l)) r hset
      (fun x' l' e => by cases e; exact hu)
  · exact Or.inr o

/-- A block `settleRuled` places with its rule after waiting leaves the
    lines used at the line after its last line, the line the waiting rule
    names. -/
theorem I3_settleRuled_used (env : Env) (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow)
    (j : Option (Nat × Int)) (r : St) (x : Nat) (l : Int) (hb : body.lines' ≠ [])
    (h : settleRuled env st i b a body rest j = some r) (hn : r.join = some (x, l)) : r.used = l + 1 := by
  obtain ⟨rest', _, _, e⟩ := settleRuled_spec env st i b a body rest j r h
  subst e
  have hj : (planOf env st i b a body rest' j).waiting = some (x, l) := hn
  have ha : (planOf env st i b a body rest' j).after = 0 := by
    simp only [planOf] at hj ⊢
    split at hj
    · rename_i hn; simp [hn]
    · simp at hj
  simp only [planOf] at hj
  split at hj
  · simp only [Option.some.injEq, Prod.mk.injEq] at hj
    obtain ⟨_, hl⟩ := hj
    have u2 : ∀ s2 : St, s2.used = st.used + (planOf env st i b a body rest' j).before + body.size →
        min (s2.used + (planOf env st i b a body rest' j).after) (max s2.used (cap env s2 - s2.noteLines))
          = l + 1 := by
      intro s2 hs2
      rw [ha, ← hl]
      have m := Int.le_max_left s2.used (cap env s2 - s2.noteLines)
      simp only [planOf] at hs2
      omega
    simp only [commitRuled]
    apply u2
    cases body with
    | lines kp ls =>
      have := (putRuledLines_keeps env (planOf env st i b a (.lines kp ls) rest' j).after ls
        { st with used := st.used + (planOf env st i b a (.lines kp ls) rest' j).before, join := none }).2.2.2
      simp only [RuledBody.size]; rw [this]
    | heading r n ls =>
      cases ls with
      | nil => exact absurd rfl hb
      | cons l0 ls => simp [putBlock, RuledBody.size]
  · simp at hj

/-- A block that shares the area of the rule waiting (`frJoined`, a rule
    before, not at a recto) but does not settle in its column starts in
    the next column (root ADR 0449, Paginate.hs `placeRuled`): the rule
    waiting is put in its own area in the column of the block before
    (`flushJoin`), and the block is placed as `placeRuledFresh` places it
    from the next column, which comes after that column and starts with no
    rule waiting and no rules.  So the rules of the block lie in a column
    after the rule of the block before (root ADR 0449 I2), each in the
    column it is placed from, or the block is split without them. -/
theorem I2_placeRuled_next_column (env : Env) (hs : 0 ≤ env.separator) (st : St) (i : Nat) (a : Bool)
    (body : RuledBody) (rest : List Flow) (x : Nat) (l : Int) (hw : st.join = some (x, l)) (hu : st.used = l + 1)
    (hr : body.recto = false) (hn : settleRuled env st i true a body rest (some (x, l)) = none) :
    placeRuled env st i true a true body rest
        = placeRuledFresh env (nextColumn env (flushJoin env st)) i true a body rest
      ∧ (∃ rr, (flushJoin env st).rules = st.rules ++ [rr] ∧ rr.id = x ∧ rr.before = false ∧ rr.line = l
        ∧ SameColumn st (flushJoin env st))
      ∧ posLt st (nextColumn env (flushJoin env st))
      ∧ (nextColumn env (flushJoin env st)).join = none ∧ (nextColumn env (flushJoin env st)).rules = []
      ∧ SplitPlaced env body (placeRuled env st i true a true body rest) := by
  have e : placeRuled env st i true a true body rest
      = placeRuledFresh env (nextColumn env (flushJoin env st)) i true a body rest := by
    unfold placeRuled
    rw [hw]
    simp only [settleJoined, hr, Bool.true_and, Bool.not_false, ↓reduceIte, hn, unjoined]
  obtain ⟨rr, h1, h2, h3, h4, h5, _⟩ := I3_flushJoin_rule env st x l hw hu
  have p : posLt (flushJoin env st) (nextColumn env (flushJoin env st)) := advance_posLt ..
  have p' : posLt st (nextColumn env (flushJoin env st)) := by
    simp only [posLt] at p ⊢; rw [h5.1, h5.2.1] at p; exact p
  refine ⟨e, ⟨rr, h1, h2, h3, h4, h5⟩, p', (I3_advance_clears ..).1, (I3_advance_clears ..).2, ?_⟩
  rw [e]; exact I3_placeRuledFresh_rules env hs _ i true a body rest

end Rules
end WholePagination
