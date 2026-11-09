{- | The patterns of the hyphenation of a language (docs/adr ADR 0187):
the patterns of the Latin words of a language span, from its language.
A language without patterns is not hyphenated by patterns; its explicit
hyphens and dashes still break (golem-layout ADR 0008).
-}
module Golem.Layout.Hyphenation.Languages
  ( patternsFor,
    exceptionPatterns,
    lookupTag,
    outsideSpanTag,
  )
where

import Control.Applicative ((<|>))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Layout.Hyphenation (Patterns, exceptionsOnly, overExceptions)
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

{- | The tag of the words outside a language span, whose patterns are those
of US English: the exceptions are looked up by it (docs/adr ADR 0272).
-}
outsideSpanTag :: Text
outsideSpanTag = "en-US"

{- | The patterns of a language span, or outside one (Nothing), with the
exceptions of a file and of a book over the bundled ones (docs/adr ADR
0272): each list is looked up by the tag of the language ('lookupTag'),
the file's words over the book's, the book's over the bundled ones. A
language without patterns with words in a list takes those words alone.
-}
exceptionPatterns :: Map Text [Text] -> Map Text [Text] -> Maybe Text -> Maybe Patterns
exceptionPatterns file book lang =
  let tag = fromMaybe outsideSpanTag lang
      fileWords = lookupTag file tag
      bookWords = lookupTag book tag
      over p = maybe p (`overExceptions` p) fileWords
   in case (patternsFor lang, bookWords, fileWords) of
        (Just p, b, _) -> Just (over (maybe p (`overExceptions` p) b))
        (Nothing, Nothing, Nothing) -> Nothing
        (Nothing, b, _) -> Just (over (exceptionsOnly (fromMaybe [] b)))

{- | The value of the key of a language tag by the lookup of RFC 4647 (its
section 3.4), the tags compared in lower case: the tag itself, then the
tag with its last subtag taken off, and so on; a single letter left at the
end goes with the subtag after it.
-}
lookupTag :: Map Text a -> Text -> Maybe a
lookupTag m tag = go (T.splitOn "-" (T.toLower tag))
  where
    keys = Map.fromList [(T.toLower k, v) | (k, v) <- Map.toAscList m]
    go = \case
      [] -> Nothing
      subtags -> Map.lookup (T.intercalate "-" subtags) keys <|> go (dropSingletons (init subtags))
    dropSingletons subtags = case reverse subtags of
      s : rest | T.length s == 1 -> reverse rest
      _ -> subtags
