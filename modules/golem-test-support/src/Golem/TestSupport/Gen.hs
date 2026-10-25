-- | Generators of the property tests (docs/adr ADR 0087).
module Golem.TestSupport.Gen
  ( genText,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog (Gen)
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range

{- | Text of 0 to 80 characters mixing ASCII, Japanese, a 4-byte emoji and
newlines, so that byte, code point and UTF-16 units all differ.
-}
genText :: Gen Text
genText =
  T.pack
    <$> Gen.list
      (Range.linear 0 80)
      (Gen.element ("ab 漢字かな\r\n😀𠮷x" :: String))
