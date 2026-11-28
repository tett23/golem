{- | Citation occurrences and caller-resolved formatting in S1 notes
(root ADR 0470 I5). The note identity
and the occurrence within it remain distinct even when a plugin reuses
one source span and identical citation items. This inventory neither
chooses the first note of a work nor changes documents or outputs.
-}
module Golem.Assemble.BibliographyNoteContext
  ( NoteCitationContext (..),
    NoteCitationOccurrence (..),
    bibliographyNoteCitations,
    formatBibliographyNoteCitations,
    citationOffsets,
    citationCount,
  )
where

import Control.Monad (void)
import Data.Bifunctor (first)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Assemble (NoteChannelKind (..), NoteCitationContext (..))
import Golem.Assemble.BibliographyCitations (BibliographyCitationRecord, formatBibliographyCitationMark)
import Golem.Assemble.BibliographyStyle (BibliographyStyle)
import Golem.Doc.Citation (CitePiece, citationCount, citationOffsets)
import Golem.Doc.IR
import Golem.Syntax (SrcSpan)

data NoteCitationOccurrence = NoteCitationOccurrence
  { ncoContext :: !NoteCitationContext,
    ncoSpan :: !SrcSpan,
    ncoItems :: ![CiteItem ()]
  }
  deriving stock (Eq, Show)

{- | Build the consumer table from already numbered S1 note occurrences.
The caller explicitly resolves each record's language, list number, year
suffix and initial/subsequent use, including the chosen first-note target.
Each item is resolved with its zero-based position in the original mark,
so identical items can receive distinct explicit formatting uses.
Formatting may sort the pieces, but lookup retains the original item order.
The first resolver or formatter error retains its structural occurrence;
no partial table is returned. This pass neither generates notes nor chooses
between note channels, and it does not connect the normal CLI's note mode.
-}
formatBibliographyNoteCitations :: BibliographyStyle d -> (NoteCitationOccurrence -> Int -> CiteItem () -> Either Text (BibliographyCitationRecord d)) -> [Document] -> Either (NoteCitationOccurrence, Text) (Map.Map NoteCitationContext (SrcSpan, [CiteItem ()], [CitePiece]))
formatBibliographyNoteCitations global resolve documents = Map.fromList <$> traverse format (bibliographyNoteCitations documents)
  where
    format occurrence = first (occurrence,) $ do
      values <- traverse (\(index, item) -> fmap (item,) (resolve occurrence index item)) (zip [0 ..] (ncoItems occurrence))
      pieces <- formatBibliographyCitationMark global values
      pure (ncoContext occurrence, (ncoSpan occurrence, ncoItems occurrence, pieces))

-- | Read already numbered S1 documents, preserving document order.
bibliographyNoteCitations :: [Document] -> [NoteCitationOccurrence]
bibliographyNoteCitations documents =
  [ if Set.size (Map.findWithDefault Set.empty (identity context) documentIndices) > 1
      then entry {ncoContext = NoteCitationContextInDocument (nccNoteSpan context) (nccChannel context) (nccNumber context) (nccOccurrence context) documentIndex}
      else entry
  | (documentIndex, entry) <- entries,
    let context = ncoContext entry
  ]
  where
    entries = [(documentIndex, entry) | (documentIndex, Document _ blocks) <- zip [0 ..] documents, entry <- concatMap notesInlines (blockLists blocks)]
    identity context = (nccNoteSpan context, nccChannel context, nccNumber context)
    documentIndices = Map.fromListWith Set.union [(identity (ncoContext entry), Set.singleton documentIndex) | (documentIndex, entry) <- entries]
    notesInlines :: [InlineF r] -> [NoteCitationOccurrence]
    notesInlines = concatMap noteInline
    noteInline :: InlineF r -> [NoteCitationOccurrence]
    noteInline = \case
      Note sp n _ blocks -> inNote sp FootnoteChannel n blocks
      Sidenote sp n _ blocks -> inNote sp SidenoteChannel n blocks
      Endnote sp n _ blocks -> inNote sp EndnoteChannel n blocks
      Ruby _ _ segments -> concatMap (notesInlines . rsBase) segments
      Kenten _ _ xs -> notesInlines xs
      Color _ _ xs -> notesInlines xs
      CharStyle _ _ xs -> notesInlines xs
      Link _ _ xs -> notesInlines xs
      Lang _ _ xs -> notesInlines xs
      Resolved _ _ _ xs -> notesInlines xs
      _ -> []
    inNote sp channel number blocks =
      [NoteCitationOccurrence (NoteCitationContext sp channel number occurrence) at items | (occurrence, (at, items)) <- zip [0 ..] (concatMap citationsInlines (blockLists blocks))]
        <> concatMap notesInlines (blockLists blocks)

-- The inventory's order is the written structural order, not a placement
-- order. No changes to the shared legacy collectors are needed.
blockLists :: [Block] -> [[Inline]]
blockLists = concatMap (bodyLists . blockBody)
  where
    bodyLists = \case
      Paragraph _ xs -> [xs]
      Heading _ _ xs -> [xs]
      BulletList items -> concatMap (blockLists . itemBlocks) items
      OrderedList items -> concatMap (blockLists . itemBlocks) items
      DefList groups -> concat [terms <> concatMap blockLists definitions | DefGroup terms definitions <- groups]
      TableBlock table -> [fromMaybe [] (tableCaption table)] <> tableHeader table <> concat (tableRows table)
      CodeBlock code -> [fromMaybe [] (codeCaption code)]
      FigureBlock figure -> blockLists (figCaption figure)
      FrameBlock _ blocks -> blockLists blocks
      _ -> []

citationsInlines :: [InlineF r] -> [(SrcSpan, [CiteItem ()])]
citationsInlines = concatMap citation
  where
    citation :: InlineF r -> [(SrcSpan, [CiteItem ()])]
    citation = \case
      Cite sp items -> [(sp, map void items)]
      Ruby _ _ segments -> concatMap (citationsInlines . rsBase) segments
      Kenten _ _ xs -> citationsInlines xs
      Color _ _ xs -> citationsInlines xs
      CharStyle _ _ xs -> citationsInlines xs
      Link _ _ xs -> citationsInlines xs
      Lang _ _ xs -> citationsInlines xs
      Resolved _ _ _ xs -> citationsInlines xs
      -- A nested note, if present before validation, has its own context.
      _ -> []
