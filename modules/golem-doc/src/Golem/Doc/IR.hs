{- | The semantic IR (golem-doc ADR 0001): evaluated content with no
geometry. The canonical definition is schema/golem-doc.cddl; these types
mirror it and are checked against it by round-trip tests.
-}
module Golem.Doc.IR
  ( abiVersion,
    inInt64,
    Document (..),
    Block (..),
    BlockBody (..),
    BreakKind (..),
    PageControl (..),
    ListItem (..),
    itemNumbers,
    DefGroup (..),
    Alignment (..),
    HeadingAttrs (..),
    noHeadingAttrs,
    ChannelBlock (..),
    ChannelItem (..),
    Code (..),
    CodeLine (..),
    DiffMark (..),
    codeText,
    Figure (..),
    Wrap (..),
    InlineF (..),
    AkiAmount (..),
    Inline,
    InlineNoRuby,
    RubySegment (..),
    NumberStyle (..),
    VerticalNumbers (..),
    verticalStyleOf,
    verticalNumbersNamed,
    RefKind (..),
    IndexEntry (..),
    DeferredExpr (..),
    noRuby,
    isLineBreak,
    splitAtLineBreaks,
  )
where

import Data.Int (Int64)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Void (Void)
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Span
import Numeric.Natural (Natural)

{- | Whether an integer is within the CDDL @int64@ (golem-doc ADR 0006):
from -2^63 to 2^63 - 1, the range of the integers of the IR. It is the
range of 'Int' too.
-}
inInt64 :: Integer -> Bool
inInt64 n = n >= toInteger (minBound :: Int) && n <= toInteger (maxBound :: Int)

{- | The ABI version shared with plugins. It goes up by one when the ABI
changes after the release that has it, and at most once between two
releases (docs/adr ADR 0052); scripts/ci/abi-version.sh checks it.
-}
abiVersion :: Int
abiVersion = 8

data Document = Document
  { docFile :: !FileId,
    docBlocks :: ![Block]
  }
  deriving stock (Eq, Show)

data Block = Block
  { blockSpan :: !SrcSpan,
    blockLabel :: !(Maybe Text),
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
  | Table [Alignment] [[Inline]] [[[Inline]]]
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
data PageControl = NoBreak | NeedLines !Int | AdjustLines !Int
  deriving stock (Eq, Show)

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
    codeLines :: ![CodeLine]
  }
  deriving stock (Eq, Show)

-- | The mark of a line of a diff.
data DiffMark = DiffAdded | DiffRemoved | DiffContext
  deriving stock (Eq, Show, Enum, Bounded)

{- | A line of code: its text without the diff mark and the callouts, its
number (Nothing for a removed line), its diff mark (Nothing when the code
is not a diff), whether it is highlighted, and its callouts.
-}
data CodeLine = CodeLine
  { clText :: !Text,
    clNumber :: !(Maybe Natural),
    clDiff :: !(Maybe DiffMark),
    clHighlight :: !Bool,
    clCallouts :: ![Int]
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
    figRotate :: !Bool
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
  | Note !SrcSpan !Int [InlineF r]
  | Sidenote !SrcSpan !Int [InlineF r]
  | IndexMark !SrcSpan IndexEntry
  | Cite !SrcSpan !Text
  | ProofComment !SrcSpan Text
  | -- | a forced line break, only between the inlines at the top of a paragraph (docs/adr ADR 0005)
    LineBreak !SrcSpan
  | -- | a fixed space written with [aki] (docs/adr ADR 0019)
    Aki !SrcSpan !AkiAmount
  | -- | an item of a channel of a plugin (golem-doc ADR 0007)
    ChannelItem !SrcSpan !ChannelItem
  deriving stock (Eq, Show)

-- | The amount of an [aki]: in zw (the size of the type there), or absolute in sp.
data AkiAmount = AkiZw !Rational | AkiAbs !Integer
  deriving stock (Eq, Show)

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
    ieReadings :: ![Text]
  }
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
  Note s n xs -> Note s n <$> traverse noRuby xs
  Sidenote s n xs -> Sidenote s n <$> traverse noRuby xs
  IndexMark s e -> Just (IndexMark s e)
  Cite s k -> Just (Cite s k)
  ProofComment s t -> Just (ProofComment s t)
  LineBreak s -> Just (LineBreak s)
  Aki s a -> Just (Aki s a)
  ChannelItem s c -> Just (ChannelItem s c)

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
