{- | Page labels (docs/adr/0260): the value that points at a page. A
section is a run of pages that share the way their folios count; it
starts at the page the break before its file opened. The label of a page
is its place in the book, its number in its section and the notation of
its section. Cross-references, the table of contents, the index and the
lists of channels write a label by 'pageLabelInlines' alone.
-}
module Golem.Layout.PageLabel
  ( PageLabel (..),
    Section (..),
    plainLabel,
    pageLabelsOf,
    sectionFirstPages,
    pageLabelInlines,
    pageLabelText,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR (Inline, InlineF (..))
import Golem.Numerals.Notation (Notation, writeNumber)
import Golem.Syntax (SrcSpan)

data PageLabel = PageLabel
  { -- | the place of the page in the book, from 1: its place in the PDF
    plIndex :: !Int,
    -- | the number in its section
    plNumber :: !Integer,
    -- | the notation of its section; Nothing for a number of no notation, arabic included
    plNotation :: !(Maybe Notation)
  }
  deriving stock (Eq, Show)

{- | A section of the manifest (docs/adr/0260): the number of its first
page, Nothing to count on from the page before, and its notation,
Nothing for none (arabic included).
-}
data Section = Section
  { secStart :: !(Maybe Integer),
    secNotation :: !(Maybe Notation)
  }
  deriving stock (Eq, Show)

-- | The label of a page of a book without sections: its place, of no notation.
plainLabel :: Int -> PageLabel
plainLabel p = PageLabel p (toInteger p) Nothing

{- | The sections that start on each page, by page: the page the break
before each section opened, the sections in the order of the manifest.
-}
sectionFirstPages :: [(Int, Int)] -> Map Int [Int]
sectionFirstPages starts = Map.fromListWith (flip (<>)) [(p, [s]) | (s, p) <- starts]

{- | The labels of the pages 1 to @n@ (docs/adr/0260): the section of a
page is the last that starts on it or before it; the first page of a
section is numbered its start, or one more than the page before; any other
page one more than the page before. A page before every section counts
from 1 in no notation. Sections not in @sections@ are left out.
-}
pageLabelsOf :: Map Int Section -> Map Int [Int] -> Int -> Map Int PageLabel
pageLabelsOf sections firsts n = Map.fromList (zip [1 .. n] (go 1 0 Nothing))
  where
    go p prev notation
      | p > n = []
      | otherwise =
          let starting = [sec | s <- Map.findWithDefault [] p firsts, Just sec <- [Map.lookup s sections]]
              (number, notation') = case reverse starting of
                sec : _ -> (fromMaybe (prev + 1) (secStart sec), secNotation sec)
                [] -> (prev + 1, notation)
           in PageLabel p number notation' : go (p + 1) number notation'

{- | A label written as inlines at a span (docs/adr/0260): a label of no
notation is the 'Number' of its number, set in the notation of [numbers]
in vertical text and in Arabic numerals in horizontal text; a label of a
notation is the text its notation writes. A number its notation cannot
write (G07110 stops the PDF) is written in Arabic numerals.
-}
pageLabelInlines :: SrcSpan -> PageLabel -> [Inline]
pageLabelInlines sp l = case plNotation l of
  Nothing -> [Number sp (plNumber l) Nothing]
  Just _ -> [Text sp (pageLabelText l)]

{- | The text of a label: its number in its notation, Arabic numerals
without one, or for a number the notation cannot write.
-}
pageLabelText :: PageLabel -> Text
pageLabelText l = fromMaybe (T.pack (show (plNumber l))) (plNotation l >>= (`writeNumber` plNumber l))
