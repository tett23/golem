{- | The semantic IR (golem-doc ADR 0001): evaluated content with no
geometry. The canonical definition is schema/golem-doc.cddl; these types
mirror it and are checked against it by round-trip tests.
-}
module Golem.Doc.IR
  ( abiVersion,
    pluginImagePrefix,
    pluginImageOutput,
    inInt64,
    Document (..),
    Block (..),
    BlockBody (..),
    BreakKind (..),
    PageControl (..),
    keepsPageBreak,
    ListItem (..),
    itemNumbers,
    DefGroup (..),
    Alignment (..),
    Table (..),
    plainTable,
    ColumnWidth (..),
    columnAbsolute,
    columnAbsoluteSp,
    HeadingAttrs (..),
    noHeadingAttrs,
    ChannelBlock (..),
    ChannelItem (..),
    ChannelOrder (..),
    ChannelDecl (..),
    Code (..),
    CodeLine (..),
    DiffMark (..),
    codeText,
    Figure (..),
    Wrap (..),
    InlineF (..),
    AkiAmount (..),
    akiAbsolute,
    akiAbsoluteSp,
    Inline,
    InlineNoRuby,
    RubySegment (..),
    NumberStyle (..),
    VerticalNumbers (..),
    verticalStyleOf,
    verticalNumbersNamed,
    RefKind (..),
    IndexEntry (..),
    IndexKind (..),
    SeeKind (..),
    CiteItem (..),
    citeItem,
    citeInlines,
    Locator (..),
    LocatorLabel (..),
    locatorLabelName,
    locatorLabelNamed,
    LocatorValue (..),
    DeferredExpr (..),
    noRuby,
    isLineBreak,
    splitAtLineBreaks,
    withoutAnchors,
    noteParagraphs,
    noteBody,
    mapNoteBody,
  )
where

import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Void (Void)
import Golem.Length (Sp (..))
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Span
import Numeric.Natural (Natural)

{- | Whether an integer is within the CDDL @int64@ (golem-doc ADR 0006):
from -2^63 to 2^63 - 1, the range of the integers of the IR, on every
target (docs/adr ADR 0247).
-}
inInt64 :: Integer -> Bool
inInt64 n = n >= toInteger (minBound :: Int64) && n <= toInteger (maxBound :: Int64)

{- | The ABI version shared with plugins. It goes up by one when the ABI
changes after the release that has it, and at most once between two
releases (docs/adr ADR 0052); scripts/ci/abi-version.sh checks it.
-}
abiVersion :: Int
abiVersion = 9

{- | The source of a figure whose image a plugin made (docs/adr/0123):
this prefix, the SHA-256 of the bytes in hexadecimal and the extension.
It has ://, so a path of the source written so is a URL (G02060), never a
file of the project.
-}
pluginImagePrefix :: Text
pluginImagePrefix = "golem-plugin-image://"

-- | Where HTML and EPUB put the image of such a figure: images/golem-plugin/<SHA-256>.<extension>.
pluginImageOutput :: Text -> Maybe Text
pluginImageOutput src = ("images/golem-plugin/" <>) <$> T.stripPrefix pluginImagePrefix src

data Document = Document
  { docFile :: !FileId,
    docBlocks :: ![Block]
  }
  deriving stock (Eq, Show)

data Block = Block
  { blockSpan :: !SrcSpan,
    blockLabel :: !(Maybe Text),
    -- | the language of the block, as written with @lang (docs/adr ADR 0187)
    blockLang :: !(Maybe Text),
    blockBody :: !BlockBody
  }
  deriving stock (Eq, Show)

data BlockBody
  = -- | a paragraph and its paragraph style; Nothing is body (docs/adr ADR 0005)
    Paragraph !(Maybe Text) [Inline]
  | Heading !Int HeadingAttrs [Inline]
  | BulletList [ListItem]
  | OrderedList [ListItem]
  | DefList [DefGroup]
  | -- | a table (docs/adr/0262)
    TableBlock !Table
  | -- | a code block (golem-driver ADR 0023)
    CodeBlock !Code
  | FigureBlock Figure
  | ChannelOutput ChannelBlock
  | -- | a forced break before what follows (docs/adr ADR 0017)
    ForcedBreak !BreakKind
  | -- | a manual control of page breaks (docs/adr ADR 0030)
    PageControl !PageControl
  | -- | blank lines before what follows (docs/adr ADR 0046)
    BlankLines !Int64
  deriving stock (Eq, Show)

