namespace BesideOwnership

/-- The two guards read by besideParagraphs. The beside guard has priority. -/
structure Class where
  beside : Bool
  control : Bool
  deriving DecidableEq

/-- Scan a finite interval of unit keys. Outside it, both maps are absent. -/
def scan (start : Nat) : List Class → List Nat
  | [] => []
  | row :: later =>
    if row.beside then start :: scan (start + 1) later
    else if row.control then scan (start + 1) later
    else []

theorem root_adr0352_i5_beside_key_range (rows : List Class) (start key : Nat)
    (member : key ∈ scan start rows) : start ≤ key ∧ key < start + rows.length := by
  induction rows generalizing start with
  | nil => simp [scan] at member
  | cons row later ih =>
    cases beside : row.beside with
    | true =>
      simp [scan, beside] at member
      rcases member with atStart | rest
      · subst key
        simp only [List.length_cons]
        omega
      · have range := ih (start + 1) rest
        simp only [List.length_cons]
        omega
    | false =>
      cases control : row.control with
      | true =>
        simp [scan, beside, control] at member
        have range := ih (start + 1) member
        simp only [List.length_cons]
        omega
      | false => simp [scan, beside, control] at member

/-- Keys are strictly increasing in their source order. -/
def Increasing : List Nat → Prop
  | [] => True
  | key :: later => (∀ other ∈ later, key < other) ∧ Increasing later

theorem root_adr0352_i5_beside_key_order (rows : List Class) (start : Nat) :
    Increasing (scan start rows) := by
  induction rows generalizing start with
  | nil => trivial
  | cons row later ih =>
    cases beside : row.beside with
    | true =>
      simp only [scan, beside, if_true, Increasing]
      refine ⟨?_, ih (start + 1)⟩
      intro key member
      have range := root_adr0352_i5_beside_key_range later (start + 1) key member
      omega
    | false =>
      cases control : row.control with
      | true => simpa [scan, beside, control] using ih (start + 1)
      | false => simp [scan, beside, control, Increasing]

def NoRepeat : List Nat → Prop
  | [] => True
  | key :: later => (key ∉ later) ∧ NoRepeat later

private theorem increasing_noRepeat (keys : List Nat) (ordered : Increasing keys) : NoRepeat keys := by
  induction keys with
  | nil => trivial
  | cons key later ih =>
    refine ⟨?_, ih ordered.2⟩
    intro member
    have impossible := ordered.1 key member
    omega

theorem root_adr0352_i5_beside_keys_unique (rows : List Class) (start : Nat) :
    NoRepeat (scan start rows) :=
  increasing_noRepeat _ (root_adr0352_i5_beside_key_order rows start)

theorem root_adr0352_i5_owner_key_not_selected (rows : List Class) (owner : Nat) :
    owner ∉ scan (owner + 1) rows := by
  intro member
  have range := root_adr0352_i5_beside_key_range rows (owner + 1) owner member
  omega

/-- A figure or another hard layout unit ends the current side job. -/
theorem root_adr0352_i5_beside_stops_at_barrier (before after : List Class) (start : Nat)
    (barrier : Class) (notBeside : barrier.beside = false) (notControl : barrier.control = false) :
    scan start (before ++ barrier :: after) = scan start before := by
  induction before generalizing start with
  | nil => simp [scan, notBeside, notControl]
  | cons row later ih =>
    cases beside : row.beside with
    | true => simp [scan, beside, ih]
    | false => cases control : row.control <;> simp [scan, beside, control, ih]

/-- A second figure separates the two side jobs. Their keys cannot collide. -/
theorem root_adr0352_i5_owner_ranges_disjoint (before after : List Class) (start : Nat)
    (barrier : Class) (notBeside : barrier.beside = false) (notControl : barrier.control = false)
    (earlier later : Nat) (left : earlier ∈ scan start (before ++ barrier :: after))
    (right : later ∈ scan (start + before.length + 1) after) : earlier < later := by
  rw [root_adr0352_i5_beside_stops_at_barrier before after start barrier notBeside notControl] at left
  have first := root_adr0352_i5_beside_key_range before start earlier left
  have second := root_adr0352_i5_beside_key_range after (start + before.length + 1) later right
  omega

end BesideOwnership
