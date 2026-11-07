-- | The helpers that the tests of golem-project share (docs/adr/0173).
module Support (offsetOf) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE

-- | The byte offset of the first @needle@ in @src@ (its length when there is none).
offsetOf :: Text -> Text -> Int
offsetOf src needle = BS.length (TE.encodeUtf8 (fst (T.breakOn needle src)))
