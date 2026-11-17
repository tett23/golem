{- | The references of an embedded CFF table stay inside the table (Golem
ADR 0357, I1).

The fixtures are the CFF tables of Source Sans Pro (a name-keyed font) and
of the subset of Source Han Sans (a CID-keyed font with an FDArray and an
FDSelect). In both, the last byte of the table belongs to an INDEX that the
check reads, so cutting the declared length by any amount leaves a used
reference outside the table. The small tables built here call subroutines
with computed numbers.
-}
module CffSpec (cffTests) where

import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Maybe (fromMaybe)
import Data.Word (Word8)
import Golem.Font.Cff
import Hedgehog (forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

cffTests :: (ByteString, Int) -> (ByteString, Int) -> (ByteString, Int) -> TestTree
cffTests (sansFile, sansGlyphs) (hanFile, hanGlyphs) (notoFile, notoGlyphs) =
  testGroup
    "CFF references within the table (Golem ADR 0357)"
    [ testPropertyNamed "ADR 0357 I1: inv1_validate_embedded_cff_property" "inv1_validate_embedded_cff_property" $ property $ do
        (file, n) <- forAll (Gen.element [(sansFile, sansGlyphs), (hanFile, hanGlyphs)])
        let cff = table file
        gids <- forAll (Gen.list (Range.linear 0 12) (Gen.int (Range.linear 0 (n - 1))))
        cut <- forAll (Gen.int (Range.linear 0 (BS.length cff - 1)))
        -- a used reference ends past the declared length: rejected
        checkCffTable (BS.take cut cff) gids === CffOutOfTable
        -- every reference ends within it: accepted, whatever follows the table
        checkCffTable cff gids === CffInTable
        checkCffTable (cff <> BS.replicate 7 0) gids === CffInTable,
      testCase "ADR 0357 I1: inv1_validate_embedded_cff_case_1" $ do
        -- every glyph of both fonts: the table ends where its last INDEX does
        checkCffTable (table sansFile) [0 .. sansGlyphs - 1] @?= CffInTable
        checkCffTable (table hanFile) [0 .. hanGlyphs - 1] @?= CffInTable
        checkCffReferences sansFile [0 .. sansGlyphs - 1] @?= CffInTable,
      testCase "ADR 0357 I1: every glyph of a whole Japanese font is within its table" $
        checkCffReferences notoFile [0 .. notoGlyphs - 1] @?= CffInTable,
      testCase "ADR 0357 I1: inv1_validate_embedded_cff_case_2" $ do
        let short f = BS.take (BS.length (table f) - 1) (table f)
        checkCffTable (short sansFile) [0] @?= CffOutOfTable
        checkCffTable (short hanFile) [0] @?= CffOutOfTable,
      testCase "ADR 0357 I1: the table of the first font of a collection" $ do
        sfntCffTable (asCollection sansFile) @?= sfntCffTable sansFile
        fmap BS.length (sfntCffTable sansFile) @?= Just 114180,
      testCase "ADR 0357 I1: a font without a CFF table is left to the other checks" $
        checkCffReferences "not a font" [0] @?= CffInTable,
      testCase "ADR 0357 I1: a subroutine number computed by arithmetic is followed" $ do
        -- -110 + 3 = -107: local subroutine 0 with the bias 107
        checkCffTable (synthetic [[251, 2, 142, 12, 10, 10, 14]] [[11]] []) [0] @?= CffInTable
        -- -110 + 4 = -106: local subroutine 1 of a one-entry INDEX
        checkCffTable (synthetic [[251, 2, 143, 12, 10, 10, 14]] [[11]] []) [0] @?= CffOutOfTable,
      testCase "ADR 0357 I1: global subroutines and nested calls" $ do
        -- the global subroutine 0 calls the local subroutine 0
        checkCffTable (synthetic [[32, 29, 14]] [[11]] [[32, 10, 11]]) [0] @?= CffInTable
        -- the global subroutine 0 calls the local subroutine 1, which is missing
        checkCffTable (synthetic [[32, 29, 14]] [[11]] [[33, 10, 11]]) [0] @?= CffOutOfTable,
      testCase "ADR 0357 I1: a malformed CharString that reads no offset is not G08107" $ do
        -- callsubr on an empty stack, and an add with one operand
        checkCffTable (synthetic [[10, 14]] [[11]] []) [0] @?= CffInTable
        checkCffTable (synthetic [[139, 12, 10, 10, 14]] [[11]] []) [0] @?= CffInTable,
      testCase "ADR 0357 I1: only the used glyphs are followed" $ do
        let cff = synthetic [[14], [33, 10, 14]] [[11]] []
        checkCffTable cff [0] @?= CffInTable
        checkCffTable cff [0, 1] @?= CffOutOfTable,
      testCase "ADR 0357 I1: a glyph beyond the CharStrings INDEX" $
        checkCffTable (synthetic [[14]] [[11]] []) [0, 1] @?= CffOutOfTable,
      testCase "ADR 0357 I1: a 32-bit offset past the table, on 32-bit and 64-bit Int alike" $ do
        let cff = synthetic [[14]] [[11]] []
            -- the CharStrings offset of the Top DICT: the four bytes after the 29 at 27
            withOffset v = BS.take 28 cff <> BS.pack v <> BS.drop 32 cff
        BS.index cff 27 @?= 29
        checkCffTable (withOffset [0x7f, 0xff, 0xff, 0xff]) [0] @?= CffOutOfTable
        checkCffTable (withOffset [0xff, 0xff, 0xff, 0xff]) [0] @?= CffOutOfTable,
      testCase "ADR 0357 I1: a Private DICT past the table" $ do
        let cff = synthetic [[14]] [] []
        -- without local subroutines the Private DICT is the end of the table
        checkCffTable cff [0] @?= CffInTable
        checkCffTable (BS.take (BS.length cff - 1) cff) [0] @?= CffOutOfTable
    ]
  where
    table f = fromMaybe (error "no CFF table") (sfntCffTable f)

{- | A name-keyed CFF table with the CharStrings, the local subroutines (none:
no Subrs in the Private DICT) and the global subroutines. Every offset of
the Top DICT is a five-byte integer, so its size does not depend on them.
-}
synthetic :: [[Word8]] -> [[Word8]] -> [[Word8]] -> ByteString
synthetic glyphs locals globals =
  let header = BS.pack [1, 0, 4, 4]
      name = index ["X"]
      top c ps po = index [int5 c <> BS.pack [17] <> int5 ps <> int5 po <> BS.pack [18]]
      strings = index []
      gsubrs = index (map BS.pack globals)
      csOff = BS.length (header <> name <> top 0 0 0 <> strings <> gsubrs)
      cs = index (map BS.pack glyphs)
      private = if null locals then BS.empty else int5 6 <> BS.pack [19]
      privOff = csOff + BS.length cs
      lsubrs = if null locals then BS.empty else index (map BS.pack locals)
   in header <> name <> top csOff (BS.length private) privOff <> strings <> gsubrs <> cs <> private <> lsubrs

-- | An INDEX with four-byte offsets.
index :: [ByteString] -> ByteString
index [] = BS.pack [0, 0]
index items =
  let offsets = scanl (+) 1 (map BS.length items)
   in BS.pack [fromIntegral (length items `shiftR` 8), fromIntegral (length items), 4] <> BS.concat (map be32 offsets) <> BS.concat items

int5 :: Int -> ByteString
int5 v = BS.cons 29 (be32 v)

be32 :: Int -> ByteString
be32 v = BS.pack [fromIntegral (v `shiftR` s) | s <- [24, 16, 8, 0]]

-- | A version 1.0 TTC holding the one sfnt font; its table offsets move by the 16 bytes of the header.
asCollection :: ByteString -> ByteString
asCollection font =
  let numTables = fromIntegral (BS.index font 4) * 256 + fromIntegral (BS.index font 5) :: Int
      u32 o = foldl (\a i -> a * 256 + fromIntegral (BS.index font (o + i))) 0 [0 .. 3] :: Int
      record k = let r = 12 + 16 * k in BS.take 8 (BS.drop r font) <> be32 (u32 (r + 8) + 16) <> BS.take 4 (BS.drop (r + 12) font)
   in "ttcf" <> be32 0x00010000 <> be32 1 <> be32 16 <> BS.take 12 font <> BS.concat (map record [0 .. numTables - 1]) <> BS.drop (12 + 16 * numTables) font
