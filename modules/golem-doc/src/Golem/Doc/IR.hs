{- | The semantic IR (golem-doc ADR 0001): evaluated content with no
geometry. The canonical definition is schema/golem-doc.cddl; these types
mirror it and are checked against it by round-trip tests.
-}
module Golem.Doc.IR
  ( abiVersion,
    Document (..),
    Block (..),
    BlockBody (..),
    BreakKind (..),
    ListItem (..),
    itemNumbers,
    DefGroup (..),
    Alignment (..),
    HeadingAttrs (..),
    noHeadingAttrs,
    ChannelBlock (..),
    Figure (..),
    Wrap (..),
    InlineF (..),
    AkiAmount (..),
    Inline,
    InlineNoRuby,
    RubySegment (..),
    NumberStyle (..),
    RefKind (..),
    IndexEntry (..),
    DeferredExpr (..),
    noRuby,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Void (Void)
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Span

-- | The ABI version shared with plugins. Bump on any change to the IR.
abiVersion :: Int
abiVersion = 5

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
  | CodeBlock (Maybe Text) Text
  | FigureBlock Figure
  | ChannelOutput ChannelBlock
  | -- | a forced break before what follows (docs/adr ADR 0017)
    ForcedBreak !BreakKind
  deriving stock (Eq, Show)

-- | The kind of a forced break (docs/adr ADR 0017).
data BreakKind = BreakPage | BreakRecto | BreakVerso | BreakColumn
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data ListItem = ListItem
  { itemNumber :: !(Maybe Integer), -- explicit @number
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
    go next (ListItem n _ : rest) = let k = fromMaybe next n in k : go (k + 1) rest

data DefGroup = DefGroup
  { dgTerms :: [[Inline]],
    dgDefs :: [[Block]]
  }
  deriving stock (Eq, Show)

data Alignment = AlignDefault | AlignLeft | AlignCenter | AlignRight
  deriving stock (Eq, Show, Enum, Bounded)

data HeadingAttrs = HeadingAttrs
  { haTocTitle :: !(Maybe [Inline]),
    haNumber :: !(Maybe Integer),
    haNoNumber :: !Bool,
    haNoToc :: !Bool
  }
  deriving stock (Eq, Show)

noHeadingAttrs :: HeadingAttrs
noHeadingAttrs = HeadingAttrs Nothing Nothing False False

data ChannelBlock = TocOutput !Int | IndexOutput | BibliographyOutput
  deriving stock (Eq, Show)

data Wrap = WrapStart | WrapEnd
  deriving stock (Eq, Show, Enum, Bounded)

data Figure = Figure
  { figSource :: !Text,
    figWeb :: !(Maybe Text),
    figAlt :: !Text,
    figWrap :: !(Maybe Wrap),
    figWidth :: !(Maybe Text),
    figCaption :: ![Block]
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
