{- | The patterns of the hyphenation of a language (docs/adr ADR 0187):
the patterns of the Latin words of a language span, from its language.
A language without patterns is not hyphenated by patterns; its explicit
hyphens and dashes still break (golem-layout ADR 0008).
-}
module Golem.Layout.Hyphenation.Languages
  ( patternsFor,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Layout.Hyphenation (Patterns)
import Golem.Layout.Hyphenation.EnUs (englishUS)

{- | The patterns of a language span, or outside one (Nothing): US English
for a primary subtag en and outside a span, none for every other
language. More patterns go here (the roadmap: v1.0.0).
-}
patternsFor :: Maybe Text -> Maybe Patterns
patternsFor = \case
  Nothing -> Just englishUS
  Just l
    | T.toLower (T.takeWhile (/= '-') l) == "en" -> Just englishUS
    | otherwise -> Nothing