{- | A manual control of page breaks (docs/adr ADR 0030): no break
between the blocks around, go on in the next column unless this many
grid lines are free, or change the grid lines of the current column.
-}
data PageControl = NoBreak | NoBreakLines !Natural | NeedLines !Int | AdjustLines !Int
  deriving stock (Eq, Show)

keepsPageBreak :: PageControl -> Bool
keepsPageBreak NoBreak = True
keepsPageBreak (NoBreakLines n) = n > 0
keepsPageBreak _ = False

-- | The kind of a forced break (docs/adr ADR 0017).
data BreakKind = BreakPage | BreakRecto | BreakVerso | BreakColumn
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data ListItem = ListItem
  { itemNumber :: !(Maybe Natural), -- explicit @number (docs/adr ADR 0102)
    itemBlocks :: ![Block]
  }
  deriving stock (Eq, Show)

{- | The numbers of the items of a numbered list (golem-driver ADR 0013):
an item with @number N is N, and the items after it count on from N.
-}
itemNumbers :: [ListItem] -> [Integer]
itemNumbers = go 1
  where
    go _ [] = []
    go next (ListItem n _ : rest) = let k = maybe next toInteger n in k : go (k + 1) rest

data DefGroup = DefGroup
  { dgTerms :: [[Inline]],
    dgDefs :: [[Block]]
  }
  deriving stock (Eq, Show)

data Alignment = AlignDefault | AlignLeft | AlignCenter | AlignRight
  deriving stock (Eq, Show, Enum, Bounded)

{- | A table (docs/adr/0262): the alignments of its columns, their widths,
its caption and whether it goes without a table number, the paragraph
style of its cells, its header row and its body rows.
-}
data Table = Table
  { tableAligns :: ![Alignment],
    -- | the width of each column; [] when no column has a width (all are auto)
    tableWidths :: ![ColumnWidth],
    -- | the caption; a table with a caption has a table number unless tableNoNumber
    tableCaption :: !(Maybe [Inline]),
    tableNoNumber :: !Bool,
    -- | the paragraph style of the cells; Nothing is the built-in table
    tableStyle :: !(Maybe Text),
    tableHeader :: ![[Inline]],
    tableRows :: ![[[Inline]]]
  }
  deriving stock (Eq, Show)

-- | A table without widths, caption or paragraph style: what a table was before docs/adr/0262.
plainTable :: [Alignment] -> [[Inline]] -> [[[Inline]]] -> Table
plainTable al = Table al [] Nothing False Nothing

-- | The width of a column of a table (docs/adr/0262).
data ColumnWidth
  = ColumnAuto
  | -- | in zw of the cells' paragraph style
    ColumnZw !Rational
  | ColumnAbs !Sp
  | -- | in percent of the width the columns share
    ColumnPercent !Rational
  deriving stock (Eq, Show)

data HeadingAttrs = HeadingAttrs
  { haTocTitle :: !(Maybe [Inline]),
    haNumber :: !(Maybe Natural),
    haNoNumber :: !Bool,
    haNoToc :: !Bool
  }
  deriving stock (Eq, Show)

noHeadingAttrs :: HeadingAttrs
noHeadingAttrs = HeadingAttrs Nothing Nothing False False

{- | The list of a channel at its place: the table of contents, the index,
the bibliography, or a channel of a plugin with the paragraph style of its
entries (golem-doc ADR 0007).
-}
data ChannelBlock = TocOutput !Int | IndexOutput | BibliographyOutput | CustomOutput !Text !(Maybe Text)
  deriving stock (Eq, Show)

{- | An item a plugin sends to a channel of its own (golem-doc ADR 0007):
the channel, the key that makes items one entry, the reading of a channel
in reading order, and the body of the entry. It shows nothing where it is.
-}
data ChannelItem = ChannelItemData
  { ciChannel :: !Text,
    ciKey :: !(Maybe Text),
    ciReading :: !(Maybe Text),
    ciBody :: ![Inline]
  }
  deriving stock (Eq, Show)

