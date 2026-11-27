{- | Prepare note citations before S1 assigns the actual note numbers.
The style has already been selected using the book language (root ADR 0475).
Writer notes are opaque here: their citations stay in their existing bodies.
This pass does not render citations or guess a first note's display number.
-}
module Golem.Assemble.BibliographyNotes (prepareBibliographyNotes) where

import Control.Monad (void)
import Golem.Assemble.BibliographyStyle
import Golem.Doc.IR

prepareBibliographyNotes :: BibliographyStyle d -> [Document] -> [Document]
prepareBibliographyNotes style
  | bsCitationMode style /= Just "note" = id
  | otherwise = map document
  where
    document d = d {docBlocks = map block (docBlocks d)}
    block b = b {blockBody = body (blockBody b)}
    body = \case
      Paragraph st xs -> Paragraph st (map inline xs)
      Heading level attrs xs -> Heading level attrs (map inline xs)
      BulletList items -> BulletList (map item items)
      OrderedList items -> OrderedList (map item items)
      DefList groups -> DefList [DefGroup (map (map inline) terms) (map (map block) definitions) | DefGroup terms definitions <- groups]
      TableBlock table -> TableBlock table {tableCaption = map inline <$> tableCaption table, tableHeader = map (map inline) (tableHeader table), tableRows = map (map (map inline)) (tableRows table)}
      CodeBlock code -> CodeBlock code {codeCaption = map inline <$> codeCaption code}
      FigureBlock figure -> FigureBlock figure {figCaption = map block (figCaption figure)}
      FrameBlock name blocks -> FrameBlock name (map block blocks)
      other -> other
    item entry = entry {itemBlocks = map block (itemBlocks entry)}
    inline :: InlineF r -> InlineF r
    inline = \case
      Cite sp items ->
        let citation = Cite sp (map void items)
            constructor = if bsNoteChannel style == Just "endnote" then Endnote else Note
         in constructor sp 0 Nothing (noteBody sp [citation])
      Note sp number label blocks -> Note sp number label blocks
      Sidenote sp number label blocks -> Sidenote sp number label blocks
      Endnote sp number label blocks -> Endnote sp number label blocks
      Ruby sp annotation segments -> Ruby sp annotation [segment {rsBase = map inline (rsBase segment)} | segment <- segments]
      Kenten sp shape xs -> Kenten sp shape (map inline xs)
      Color sp color xs -> Color sp color (map inline xs)
      CharStyle sp name xs -> CharStyle sp name (map inline xs)
      Lang sp language xs -> Lang sp language (map inline xs)
      Resolved sp kind target xs -> Resolved sp kind target (map inline xs)
      other -> other
