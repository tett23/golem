-- the enumerations are built in the tests that check them, and must not
-- be floated out into values that live as long as the program (docs/adr/0208)
{-# OPTIONS_GHC -fno-full-laziness -fno-cse #-}

{- | The places of line adjustment in the order of JLReq (docs/adr/0278):
the kinds of glue, the stages that shrink and stretch a set line, and A1
to A9 and A12 on paragraphs made by hand and on every small input of
docs/adr/0209.
-}
module AdjustOrderSpec (adjustOrderTests) where

import Data.Bits (xor)
import Data.ByteString.Lazy qualified as BL
import Data.Char (ord)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word64)
import Golem.Layout.KnuthPlass
import Golem.TestSupport.Enum
import LineBreakEnum
import Numeric (showHex)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)

adjustOrderTests :: TestTree
adjustOrderTests =
  testGroup
    "the places of line adjustment in the order of JLReq (docs/adr/0278)"
    [ goldenVsString
        "A9: the items of every input up to 2 parts, the kinds and the sizes of the glue left out, are those before the ADR (test/golden/adjust-order-items.tsv)"
        "test/golden/adjust-order-items.tsv"
        (pure (BL.fromStrict (TE.encodeUtf8 itemLines)))
    ]

-- | FNV-1a, 64 bits, over the code points of a string.
fnv :: String -> Word64
fnv = foldl (\h c -> (h `xor` fromIntegral (ord c)) * 0x100000001b3) 0xcbf29ce484222325

{- | An item as A9 compares it: a glue by its width, stretch and shrink
alone, the kind and the size it has after docs/adr/0278 left out.
-}
itemKey :: Item -> String
itemKey = \case
  Glue {itemWidth = w, itemStretch = y, itemShrink = z} -> "G" <> show (unSp w, unSp y, unSp z)
  it -> show it

{- | A9 of docs/adr/0278: the items of every run up to two parts, in every
setting of its normal form, at the start and not, at the end and not, in
horizontal and in vertical writing: the hash of each run. More characters
before and after the run repeat those items. The golden file was written
by the implementation before the ADR.
-}
itemLines :: Text
itemLines =
  let (_, hashes) = tallyAllPar 2 runsT (\run -> ([], Map.singleton run (hashOf run)))
      hashOf run = T.pack (showHex (fnv (concat [concatMap itemKey (itemsOf v s pre run post) | v <- [False, True], s <- normalSettings run, pre <- [0, 1], post <- [0, 1]])) "")
   in T.unlines [T.intercalate "\t" [T.pack (show run), Map.findWithDefault "" run hashes] | run <- concat (upTo 2 runsT)]

-- | The runs of the enumeration (docs/adr/0209).
runsT :: Tiers [Text]
runsT = listsOf (Tiers [parts])
