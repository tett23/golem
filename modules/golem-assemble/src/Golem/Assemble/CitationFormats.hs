-- | Whole-mark literal envelopes of root ADR 0475.
module Golem.Assemble.CitationFormats (joinBibliographyCitations) where

import Data.List (intercalate)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Citation (CitePiece (..), citationText)

joinBibliographyCitations :: Text -> Text -> Text -> [[CitePiece]] -> [CitePiece]
joinBibliographyCitations prefix suffix delimiter items = case filter (not . T.null . citationText) items of
  [] -> []
  present -> literal prefix <> intercalate (literal delimiter) present <> literal suffix
  where
    literal text = [CiteText text | not (T.null text)]
