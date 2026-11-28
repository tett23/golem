import MixedKeywords
namespace KeywordLowering
inductive Kind where
  | word | equals | quoted | whitespace | comment | newline | proofComment | ignored
  deriving Repr, DecidableEq
structure Token where
  kind : Kind
  chars : List Char
  deriving Repr, DecidableEq
abbrev Value := QuotedKeywords.Value

def isTrivia (token : Token) : Bool :=
  token.kind == .whitespace || token.kind == .comment || token.kind == .newline
def significant (tokens : List Token) : List Token := tokens.filter (fun t => !isTrivia t)
def unquote (chars : List Char) : List Char := StringRoundTrip.unescape ((chars.drop 1).dropLast)
def argValue (token : Token) : Option Value :=
  match token.kind with
  | .word => some (.word token.chars)
  | .quoted => some (.string (unquote token.chars))
  | _ => none

def lowerKeyword (tokens : List Token) : Option (List Char × Value) :=
  match significant tokens with
  | ⟨.word,name⟩::_::value::_ => (argValue value).map (fun v => (name,v))
  | _ => none

inductive Trivia where
  | whitespace (chars : List Char)
  | comment (chars : List Char)
  | newline (chars : List Char)
  deriving Repr, DecidableEq
def triviaToken : Trivia → Token
  | .whitespace chars => ⟨.whitespace,chars⟩
  | .comment chars => ⟨.comment,chars⟩
  | .newline chars => ⟨.newline,chars⟩
def triviaTokens (items : List Trivia) : List Token := items.map triviaToken

def valueToken : MixedKeywords.Input → Token
  | .word value => ⟨.word,value.chars⟩
  | .string parts => ⟨.quoted,MixedKeywords.spelling (.string parts)⟩
structure Decorated where
  entry : MixedKeywords.Entry
  before : List Trivia
  middleLeft : List Trivia
  middleRight : List Trivia
  after : List Trivia

def decoratedTokens (value : Decorated) : List Token :=
  triviaTokens value.before ++ [⟨.word,value.entry.1.chars⟩] ++
  triviaTokens value.middleLeft ++ [⟨.equals,['=']⟩] ++
  triviaTokens value.middleRight ++ [valueToken value.entry.2] ++ triviaTokens value.after

theorem significant_trivia (items : List Trivia) : significant (triviaTokens items) = [] := by
  induction items with
  | nil => rfl
  | cons x xs ih => cases x <;> simpa [significant,triviaTokens,triviaToken,isTrivia,List.filter] using ih

theorem proof_comment_is_significant (chars : List Char) :
    significant [⟨.proofComment,chars⟩] = [⟨.proofComment,chars⟩] := by rfl

theorem significant_append (left right : List Token) :
    significant (left ++ right) = significant left ++ significant right := by
  induction left with
  | nil => rfl
  | cons t ts ih =>
    cases h : isTrivia t <;> simpa [significant,List.filter,h] using ih

theorem significant_decorated (value : Decorated) :
    significant (decoratedTokens value) =
      [⟨.word,value.entry.1.chars⟩,⟨.equals,['=']⟩,valueToken value.entry.2] := by
  simp only [decoratedTokens,significant_append,significant_trivia,List.nil_append,List.append_nil]
  rcases value with ⟨⟨name,input⟩,a,b,c,d⟩
  cases input <;> rfl

theorem dropLast_snoc (chars : List Char) (c : Char) : (chars ++ [c]).dropLast = chars := by
  induction chars with
  | nil => rfl
  | cons a chars ih => cases chars <;> simp_all [List.dropLast]

theorem unquote_spelling (parts : List StringRoundTrip.Part) :
    unquote (MixedKeywords.spelling (.string parts)) = parts.map StringRoundTrip.partValue := by
  simp [unquote,MixedKeywords.spelling,dropLast_snoc,StringRoundTrip.unescape_spell]

theorem valueToken_exact (input : MixedKeywords.Input) :
    argValue (valueToken input) = some (MixedKeywords.abstractValue input) := by
  cases input with
  | word value => rfl
  | string parts => simp [argValue,valueToken,unquote_spelling,MixedKeywords.abstractValue]

theorem I1_lower_decorated_keyword (value : Decorated) :
    lowerKeyword (decoratedTokens value) = some (MixedKeywords.abstract value.entry) := by
  unfold lowerKeyword
  rw [significant_decorated]
  change (argValue (valueToken value.entry.2)).map (fun v => (value.entry.1.chars,v)) = _
  rw [valueToken_exact]
  rfl

theorem leading_proof_comment_rejected (chars : List Char) (value : Decorated) :
    lowerKeyword (⟨.proofComment,chars⟩ :: decoratedTokens value) = none := by rfl

inductive Element where
  | keyword (tokens : List Token)
  | ignored

def lowerElement : Element → Option (List Char × Value)
  | .keyword tokens => lowerKeyword tokens
  | .ignored => none

def lowerArguments (elements : List Element) : List (List Char × Value) := elements.filterMap lowerElement

theorem I1_lower_decorated_arguments (values : List Decorated) :
    lowerArguments (values.map fun value => Element.keyword (decoratedTokens value)) =
      values.map (fun value => MixedKeywords.abstract value.entry) := by
  induction values with
  | nil => rfl
  | cons value values ih =>
    simp only [lowerArguments,List.map_cons,List.filterMap,lowerElement,I1_lower_decorated_keyword]
    change MixedKeywords.abstract value.entry :: lowerArguments _ = _
    rw [ih]
def interleavedElements : List (Option Decorated) → List Element
  | [] => []
  | none::rest => Element.ignored :: interleavedElements rest
  | some value::rest => Element.keyword (decoratedTokens value) :: interleavedElements rest

theorem I1_lower_interleaved_arguments (values : List (Option Decorated)) :
    lowerArguments (interleavedElements values) =
      values.filterMap (fun value => value.map (fun entry => MixedKeywords.abstract entry.entry)) := by
  induction values with
  | nil => rfl
  | cons value values ih =>
    cases value with
    | none => simpa [interleavedElements,lowerArguments,List.filterMap,lowerElement] using ih
    | some entry =>
      simp only [interleavedElements,lowerArguments,List.filterMap,lowerElement,I1_lower_decorated_keyword]
      change MixedKeywords.abstract entry.entry :: lowerArguments _ = _
      rw [ih]
      rfl
#print axioms I1_lower_interleaved_arguments
#print axioms I1_lower_decorated_keyword
#print axioms I1_lower_decorated_arguments
end KeywordLowering
