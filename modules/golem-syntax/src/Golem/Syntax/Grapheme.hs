{- | Unicode 17 extended grapheme boundaries, using the vendored libgrapheme
already used by manuscript statistics (root ADR 0355, 0380).
-}
module Golem.Syntax.Grapheme (graphemeClusters) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Foreign.C.String (CString)
import Foreign.C.Types (CSize (..))
import System.IO.Unsafe (unsafePerformIO)

foreign import ccall unsafe "grapheme_next_character_break_utf8" nextCharacter :: CString -> CSize -> IO CSize

{- | The C operation only reads immutable UTF-8 bytes; each returned length is
consumed while its byte buffer is alive. Empty text has no clusters.
-}
graphemeClusters :: Text -> [Text]
graphemeClusters text = unsafePerformIO (go (TE.encodeUtf8 text))
  where
    go bytes
      | BS.null bytes = pure []
      | otherwise = do
          n <- BS.useAsCStringLen bytes $ \(ptr, len) -> fromIntegral <$> nextCharacter ptr (fromIntegral len)
          let (first, rest) = BS.splitAt n bytes
          remaining <- go rest
          pure (TE.decodeUtf8 first : remaining)
{-# NOINLINE graphemeClusters #-}
