{- | The glyph codes and the xref offsets written with Builder instead of
Text.Printf (docs/adr ADR 0254). The bytes must stay those printf wrote:
"%04X" for a glyph code, "%010d" for an offset.
-}
module HexSpec (tests) where

import Data.ByteString.Builder qualified as B
import Data.ByteString.Lazy.Char8 qualified as BLC
import Data.Word (Word16)
import Golem.Pdf.Number (decimal10, hex4)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)
import Text.Printf (printf)

built :: B.Builder -> String
built = BLC.unpack . B.toLazyByteString

{- | The largest offset that printf "%010d" writes in ten digits, within
'Int' (2^31 - 1 on wasm32, docs/adr ADR 0300).
-}
maxOffset :: Int
maxOffset = fromInteger (min 9999999999 (toInteger (maxBound :: Int)))

tests :: TestTree
tests =
  testGroup
    "glyph codes and xref offsets without printf (ADR 0254)"
    [ testCase "I1 hex4 g is printf \"%04X\" g for every g from 0 to 0xFFFF" $
        let wrong = [g | g <- [minBound .. maxBound :: Word16], built (hex4 g) /= printf "%04X" g]
         in take 5 wrong @?= [],
      testCase "I1 the boundary glyph codes" $
        [built (hex4 g) | g <- [0, 1, 0x000F, 0x0010, 0x0FFF, 0x1000, 0xFFFF]]
          @?= ["0000", "0001", "000F", "0010", "0FFF", "1000", "FFFF"],
      testCase "I3 the boundary offsets are printf \"%010d\"" $
        [built (decimal10 o) | o <- [0, 9, 10, maxOffset]]
          @?= [printf "%010d" o | o <- [0, 9, 10, maxOffset :: Int]],
      testProperty "I3 decimal10 o is printf \"%010d\" o for offsets from 0 to 9,999,999,999" . property $ do
        o <- forAll (Gen.int (Range.exponential 0 maxOffset))
        built (decimal10 o) === printf "%010d" o
    ]
