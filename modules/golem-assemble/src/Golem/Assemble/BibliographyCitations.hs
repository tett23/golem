-- | Format one mark from already resolved records; first-note selection belongs to the caller.
module Golem.Assemble.BibliographyCitations
  ( BibliographyCitationUse (..),
    BibliographyCitationRecord (..),
    formatBibliographyCitationMark,
  )
where

import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Golem.Assemble (inlineText)
import Golem.Assemble.BibliographyNames qualified as Names
import Golem.Assemble.BibliographyRecords
import Golem.Assemble.BibliographySort (authorSortKey)
import Golem.Assemble.BibliographyStyle
import Golem.Assemble.CitationFormats (joinBibliographyCitations)
import Golem.Bibliography (CslDate (..), CslName (..))
import Golem.Bibliography.Csl (CslPerson (..), CslRecord, recordDate, recordNames)
import Golem.Doc.Citation (CitePiece (..))
import Golem.Doc.IR (CiteItem (..), citationYearOnly)
import Golem.Syntax (SrcSpan)

data BibliographyCitationUse
  = BibliographyInitialCitation
  | BibliographySubsequentCitation !Integer
  | BibliographyDeferredSubsequentCitation !SrcSpan !Int
  deriving stock (Eq, Show)

data BibliographyCitationRecord d = BibliographyCitationRecord
  { bcrRecord :: !CslRecord,
    bcrStyle :: !(BibliographyStyle d),
    bcrNumber :: !Int,
    bcrYearSuffix :: !Text,
    bcrUse :: !BibliographyCitationUse
  }

{- | The caller resolves language overlays, assigned numbers, year suffixes and
the use of each citation. This function keeps those choices with the item
through sorting, then applies its literal affixes and the book's envelope.
-}
formatBibliographyCitationMark :: BibliographyStyle d -> [(CiteItem (), BibliographyCitationRecord d)] -> Either Text [CitePiece]
formatBibliographyCitationMark global input = do
  ordered <- case bsCitationSort global of
    Just "year" -> pure (sortOn citationYear input)
    Just "author-year" -> do
      keys <- traverse citationAuthorYear input
      pure (map snd (sortOn fst (zip keys input)))
    _ -> pure input
  pieces <- traverse citation ordered
  pure (joinBibliographyCitations (fromMaybe "" (bsCitationPrefix global)) (fromMaybe "" (bsCitationSuffix global)) (fromMaybe "" (bsCitationDelimiter global)) pieces)
  where
    citationYear (_, value) = case recordDate "issued" (bcrRecord value) of
      Just (DateParts year _ _) -> Just year
      _ -> Nothing
    citationAuthorYear pair@(_, value) = do
      separator <- maybe (Left "names.author.part-delimiter がありません") Right (Map.lookup "author" (bsNames (bcrStyle value)) >>= bnPartDelimiter)
      let (person, reading) = case recordNames "author" (bcrRecord value) of
            CslPerson name key : _ -> (Just (case name of PersonalName family given -> Names.PersonalName family given; LiteralName literal -> Names.LiteralName literal), key)
            [] -> (Nothing, Nothing)
      pure (authorSortKey separator reading person, citationYear pair)
    citation (item, value) = do
      let suffix = bcrYearSuffix value
          style = bcrStyle value
          ordinary = if citationYearOnly item then formatBibliographyYearCitationWithSuffix suffix else formatBibliographyCitationWithSuffix suffix
          formatter
            | bsCitationMode style /= Just "note" = ordinary
            | otherwise = case bcrUse value of
                BibliographyInitialCitation -> ordinary
                BibliographySubsequentCitation firstNote -> formatBibliographySubsequentCitationWithSuffix suffix firstNote
                BibliographyDeferredSubsequentCitation target number -> formatBibliographyDeferredSubsequentCitationWithSuffix suffix (target, number)
      pieces <- formatter style (bcrNumber value) (citLocator item) (bcrRecord value)
      let literal inlines = [CiteText text | let text = foldMap inlineText inlines, text /= ""]
      pure (literal (citPrefix item) <> pieces <> literal (citSuffix item))
