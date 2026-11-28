-- | Page ranges with an explicit format and delimiter (root ADR 0470).
module Golem.Assemble.BibliographyRanges
  ( PageRangeFormat (..),
    formatBibliographyRange,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Numeric.Natural (Natural)

data PageRangeFormat = FullPageRange | MinimalPageRange
  deriving stock (Eq, Show)

-- | Format already parsed endpoints; this function supplies no style defaults.
formatBibliographyRange :: PageRangeFormat -> Text -> Natural -> Natural -> Text
formatBibliographyRange mode delimiter first lastPage = start <> delimiter <> finish
  where
    start = T.pack (show first)
    end = T.pack (show lastPage)
    finish
      | mode == MinimalPageRange,
        first < lastPage,
        T.length start == T.length end,
        Just (_, _, remainder) <- T.commonPrefixes start end,
        not (T.null remainder) =
          remainder
      | otherwise = end
