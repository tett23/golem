{- | The patterns of the hyphenation of a language (docs/adr ADR 0187, ADR
0276): the patterns of the Latin words of a language span, from its
language, and those of the words outside a span, from the language of the
book. A language without patterns is not hyphenated by patterns; its
explicit hyphens and dashes still break (golem-layout ADR 0008).
-}
module Golem.Layout.Hyphenation.Languages
  ( patternsFor,
    patternsNameFor,
    exceptionPatterns,
    lookupTag,
    outsideSpanTag,
  )
where

import Control.Applicative ((<|>))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Layout.Hyphenation (Patterns, exceptionsOnly, overExceptions)
import Golem.Layout.Hyphenation.De1996 (german)
import Golem.Layout.Hyphenation.EnGb (englishGB)
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Hyphenation.Es (spanish)
import Golem.Layout.Hyphenation.Fr (french)
import Golem.Layout.Hyphenation.It (italian)
import Golem.Layout.Hyphenation.Nl (dutch)
import Golem.Layout.Hyphenation.Pt (portuguese)

{- | The bundled patterns by the key of a language tag (docs/adr ADR 0276,
its section 2), each with the name of its file of hyph-utf8: de and every
tag under it take the reformed orthography of 1996.
-}
bundled :: Map Text (Text, Patterns)
bundled =
  Map.fromList
    [ ("en", ("en-us", englishUS)),
      ("en-us", ("en-us", englishUS)),
      ("en-gb", ("en-gb", englishGB)),
      ("fr", ("fr", french)),
      ("de", ("de-1996", german)),
      ("es", ("es", spanish)),
      ("it", ("it", italian)),
      ("pt", ("pt", portuguese)),
      ("nl", ("nl", dutch))
    ]

{- | The bundled patterns of a tag by the lookup of RFC 4647, with the name
of their file; outside a span (Nothing) those of US English.
-}
bundledFor :: Maybe Text -> Maybe (Text, Patterns)
bundledFor = lookupTag bundled . fromMaybe "en-US"

{- | The patterns of a language span, or outside one in a book of no
bundled language (Nothing): the tag looked up in the table of the bundled
patterns, none for a language not in it.
-}
patternsFor :: Maybe Text -> Maybe Patterns
patternsFor = fmap snd . bundledFor

-- | The name of the hyph-utf8 file of the patterns of 'patternsFor' (@en-us@, @de-1996@).
patternsNameFor :: Maybe Text -> Maybe Text
patternsNameFor = fmap fst . bundledFor

{- | The tag of the words outside a language span, by the language of the
book (docs/adr ADR 0276): the language of the book when the table of the
bundled patterns has it, en-US otherwise (ja, zh, none). Their patterns
and their exceptions are looked up by it (docs/adr ADR 0272).
-}
outsideSpanTag :: Text -> Text
outsideSpanTag book
  | isJust (lookupTag bundled book) = book
  | otherwise = "en-US"

{- | The patterns of a language span, or outside one (Nothing) in a book of
a language, with the exceptions of a file and of a book over the bundled
ones (docs/adr ADR 0272): each list is looked up by the tag of the
language ('lookupTag'), the file's words over the book's, the book's over
the bundled ones. A language without patterns with words in a list takes
those words alone.
-}
exceptionPatterns :: Text -> Map Text [Text] -> Map Text [Text] -> Maybe Text -> Maybe Patterns
exceptionPatterns bookLang file book lang =
  let tag = fromMaybe (outsideSpanTag bookLang) lang
      fileWords = lookupTag file tag
      bookWords = lookupTag book tag
      over p = maybe p (`overExceptions` p) fileWords
   in case (patternsFor (Just tag), bookWords, fileWords) of
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