-- | How the entries of a channel of a plugin are ordered (golem-doc ADR 0007).
data ChannelOrder = OrderDocument | OrderReading
  deriving stock (Eq, Show, Enum, Bounded)

{- | A channel a plugin declares (golem-doc ADR 0007): its name, the order
of its entries, and whether an entry shows where its items are.
-}
data ChannelDecl = ChannelDecl
  { channelName :: !Text,
    channelOrder :: !ChannelOrder,
    channelLocators :: !Bool
  }
  deriving stock (Eq, Show)

{- | A code block (golem-driver ADR 0023): its language, whether it has
line numbers (Nothing: [code] line-numbers decides), its file name, its
caption, whether it is a diff, and its lines as the evaluation read them.
-}
data Code = Code
  { codeLang :: !(Maybe Text),
    codeNumbers :: !(Maybe Bool),
    codeFile :: !(Maybe Text),
    codeCaption :: !(Maybe [Inline]),
    codeDiff :: !Bool,
    codeLines :: ![CodeLine],
    -- | whether a code block with a caption takes no listing number (docs/adr/0200)
    codeNoNumber :: !Bool
  }
  deriving stock (Eq, Show)

-- | The mark of a line of a diff.
data DiffMark = DiffAdded | DiffRemoved | DiffContext
  deriving stock (Eq, Show, Enum, Bounded)

{- | A line of code: its text without the diff mark and the callouts, its
number (Nothing for a removed line), its diff mark (Nothing when the code
is not a diff), whether it is highlighted, its callouts, and where its
text is in the source (docs/adr/0218).
-}
data CodeLine = CodeLine
  { clText :: !Text,
    clNumber :: !(Maybe Natural),
    clDiff :: !(Maybe DiffMark),
    clHighlight :: !Bool,
    clCallouts :: ![Int],
    -- | the text in the source, from after the diff mark to the end of the line before the callouts are taken off; Nothing for a line of @listing or of an Emet function (docs/adr/0218)
    clSpan :: !(Maybe SrcSpan)
  }
  deriving stock (Eq, Show)

-- | The text of the lines of code, joined by newlines.
codeText :: Code -> Text
codeText = T.intercalate "\n" . map clText . codeLines

data Wrap = WrapStart | WrapEnd
  deriving stock (Eq, Show, Enum, Bounded)

data Figure = Figure
  { figSource :: !Text,
    figWeb :: !(Maybe Text),
    figAlt :: !Text,
    figWrap :: !(Maybe Wrap),
    figWidth :: !(Maybe Text),
    figCaption :: ![Block],
    -- | the page of a PDF figure, from 1 (golem-pdf ADR 0008)
    figPage :: !(Maybe Natural),
    -- | whether the PDF turns the figure and its caption onto a page of their own (golem-driver ADR 0034)
    figRotate :: !Bool,
    -- | whether the figure takes no figure number (docs/adr/0200)
    figNoNumber :: !Bool
  }
  deriving stock (Eq, Show)

{- | Inline content. With @r = ()@ every constructor is available; with
@r = Void@ the 'Ruby' constructor cannot be built, which is how ruby
inside ruby is ruled out by the type.
-}
data InlineF r
  = Text !SrcSpan Text
  | Ruby !SrcSpan !r [RubySegment]
  | Kenten !SrcSpan !(Maybe Text) [InlineF r]
  | Color !SrcSpan !Text [InlineF r]
  | CharStyle !SrcSpan !Text [InlineF r]
  | Tcy !SrcSpan Text
  | Number !SrcSpan !Integer !(Maybe NumberStyle)
  | Ref !SrcSpan !RefKind !Text
  | Deferred !SrcSpan DeferredExpr
  | -- | a footnote, its number in its file and its body: paragraphs without a paragraph style, whatever r is (docs/adr/0263)
    Note !SrcSpan !Int [Block]
  | -- | a sidenote, its number and its body: one paragraph without a paragraph style (docs/adr/0263)
    Sidenote !SrcSpan !Int [Block]
  | IndexMark !SrcSpan IndexEntry
  | -- | a citation: one or more items, their keys distinct (docs/adr/0266)
    Cite !SrcSpan ![CiteItem r]
  | ProofComment !SrcSpan Text
  | -- | a forced line break, only between the inlines at the top of a paragraph (docs/adr ADR 0005)
    LineBreak !SrcSpan
  | -- | a fixed space written with [aki] (docs/adr ADR 0019)
    Aki !SrcSpan !AkiAmount
  | -- | an item of a channel of a plugin (golem-doc ADR 0007)
    ChannelItem !SrcSpan !ChannelItem
  | -- | a link to an external URL, as written (docs/adr ADR 0182)
    Link !SrcSpan !Text [InlineF r]
  | -- | a language span: the tag as written with [lang] (docs/adr ADR 0187)
    Lang !SrcSpan !Text [InlineF r]
  | -- | [ref-number] and [ref-title] after S1: the kind, the label and the inlines they resolve to (docs/adr/0215)
    Resolved !SrcSpan !RefKind !Text [InlineF r]
  deriving stock (Eq, Show)

