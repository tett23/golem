{- | The types of placing lines on pages (golem-layout ADR 0003): the
flows that go in and the columns of pages that come out.
'Golem.Layout.Paginate' exports them.
-}
module Golem.Layout.Paginate.Types
  ( LineBox (..),
    ColumnSet,
    ColumnSetAt (..),
    NoteId (..),
    NoteBody (..),
    Flow,
    FlowAt (..),
    Slotted (..),
    PageOut,
    PageOutAt (..),
    Unmet (..),
    AdjustLimit (..),
    TableSegment,
    TableSegmentAt (..),
    BoxSegment,
    BoxSegmentAt (..),
    RuledBody,
    RuledBodyAt (..),
    PlacedRule (..),
    HeadingBlock (..),
    Keep (..),
    defaultKeep,
    StartOf (..),
    Part (..),
  )
where

import Data.Text (Text)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Code (CodeGeometry)
import Golem.Layout.Look (NoteId (..))
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Length (Sp)
import Golem.Project.Style (KeepParts)
import Golem.Syntax (SrcSpan)

data NoteBody = NoteBody {nbId :: !NoteId, nbLines :: !Int}
  deriving stock (Eq, Show)

data LineBox = LineBox
  { lbId :: !Int,
    lbNotes :: ![NoteBody],
    lbLabels :: ![Text],
    -- | index marks on the line (golem-driver ADR 0007)
    lbMarks :: ![SrcSpan],
    {- | how far the ruby and kenten of the line reach out of the face of
    the line toward the line before it, in sp (golem-driver ADR 0033);
    pagination does not read it
    -} lbOverhang :: !Sp
  }
  deriving stock (Eq, Show)

{- | How a paragraph is broken between columns (docs/adr/0261): the
fewest lines (verse lines of a stanza) of its first and last parts, and
whether it is not broken at all.
-}
data Keep = Keep {kFirst :: !Int, kLast :: !Int, kAll :: !Bool}
  deriving stock (Eq, Show)

-- | The rule before docs/adr/0261: no first or last line alone, broken anywhere.
defaultKeep :: Keep
defaultKeep = Keep 2 2 False

{- | What a start before the flow starts (docs/adr/0260, docs/adr/0261): a
section, by its number in the order of the manifest, or a paragraph of a
style with page-break, by its span.
-}

-- | The first or the last part of a paragraph broken between columns (docs/adr/0261).
data Part = FirstPart | LastPart
  deriving stock (Eq, Show)

data StartOf = OfSection !Int | OfParagraph !SrcSpan
  deriving stock (Eq, Show)

type Flow = FlowAt Int

