-- | Byte strings in the tests (docs/adr ADR 0087).
module Golem.TestSupport.Bytes
  ( hex,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS

-- | The bytes as lower-case hexadecimal digits, two a byte.
hex :: ByteString -> String
hex = concatMap (\w -> [digits !! fromIntegral (w `div` 16), digits !! fromIntegral (w `mod` 16)]) . BS.unpack
  where
    digits = "0123456789abcdef"