-- | The amount of an [aki]: in zw (the size of the type there), or absolute in sp.
data AkiAmount = AkiZw !Rational | AkiAbs !Sp
  deriving stock (Eq, Show)

-- | A width of a column in sp, for a module without golem-length (docs/adr/0262).
columnAbsolute :: Integer -> ColumnWidth
columnAbsolute = ColumnAbs . Sp

-- | The sp of a width of a column in sp.
columnAbsoluteSp :: ColumnWidth -> Maybe Integer
columnAbsoluteSp = \case
  ColumnAbs (Sp x) -> Just x
  _ -> Nothing

-- | An absolute amount of an [aki] in sp, for a module without golem-length (docs/adr/0162).
akiAbsolute :: Integer -> AkiAmount
akiAbsolute = AkiAbs . Sp

-- | The sp of an absolute amount of an [aki].
akiAbsoluteSp :: AkiAmount -> Maybe Integer
akiAbsoluteSp = \case
  AkiAbs (Sp n) -> Just n
  AkiZw _ -> Nothing

type Inline = InlineF ()

type InlineNoRuby = InlineF Void

data RubySegment = RubySegment
  { rsBase :: [InlineNoRuby],
    rsReading :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

data NumberStyle = StyleKanji | StyleKanjiDigits | StyleTcy
  deriving stock (Eq, Show, Enum, Bounded)

-- | The vertical style of the numbers of a book ([numbers] vertical, golem-parser ADR 0011).
data VerticalNumbers
  = VerticalFixed !NumberStyle
  | -- | two digits or fewer in tate-chu-yoko, the others in the style
    VerticalAuto !NumberStyle
  deriving stock (Eq, Show)

-- | The style of a number in vertical text by the default of the book.
verticalStyleOf :: VerticalNumbers -> Integer -> NumberStyle
verticalStyleOf v n = case v of
  VerticalFixed s -> s
  VerticalAuto s
    | n >= 0 && n <= 99 -> StyleTcy
    | otherwise -> s

{- | The value of [numbers] vertical: kanji, kanji-digits, tcy, auto and
auto-digits; anything else is kanji (style.toml checks the value).
-}
verticalNumbersNamed :: Text -> VerticalNumbers
verticalNumbersNamed = \case
  "kanji-digits" -> VerticalFixed StyleKanjiDigits
  "tcy" -> VerticalFixed StyleTcy
  "auto" -> VerticalAuto StyleKanji
  "auto-digits" -> VerticalAuto StyleKanjiDigits
  _ -> VerticalFixed StyleKanji

data RefKind = RefNumber | RefTitle | RefPage
  deriving stock (Eq, Show, Enum, Bounded)

data IndexEntry = IndexEntry
  { ieTerms :: ![Text], -- one or two levels
    ieReadings :: ![Text],
    -- | a page, an end of a range, or a reference (docs/adr/0265)
    ieKind :: !IndexKind
  }
  deriving stock (Eq, Show)

{- | The kind of an index mark (docs/adr/0265): the page of the mark, the
begin or the end of a range, or a cross reference to the terms of another
entry, one level or two.
-}
data IndexKind
  = IndexPoint
  | IndexRangeBegin
  | IndexRangeEnd
  | IndexSee !SeeKind ![Text]
  deriving stock (Eq, Show)

{- | The kind of a cross reference (docs/adr/0265): by whether the entry
has pages (see without pages, see also with them), see, or see also. The
notation makes 'SeeAuto' alone; plugins and Emet functions make the others.
-}
data SeeKind = SeeAuto | SeeOnly | SeeAlso
  deriving stock (Eq, Ord, Show, Enum, Bounded)

{- | An item of a citation (docs/adr/0266): the key of the bibliography,
where in the work it cites, and the text before and after it. The fields
start with @cit@ not to meet 'ciKey' of a channel item.
-}
data CiteItem r = CiteItem
  { citKey :: !Text,
    citLocator :: !(Maybe Locator),
    citPrefix :: ![InlineF r],
    citSuffix :: ![InlineF r]
  }
  deriving stock (Eq, Show)

-- | An item of a key alone: no locator, no prefix, no suffix.
citeItem :: Text -> CiteItem r
citeItem k = CiteItem k Nothing [] []

-- | The prefix and the suffix of the items of a citation, in order: the inlines it holds.
citeInlines :: [CiteItem r] -> [InlineF r]
citeInlines = concatMap (\i -> citPrefix i <> citSuffix i)

-- | Where in the cited work (docs/adr/0266): the kind of the place and its value.
data Locator = Locator
  { locLabel :: !LocatorLabel,
    locValue :: !LocatorValue
  }
  deriving stock (Eq, Show)

-- | The 26 locator terms of CSL 1.0.2, one constructor each (docs/adr/0266).
data LocatorLabel
  = LocatorAppendix
  | LocatorArticleLocator
  | LocatorBook
  | LocatorCanon
  | LocatorChapter
  | LocatorColumn
  | LocatorElocation
  | LocatorEquation
  | LocatorFigure
  | LocatorFolio
  | LocatorIssue
  | LocatorLine
  | LocatorNote
  | LocatorOpus
  | LocatorPage
  | LocatorParagraph
  | LocatorPart
  | LocatorRule
  | LocatorSection
  | LocatorSubVerbo
  | LocatorSupplement
  | LocatorTable
  | LocatorTimestamp
  | LocatorTitle
  | LocatorVerse
  | LocatorVolume
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The CSL term of a kind of locator, as the CDDL writes it.
locatorLabelName :: LocatorLabel -> Text
locatorLabelName = \case
  LocatorAppendix -> "appendix"
  LocatorArticleLocator -> "article-locator"
  LocatorBook -> "book"
  LocatorCanon -> "canon"
  LocatorChapter -> "chapter"
  LocatorColumn -> "column"
  LocatorElocation -> "elocation"
  LocatorEquation -> "equation"
  LocatorFigure -> "figure"
  LocatorFolio -> "folio"
  LocatorIssue -> "issue"
  LocatorLine -> "line"
  LocatorNote -> "note"
  LocatorOpus -> "opus"
  LocatorPage -> "page"
  LocatorParagraph -> "paragraph"
  LocatorPart -> "part"
  LocatorRule -> "rule"
  LocatorSection -> "section"
  LocatorSubVerbo -> "sub-verbo"
  LocatorSupplement -> "supplement"
  LocatorTable -> "table"
  LocatorTimestamp -> "timestamp"
  LocatorTitle -> "title"
  LocatorVerse -> "verse"
  LocatorVolume -> "volume"

-- | The kind of locator of a CSL term.
locatorLabelNamed :: Text -> Maybe LocatorLabel
locatorLabelNamed t = lookup t [(locatorLabelName l, l) | l <- [minBound .. maxBound]]

{- | The value of a locator: a number, a range of numbers, or text
(docs/adr/0266). The IR checks a number is 0 or more, a range is not
reversed and text is not empty.
-}
data LocatorValue
  = LocNumber !Integer
  | LocRange !Integer !Integer
  | LocText !Text
  deriving stock (Eq, Show)

{- | An expression whose only free name is @doc@, evaluated at S1. S0
values have already been substituted.
-}
newtype DeferredExpr = DeferredExpr (AST.Located AST.Expr)
  deriving stock (Eq, Show)

-- | Forget that an inline may contain ruby, if it does not.
noRuby :: Inline -> Maybe InlineNoRuby
noRuby = \case
  Text s t -> Just (Text s t)
  Ruby {} -> Nothing
  Kenten s sh xs -> Kenten s sh <$> traverse noRuby xs
  Color s c xs -> Color s c <$> traverse noRuby xs
  CharStyle s c xs -> CharStyle s c <$> traverse noRuby xs
  Tcy s t -> Just (Tcy s t)
  Number s n st -> Just (Number s n st)
  Ref s k l -> Just (Ref s k l)
  Deferred s e -> Just (Deferred s e)
  -- the body of a note is set outside the base: no ruby inside ruby (docs/adr/0263)
  Note s n bs -> Just (Note s n bs)
  Sidenote s n bs -> Just (Sidenote s n bs)
  IndexMark s e -> Just (IndexMark s e)
  Cite s is -> Cite s <$> traverse itemNoRuby is
  ProofComment s t -> Just (ProofComment s t)
  LineBreak s -> Just (LineBreak s)
  Aki s a -> Just (Aki s a)
  ChannelItem s c -> Just (ChannelItem s c)
  Link s u xs -> Link s u <$> traverse noRuby xs
  Lang s l xs -> Lang s l <$> traverse noRuby xs
  Resolved s k l xs -> Resolved s k l <$> traverse noRuby xs

-- | An item of a citation whose prefix and suffix have no ruby (docs/adr/0266).
itemNoRuby :: CiteItem () -> Maybe (CiteItem Void)
itemNoRuby (CiteItem k l p q) = CiteItem k l <$> traverse noRuby p <*> traverse noRuby q

{- | The inlines of the paragraphs of the body of a note, in order
(docs/adr/0263); the other blocks, which the evaluation and Validate do
not let in, are left out.
-}
noteParagraphs :: [Block] -> [[Inline]]
noteParagraphs bs = [is | Block _ _ _ (Paragraph _ is) <- bs]

-- | The body of a note with the inlines of its paragraphs changed (docs/adr/0263).
mapNoteBody :: ([Inline] -> [Inline]) -> [Block] -> [Block]
mapNoteBody f = map $ \b -> case blockBody b of
  Paragraph st is -> b {blockBody = Paragraph st (f is)}
  _ -> b

-- | The body of a note of one paragraph without a paragraph style, at a span (docs/adr/0263).
noteBody :: SrcSpan -> [Inline] -> [Block]
noteBody sp is = [Block sp Nothing Nothing (Paragraph Nothing is)]

{- | A title as it is copied elsewhere in the book (the table of contents,
[ref-title]): without the inlines that tell a list where the text is,
index marks and channel items, at any depth (docs/adr/0145). A mark
stands only where it was written, so a list never points at a copy. The
notes are left as they are. A link gives its text without the link
(docs/adr ADR 0182), so that a copy that becomes a link holds no link.
A language span stays, with the rule inside it (docs/adr ADR 0187).
-}
withoutAnchors :: [InlineF r] -> [InlineF r]
withoutAnchors = concatMap $ \case
  IndexMark {} -> []
  ChannelItem {} -> []
  Ruby sp r segs -> [Ruby sp r [s {rsBase = withoutAnchors (rsBase s)} | s <- segs]]
  Kenten sp s xs -> [Kenten sp s (withoutAnchors xs)]
  Color sp c xs -> [Color sp c (withoutAnchors xs)]
  CharStyle sp c xs -> [CharStyle sp c (withoutAnchors xs)]
  Link _ _ xs -> withoutAnchors xs
  Lang sp l xs -> [Lang sp l (withoutAnchors xs)]
  -- a resolved reference stays a reference, as a language span (docs/adr/0215)
  Resolved sp k l xs -> [Resolved sp k l (withoutAnchors xs)]
  x -> [x]

-- | Whether an inline is a line break.
isLineBreak :: InlineF r -> Bool
isLineBreak = \case
  LineBreak _ -> True
  _ -> False

-- | The inlines of a paragraph split at its line breaks.
splitAtLineBreaks :: [InlineF r] -> [[InlineF r]]
splitAtLineBreaks is = case break isLineBreak is of
  (l, []) -> [l]
  (l, _ : rest) -> l : splitAtLineBreaks rest
