{- | Converters of the public-domain texts of the test fixtures into Golem
source (docs/adr/0023). scripts/fixtures/fetch-public-domain.sh runs them
through the golem-fixtures executable.
-}
module Golem.Fixtures
  ( Converter (..),
    converterNamed,
    convertBytes,
  )
where

import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.Text.Encoding (decodeUtf8', encodeUtf8)
import Golem.Fixtures.Aozora (convertAozora)
import Golem.Fixtures.Gutenberg (convertPlay)
import Golem.Fixtures.Python (universalNewlines)

data Converter
  = -- | a play of the Project Gutenberg Cambridge edition of Shakespeare
    GutenbergPlay
  | -- | a text of Aozora Bunko, ruby edition, in UTF-8
    Aozora
  deriving stock (Eq, Show)

-- | The converter of a subcommand name.
converterNamed :: String -> Maybe Converter
converterNamed = \case
  "gutenberg-play" -> Just GutenbergPlay
  "aozora" -> Just Aozora
  _ -> Nothing

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
