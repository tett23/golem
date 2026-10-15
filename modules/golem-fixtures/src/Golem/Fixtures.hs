{- | Converters of the public-domain texts of the test fixtures into Golem
source (docs/adr/0023, docs/adr/0026). scripts/fixtures/fetch-public-domain.sh
runs them through the golem-fixtures executable.
-}
module Golem.Fixtures
  ( Converter (..),
    TextOptions (..),
    defaultTextOptions,
    converterNamed,
    parseArgs,
    convertBytes,
  )
where

import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8', encodeUtf8)
import Golem.Fixtures.Aozora (AozoraMode (..), convertAozora, convertAozoraWith)
import Golem.Fixtures.Gutenberg (convertPlay)
import Golem.Fixtures.GutenbergText (TextOptions (..), convertText, defaultTextOptions)
import Golem.Fixtures.Python (universalNewlines)
import Text.Read (readMaybe)

data Converter
  = -- | a play of the Project Gutenberg Cambridge edition of Shakespeare
    GutenbergPlay
  | -- | a text of Aozora Bunko, ruby edition, in UTF-8
    Aozora
  | -- | another text of Project Gutenberg (docs/adr/0026)
    GutenbergText TextOptions
  | -- | Aozora Bunko prose with its indents and more annotations (docs/adr/0026)
    AozoraProse
  | -- | Aozora Bunko verse, stanza by stanza (docs/adr/0026)
    AozoraVerse
  deriving stock (Eq, Show)

-- | The converter of a subcommand name, with no options.
converterNamed :: String -> Maybe Converter
converterNamed = \case
  "gutenberg-play" -> Just GutenbergPlay
  "aozora" -> Just Aozora
  "gutenberg-text" -> Just (GutenbergText defaultTextOptions)
  "aozora-prose" -> Just AozoraProse
  "aozora-verse" -> Just AozoraVerse
  _ -> Nothing

{- | The converter, the input and the output of the command line: the
subcommand, then its options (gutenberg-text only), then INPUT and OUTPUT.
-}
parseArgs :: [String] -> Either String (Converter, FilePath, FilePath)
parseArgs = \case
  name : rest | Just conv <- converterNamed name -> case conv of
    GutenbergText opts -> textArgs opts rest
    _ -> case rest of
      [input, output] | not (isOption input) -> Right (conv, input, output)
      _ -> Left (name <> " takes INPUT.txt OUTPUT.gm and no options")
  _ -> Left "no converter: gutenberg-play, gutenberg-text, aozora, aozora-prose or aozora-verse"
  where
    isOption = (== "--") . take 2
    textArgs opts = \case
      [input, output] | not (isOption input), not (isOption output) -> Right (GutenbergText opts, input, output)
      "--verse" : r -> textArgs opts {optVerse = True} r
      "--speakers" : r -> textArgs opts {optSpeakers = True} r
      "--two-columns" : r -> textArgs opts {optTwoColumns = True} r
      "--numbered-headings" : r -> textArgs opts {optNumberedHeadings = True} r
      "--bold-equals" : r -> textArgs opts {optBoldEquals = True} r
      "--heading" : v : r | enough r -> textArgs opts {optHeadings = optHeadings opts <> [T.pack v]} r
      "--start" : v : r | enough r -> textArgs opts {optStart = Just (T.pack v)} r
      "--end" : v : r | enough r -> textArgs opts {optEnd = Just (T.pack v)} r
      "--notes" : v : r | enough r -> textArgs opts {optNotes = Just (T.pack v)} r
      "--caps-heading" : v : r
        | enough r -> case readMaybe v of
            Just n | n >= 1 && n <= 6 -> textArgs opts {optCapsHeading = Just n} r
            _ -> Left ("--caps-heading takes a level from 1 to 6: " <> v)
      o : _ | isOption o -> Left ("an unknown option or one without its value: " <> o)
      _ -> Left "gutenberg-text takes [OPTION...] INPUT.txt OUTPUT.gm"
    -- an option's value must leave INPUT and OUTPUT after it
    enough r = length r >= 2

{- | Reads the input as UTF-8 text with its newlines made @\\n@, converts it,
and writes the Golem source as UTF-8.
-}
convertBytes :: Converter -> ByteString -> Either String ByteString
convertBytes conv bytes = do
  src <- first (const "the input is not UTF-8") (decodeUtf8' bytes)
  encodeUtf8 <$> run conv (universalNewlines src)
  where
    run GutenbergPlay = convertPlay
    run Aozora = convertAozora
    run (GutenbergText opts) = convertText opts
    run AozoraProse = convertAozoraWith Prose
    run AozoraVerse = convertAozoraWith Verse