data FlowAt position
  = -- | A book part and its retained slot IDs (root ADR 0377 and 0401).
    FBookPart !KeepParts !SrcSpan !Text ![Int] ![FlowAt position]
  | -- | a paragraph and how it is broken (docs/adr/0261)
    FParagraph !Keep [LineBox]
  | {- | a stanza of verse, a paragraph of line-breaks = "keep": its verse
    lines, each the lines it is broken into (docs/adr/0180). A verse line
    is not broken between columns; a column does not end or start with a
    single verse line of a stanza.
    -}
    FStanza !Keep [[LineBox]]
  | -- | a heading, placed whole over 'fhSpan' grid lines (golem-driver ADR 0003)
    FHeading {fhLevel :: !Int, fhRecto :: !Bool, fhSpan :: !position, fhLines :: [LineBox]}
  | FDefTerm [LineBox]
  | -- | a figure with its caption, in grid lines
    FFigure {ffId :: !Int, ffLines :: !position, ffLabels :: ![Text], ffMarks :: ![SrcSpan]}
  | -- | a wrapped figure and the shortened lines set beside it (ADR 0004)
    FWrapped {fwId :: !Int, fwLines :: !position, fwLabels :: ![Text], fwMarks :: ![SrcSpan], fwBeside :: [LineBox]}
  | {- | a figure turned onto a page of its own (golem-driver ADR 0034): on
    the page if nothing is on it, else waiting with the figures sent on,
    at the start of a later page
    -}
    FPageFigure {fpId :: !Int, fpLabels :: ![Text], fpMarks :: ![SrcSpan]}
  | {- | the rest of a paragraph whose first lines are beside a wrapped
    figure: no orphan rule for its first line (golem-driver ADR 0005)
    -}
    FContinued !Keep [LineBox]
  | {- | a table: the grid lines of space before it (not at the first line
    of a column), its header row (none when empty) and body rows, in grid
    lines (golem-driver ADR 0008, 0031), and the grid lines of its caption
    (none without one), before the header row or, with 'ftCaptionBelow',
    after the last row (docs/adr/0262)
    -}
    FTable {ftId :: !Int, ftSpaceBefore :: !position, ftHeader :: ![LineBox], ftRows :: ![[LineBox]], ftCaption :: ![LineBox], ftCaptionBelow :: !Bool}
  | {- | empty grid lines, as between stanzas of verse (docs/adr ADR 0003);
    nothing at the top of a page
    -}
    FSpace !position
  | -- | a forced break before what follows (docs/adr ADR 0017)
    FBreak !BreakKind
  | {- | a start before what follows (docs/adr/0260, docs/adr/0261): of a
    section, or of a paragraph of a style with page-break. Unlike a forced
    break, it does nothing in an empty column or on an empty page: to the
    next column unless the column is empty ('BreakColumn'), to the next
    page unless the page is empty ('BreakPage'), and to an odd or an even
    page ('BreakRecto', 'BreakVerso'), the figures sent on and the
    continued notes placed first but for a column. The page a start of a
    section opens is the first page of the section.
    -}
    FSection !StartOf !BreakKind
  | {- | a paragraph kept with the first part of what follows, of at least
    so many lines (docs/adr/0261): placed right after the paragraph, with
    the span of the paragraph
    -}
    FKeepNext !SrcSpan !Int
  | {- | a code block: its rows, broken between any two of them; each part
    takes the grid lines of 'codeSpan' (golem-driver ADR 0017). The first
    part has the grid lines of the caption above it and at least
    'fcFirst' rows; with 'fcContinued', each part but the last has a row
    more for the text that it continues (golem-driver ADR 0023).
    -}
    FCode
      { fcGeometry :: !CodeGeometry,
        fcCaption :: !position,
        fcFirst :: !Int,
        fcContinued :: !Bool,
        fcRows :: [LineBox]
      }
  | {- | a paragraph or a heading with rules (golem-driver ADR 0027): the
    areas of its rules, its lines and the areas are placed as one block,
    not broken between columns. 'frId' names its rules in 'PlacedRule';
    with 'frJoined', its rule before shares one area with the rule after
    of the ruled block just before it; 'frNextOverhang' is the overhang of
    the first line after it.
    -}
    FRuled
      { frId :: !Int,
        frBefore :: !(Maybe RuleSide),
        frAfter :: !(Maybe RuleSide),
        frJoined :: !Bool,
        frGrid :: !RuleGrid,
        frNextOverhang :: !Sp,
        frBody :: !(RuledBodyAt position)
      }
  | {- | paragraphs in one box (docs/adr/0271): each part of the box in a
    column takes 'fbBefore' grid lines before its first line and
    'fbAfter' after its last; the body holds paragraphs, stanzas and the
    spaces between them, broken as they are outside a box
    -}
    FBoxed {fbId :: !Int, fbBefore :: !position, fbAfter :: !position, fbBody :: ![FlowAt position]}
  | -- | the start of the index in its own columns (docs/adr ADR 0025)
    FSwitchColumns !(ColumnSetAt position)
  | -- | the end of the index: the next page, in the columns of the page
    FRestoreColumns
  | -- | no page or column break between the flows around (docs/adr ADR 0030)
    FNoBreak !SrcSpan
  | FNoBreakLines !SrcSpan !Int
  | -- | go to the next column unless this many grid lines are free
    FNeedLines !SrcSpan !Int
  | -- | change the grid lines of the current column
    FAdjustLines !SrcSpan !Int
  | {- | blank lines before what follows (docs/adr ADR 0046), in its
    column; dropped at the top of a column
    -}
    FBlank !SrcSpan !Int
  deriving stock (Eq, Show, Functor)

{- | What a ruled block holds (golem-driver ADR 0027): the lines of a
paragraph, or a heading (recto, grid lines, lines) as 'FHeading'.
-}
type RuledBody = RuledBodyAt Int

data RuledBodyAt position
  = RuledLines !Keep ![LineBox]
  | RuledHeading {rhRecto :: !Bool, rhSpan :: !position, rhLines :: ![LineBox]}
  deriving stock (Eq, Show, Functor)

{- | A rule placed in a column (golem-driver ADR 0027): the block it
belongs to, whether it is the rule before, and the place of the start of
its weight across the lines in sp from the start of the em box of the
first grid line of the page (negative out of the column).
-}
data PlacedRule = PlacedRule {prId :: !Int, prBefore :: !Bool, prAt :: !Sp}
  deriving stock (Eq, Show)

{- | A set of columns (docs/adr ADR 0025): from which grid line of the
page, how many columns, of which measure and gap.
-}
type ColumnSet = ColumnSetAt Int

data ColumnSetAt position = ColumnSet
  { -- | the number of columns
    csColumns :: !Int,
    -- | the measure of a column (sp)
    csMeasure :: !Sp,
    -- | the gap between columns (sp)
    csGap :: !Sp,
    -- | the grid line of the page where the columns start, from 0
    csFirstLine :: !position
  }
  deriving stock (Eq, Show, Functor)

