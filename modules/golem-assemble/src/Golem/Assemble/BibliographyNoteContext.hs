{- | Citation occurrences in S1 notes (root ADR 0470 I5). The note identity
and the occurrence within it remain distinct even when a plugin reuses
one source span and identical citation items. This inventory neither
chooses the first note of a work nor changes documents or outputs.
-}
module Golem.Assemble.BibliographyNoteContext
  ( NoteCitationContext (..),
    NoteCitationOccurrence (..),
    bibliographyNoteCitations,
    citationOffsets,
    citationCount,
  )
where

import Control.Monad (void)
import Data.Maybe (fromMaybe)
import Golem.Assemble (NoteChannelKind (..), NoteCitationContext (..))
import Golem.Doc.Citation (citationCount, citationOffsets)
import Golem.Doc.IR
import Golem.Syntax (SrcSpan)

data NoteCitationOccurrence = NoteCitationOccurrence
  { ncoContext :: !NoteCitationContext,
    ncoSpan :: !SrcSpan,
    ncoItems :: ![CiteItem ()]
  }
  deriving stock (Eq, Show)

-- | Read already numbered S1 documents, preserving document order.
bibliographyNoteCitations :: [Document] -> [NoteCitationOccurrence]
bibliographyNoteCitations documents =
  concat [concatMap notesInlines (blockLists blocks) | Document _ blocks <- documents]
  where
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