data Slotted
  = SLine !Int
  | SFigure !Int
  | SWrapped !Int
  | -- | a figure turned onto the whole page (golem-driver ADR 0034)
    SPageFigure !Int
  | -- | a heading block: its first line and how many lines it has
    SHeading !Int !Int
  | -- | a part of a code block: its first row, how many rows it has and the grid lines it takes (golem-driver ADR 0017)
    SCode !Int !Int !Int
  deriving stock (Eq, Show)

-- | How a heading sits on the line grid (golem-driver ADR 0003).
data HeadingBlock = HeadingBlock
  { -- | the line pitch of the heading
    hbPitch :: !Sp,
    -- | how many grid lines it takes
    hbSpan :: !Int,
    -- | from its first grid line to the top of its first line
    hbOffset :: !Sp
  }
  deriving stock (Eq, Show)

-- | One column of a page (docs/adr ADR 0018).
type PageOut = PageOutAt Int

data PageOutAt position = PageOut
  { poNumber :: !Int,
    -- | the column, from 0 in the order of 'pgColumns'
    poColumn :: !Int,
    poBlank :: !Bool,
    -- | grid line index and what starts there
    poSlots :: ![(position, Slotted)],
    -- | note id, first line of the body shown here, number of lines
    poFootnotes :: ![(NoteId, Int, Int)],
    poLabels :: ![Text],
    -- | the index marks placed on the page (golem-driver ADR 0007)
    poMarks :: ![SrcSpan],
    -- | the parts of tables on the page (golem-driver ADR 0008)
    poTables :: ![TableSegmentAt position],
    -- | the set of columns the column belongs to (docs/adr ADR 0025)
    poColumnSet :: !(ColumnSetAt position),
    -- | the rules of paragraphs and headings in the column (golem-driver ADR 0027)
    poRules :: ![PlacedRule],
    -- | the grid lines of the column, changed by 'FAdjustLines' (docs/adr ADR 0030)
    poLines :: !position,
    -- | the manual controls of page breaks not met in the column
    poUnmet :: ![Unmet],
    {- | the sections whose first page this is, in the order of the
    manifest, on the first column of the page (docs/adr/0260)
    -} poSections :: ![Int],
    -- | the parts of boxes in the column (docs/adr/0271)
    poBoxes :: ![BoxSegmentAt position]
  }
  deriving stock (Eq, Show, Functor)

-- | Why @page-lines was cut short (docs/adr ADR 0030).
data AdjustLimit
  = -- | no more lines fit inside the page
    AdjustNoRoom
  | -- | the column already holds more lines
    AdjustLinesPlaced
  | -- | a column keeps at least one line
    AdjustOneLine
  deriving stock (Eq, Show)

-- | A manual control of page breaks that could not be met (docs/adr ADR 0030).
data Unmet
  = -- | A book part split after an empty retention unit failed (root ADR 0401).
    SplitBookPart !SrcSpan !Text !KeepParts
  | UnmetNoBreak !SrcSpan
  | -- | the lines asked for
    UnmetNeedLines !SrcSpan !Int
  | -- | the lines the column was changed by, and why it was cut short
    UnmetAdjust !SrcSpan !Int !AdjustLimit
  | -- | blank lines dropped at the top of a column (docs/adr ADR 0046)
    DroppedBlank !SrcSpan
  | {- | a heading placed in an empty column it does not fit (golem-layout
    ADR 0020): the id of its first line, its grid lines and the grid
    lines left in the column
    -}
    TallHeading !Int !Int !Int
  | -- | The same overhang in free placement: heading length and remaining length in sp.
    TallHeadingExtent !Int !Sp !Sp
  | -- | a keep-with-next not met: the span of the paragraph (docs/adr/0261)
    UnmetKeepNext !SrcSpan
  | -- | a footnote cannot make progress even in an empty column (Golem ADR 0353)
    UnplaceableFootnote !NoteId !Int
  | -- | a paragraph of keep-all-lines broken, as an empty column does not hold it: the id of its first line (docs/adr/0261)
    SplitKept !Int
  | {- | a first or last part shorter than its keep, placed in an empty
    column (docs/adr/0261): which part, the id of the first line of the
    paragraph, the lines asked for and the lines placed
    -}
    ShortPart !Part !Int !Int !Int
  deriving stock (Eq, Show)

-- | The part of a table on a page, in grid lines.
type TableSegment = TableSegmentAt Int

data TableSegmentAt position = TableSegment
  { tsTable :: !Int,
    tsFirst :: !position,
    -- | the last grid line of the header row; none for a table without one (golem-driver ADR 0031)
    tsHeaderEnd :: !(Maybe position),
    tsLast :: !position
  }
  deriving stock (Eq, Show, Functor)

{- | The part of a box in a column (docs/adr/0271): the box, and the first
and the last grid line it takes, the grid lines before its first line
and after its last included.
-}
type BoxSegment = BoxSegmentAt Int

data BoxSegmentAt position = BoxSegment
  { bsBox :: !Int,
    bsFirst :: !position,
    bsLast :: !position
  }
  deriving stock (Eq, Show, Functor)
