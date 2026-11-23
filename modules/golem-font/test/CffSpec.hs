{- | The references of an embedded CFF table stay inside the table (Golem
ADR 0357, I1).

The fixtures are the CFF tables of Source Sans Pro (a name-keyed font) and
of the subset of Source Han Sans (a CID-keyed font with an FDArray and an
FDSelect). In both, the last byte of the table belongs to an INDEX that the
check reads, so cutting the declared length by any amount leaves a used
reference outside the table. The small tables built here call subroutines
with computed numbers.
-}
module CffSpec (cffTests, randomCffTests, seacTests) where

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
        tableCheck (BS.take cut cff) gids === CffOutOfTable
        -- every reference ends within it: accepted, whatever follows the table
        tableCheck cff gids === CffInTable
        tableCheck (cff <> BS.replicate 7 0) gids === CffInTable,
      testCase "ADR 0357 I1: inv1_validate_embedded_cff_case_1" $ do
        -- every glyph of both fonts: the table ends where its last INDEX does
        tableCheck (table sansFile) [0 .. sansGlyphs - 1] @?= CffInTable
        tableCheck (table hanFile) [0 .. hanGlyphs - 1] @?= CffInTable
        referencesCheck sansFile [0 .. sansGlyphs - 1] @?= CffInTable,
      testCase "ADR 0357 I1: every glyph of a whole Japanese font is within its table" $
        referencesCheck notoFile [0 .. notoGlyphs - 1] @?= CffInTable,
      testCase "ADR 0357 I1: inv1_validate_embedded_cff_case_2" $ do
        let short f = BS.take (BS.length (table f) - 1) (table f)
        tableCheck (short sansFile) [0] @?= CffOutOfTable
        tableCheck (short hanFile) [0] @?= CffOutOfTable,
      testCase "ADR 0357 I1: the table of the first font of a collection" $ do
        sfntCffTable (asCollection sansFile) @?= sfntCffTable sansFile
        fmap BS.length (sfntCffTable sansFile) @?= Just 114180,
      testCase "ADR 0357 I1: a font without a CFF table is left to the other checks" $
        referencesCheck "not a font" [0] @?= CffInTable,
      testCase "ADR 0357 I1: a subroutine number computed by arithmetic is followed" $ do
        -- -110 + 3 = -107: local subroutine 0 with the bias 107
        tableCheck (synthetic [[251, 2, 142, 12, 10, 10, 14]] [[11]] []) [0] @?= CffInTable
        -- -110 + 4 = -106: local subroutine 1 of a one-entry INDEX
        tableCheck (synthetic [[251, 2, 143, 12, 10, 10, 14]] [[11]] []) [0] @?= CffOutOfTable,
      testCase "ADR 0357 I1: global subroutines and nested calls" $ do
        -- the global subroutine 0 calls the local subroutine 0
        tableCheck (synthetic [[32, 29, 14]] [[11]] [[32, 10, 11]]) [0] @?= CffInTable
        -- the global subroutine 0 calls the local subroutine 1, which is missing
        tableCheck (synthetic [[32, 29, 14]] [[11]] [[33, 10, 11]]) [0] @?= CffOutOfTable,
      testCase "ADR 0357 I1: a malformed CharString that reads no offset is not G08107" $ do
        -- callsubr on an empty stack, and an add with one operand
        tableCheck (synthetic [[10, 14]] [[11]] []) [0] @?= CffInTable
        tableCheck (synthetic [[139, 12, 10, 10, 14]] [[11]] []) [0] @?= CffInTable,
      testCase "ADR 0357 I1: only the used glyphs are followed" $ do
        let cff = synthetic [[14], [33, 10, 14]] [[11]] []
        tableCheck cff [0] @?= CffInTable
        tableCheck cff [0, 1] @?= CffOutOfTable,
      testCase "ADR 0357 I1: a glyph beyond the CharStrings INDEX" $
        tableCheck (synthetic [[14]] [[11]] []) [0, 1] @?= CffOutOfTable,
      testCase "ADR 0357 I1: a 32-bit offset past the table, on 32-bit and 64-bit Int alike" $ do
        let cff = synthetic [[14]] [[11]] []
            -- the CharStrings offset of the Top DICT: the four bytes after the 29 at 27
            withOffset v = BS.take 28 cff <> BS.pack v <> BS.drop 32 cff
        BS.index cff 27 @?= 29
        tableCheck (withOffset [0x7f, 0xff, 0xff, 0xff]) [0] @?= CffOutOfTable
        tableCheck (withOffset [0xff, 0xff, 0xff, 0xff]) [0] @?= CffOutOfTable,
      testCase "ADR 0357 I1: a Private DICT past the table" $ do
        let cff = synthetic [[14]] [] []
        -- without local subroutines the Private DICT is the end of the table
        tableCheck cff [0] @?= CffInTable
        tableCheck (BS.take (BS.length cff - 1) cff) [0] @?= CffOutOfTable
    ]
  where
    table f = fromMaybe (error "no CFF table") (sfntCffTable f)

-- | Whether the used references of a bare CFF table stay inside it (Golem ADR 0357).
tableCheck :: ByteString -> [Int] -> CffCheck
tableCheck t = cffCheck . checkCffTable t

-- | 'tableCheck' on the CFF table of a font file.
referencesCheck :: ByteString -> [Int] -> CffCheck
referencesCheck f = cffCheck . checkCffReferences f

{- | The references of the values of random checked over every value it may
take (Golem ADR 0390, I5 to I7). The glyph 0 of each table is checked:
G08107 is 'CffOutOfTable', and G08108 is the glyph in 'cffUnverifiable'.
With c local subroutines the bias b is 107, a number v written in a
CharString is in the INDEX when 0 <= v + b < c, and n = c - b - 1 is the
largest number that may be written.
-}
randomCffTests :: TestTree
randomCffTests =
  testGroup
    "CFF references over every value of random (Golem ADR 0390)"
    [ testCase "ADR 0390 I5, I6: random k mul callsubr is G08107 exactly when k > n" $
        sequence_
          [ assertEqual (show (c, k)) (if k > c - 108 then out else clean) (verdict (synthetic [randomCall k] (returns c) []))
          | c <- [100 .. 116],
            k <- [0 .. 12]
          ],
      testCase "ADR 0390 I5: a glyph without random is as before" $
        verdict (synthetic [[139, 139, 21, 14]] (returns 1) []) @?= clean,
      testCase "ADR 0390 I5: random that reaches no number" $
        verdict (synthetic [[12, 23, 12, 23, 21, 14]] (returns 1) []) @?= clean,
      testCase "ADR 0390 I5: k less than n" $
        verdict (synthetic [randomCall 11] (returns 120) []) @?= clean,
      testCase "ADR 0390 I5: k exactly n" $
        verdict (synthetic [randomCall 12] (returns 120) []) @?= clean,
      testCase "ADR 0390 I6: k one more than n" $
        verdict (synthetic [randomCall 13] (returns 120) []) @?= out,
      testCase "ADR 0390 I6: only one branch of an ifelse chosen by random calls past the INDEX" $ do
        -- 0 600 random 0.5 ifelse callsubr endchar: subroutines 107 and 707
        verdict (synthetic [[139, 248, 236, 12, 23] <> half <> [12, 22, 10, 14]] (returns 108) []) @?= out
        -- 0 0 random 0.5 ifelse callsubr endchar: both branches call 107
        verdict (synthetic [[139, 139, 12, 23] <> half <> [12, 22, 10, 14]] (returns 108) []) @?= clean,
      testCase "ADR 0390 I5: two subroutines chosen by an interval declare different stems, and each branch reads its hintmask" $ do
        verdict (synthetic [stemsGlyph] (stemsLocals 2 3) []) @?= clean
        -- the same with the numbers swapped: each branch read right calls past the INDEX
        verdict (synthetic [stemsGlyph] (stemsLocals 3 2) []) @?= out,
      testCase "ADR 0390 I5, I7: the operators of all the branches add up to exactly the limit" $
        -- 0 0 1 random 0.5 ifelse: 6 before the two branches, then 2 + 2 * 24997 + 1 in each
        verdict (synthetic [[139, 139, 140, 12, 23] <> half <> [12, 22, 12, 18, 12, 18] <> pushDrops 24997 <> [14]] [] []) @?= clean,
      testCase "ADR 0390 I7, I9: the operators of all the branches add up to one more than the limit" $
        -- 0 1 random 0.5 ifelse: 5 before the two branches, then 1 + 2 * 24998 + 1 in each
        verdict (synthetic [[139, 140, 12, 23] <> half <> [12, 22, 12, 18] <> pushDrops 24998 <> [14]] [] []) @?= unverifiable,
      testCase "ADR 0390 I7: a glyph without random at exactly the limit" $
        verdict (synthetic [pushDrops 49999 <> [139, 14]] [] []) @?= clean,
      testCase "ADR 0390 I7, I9: a glyph without random one over the limit, the 100001st an endchar" $
        verdict (synthetic [pushDrops 49999 <> [139, 139, 14]] [] []) @?= unverifiable,
      testCase "ADR 0390 I7: a b random random ifelse repeated: 7 * 2^r - 6 operators, G08108 from r = 14" $
        sequence_
          [ assertEqual (show r) (if 7 * 2 ^ r - 6 > (100000 :: Int) then unverifiable else clean) (verdict (synthetic [concat (replicate r [139, 140, 12, 23, 12, 23, 12, 22, 12, 18]) <> [14]] [] []))
          | r <- [0 .. 15 :: Int]
          ],
      testCase "ADR 0390 I6: 1 random div callsubr" $
        verdict (synthetic [[140, 12, 23, 12, 12, 10, 14]] (returns 2000) []) @?= out,
      testCase "ADR 0390 I7, I9: dividing by random 0.5 sub" $
        verdict (synthetic [[140, 12, 23] <> half <> [12, 11, 12, 12, 12, 18, 14]] [] []) @?= unverifiable,
      testCase "ADR 0390 I7, I9: random 0.5 sub sqrt" $
        verdict (synthetic [[12, 23] <> half <> [12, 11, 12, 26, 12, 18, 14]] [] []) @?= unverifiable,
      testCase "ADR 0390 I5: random 3 mul index with five values on the stack follows the positions 0 to 3" $
        -- the value at position p is 600 (subroutine 707, past the INDEX), the
        -- others 0; hstem clears the five values before endchar, which would
        -- read them as a width and a seac (root ADR 0420)
        sequence_
          [ assertEqual (show p) (if p <= 3 then out else clean) (verdict (synthetic [concat [if q == p then [248, 236] else [139] | q <- [4, 3, 2, 1, 0 :: Int]] <> [12, 23, 142, 12, 24, 12, 29, 10, 1, 14]] (returns 108) []))
          | p <- [0 .. 4 :: Int]
          ],
      testCase "ADR 0390 I7: random 4 mul index with four values on the stack goes past its depth" $
        verdict (synthetic [[139, 139, 139, 139, 12, 23, 143, 12, 24, 12, 29, 10, 14]] (returns 108) []) @?= unverifiable,
      testCase "ADR 0390 I5: the glyphs that run random are told" $
        cffRandom (checkCffTable (synthetic [[14], [12, 23, 12, 18, 14]] [] []) [0, 1]) @?= [1]
    ]
  where
    verdict t = let r = checkCffTable t [0] in (cffCheck r, cffUnverifiable r)
    clean = (CffInTable, [])
    out = (CffOutOfTable, [])
    unverifiable = (CffInTable, [0])
    -- 0.5 as a 16.16 number
    half = [255, 0, 0, 0x80, 0]
    -- random k mul callsubr endchar, k from 0 to 107
    randomCall :: Int -> [Word8]
    randomCall k = [12, 23, fromIntegral (k + 139), 12, 24, 10, 14]
    returns :: Int -> [[Word8]]
    returns c = replicate c [11]
    -- push 0 and drop it, n times: 2 operators each
    pushDrops n = concat (replicate n [139, 12, 18])
    {- random 1 mul callsubr calls subroutine 107, which declares one stem,
    or subroutine 108, which declares nine. Each puts the number mine (2:
    subroutine 109, a return; 3: past the INDEX) where its own hintmask
    reads it, and the number other where the other reads it: hintmask is one
    byte after one stem and two after nine, and 247 139 is the number 247,
    or the byte of a mask and then 0. The glyph then calls what it got -}
    stemsGlyph = [12, 23, 140, 12, 24, 10, 19, 0xff, 247, 139, 12, 21, 10, 14]
    stemsLocals :: Int -> Int -> [[Word8]]
    stemsLocals mine other =
      let n v = fromIntegral (v + 139)
       in returns 107
            <> [ [139, 149, 1, n mine, 247, 139, 12, 20, n other, 139, 12, 20, 11],
                 concat (replicate 9 [139, 149]) <> [1, n other, 247, 139, 12, 20, n mine, 139, 12, 20, 11],
                 [11]
               ]

{- | The components of a seac checked as the glyphs used (root ADR 0420).

The fonts are Source Sans Pro (name-keyed) and the subset of Source Han
Sans (CID-keyed), with CharStrings rewritten in place. The glyph used is b
(glyph 29, 56 bytes) of Source Sans Pro, rewritten to a seac; its base
character A (code 65 of StandardEncoding, glyph 2) and its accent grave
(code 193, glyph 1804) are rewritten for the rows of the components. The
font has 611 local subroutines: the bias is 107, and 503 is the largest
number a CharString may call.
-}
seacTests :: (ByteString, Int) -> (ByteString, Int) -> (ByteString, Int) -> TestTree
seacTests (sans, sansGlyphs) (han, hanGlyphs) (noto, notoGlyphs) =
  testGroup
    "the seac components of embedded CFF (root ADR 0420)"
    [ testCase "root ADR 0420 I1, I3: a seac whose components are right is accepted" $ do
        verdict (used (seac 65 193) sans) @?= clean
        -- with the width before the arguments, and the width alone
        verdict (used (num 200 <> seac 65 193) sans) @?= clean
        verdict (used (num 200 <> [14]) sans) @?= clean,
      testCase "root ADR 0420 I1: the CharString of the base component ends exactly at the end of the table, or one byte past it" $ do
        verdict (charStringEnd 45452 79245 (used (seac 65 193) sans)) @?= clean
        verdict (charStringEnd 45452 79246 (used (seac 65 193) sans)) @?= out
        -- without the seac the component is not used, so not followed
        verdict (charStringEnd 45452 79246 sans) @?= clean,
      testCase "root ADR 0420 I1: the CharString of the accent component ends past the table" $
        verdict (charStringEnd 50858 79246 (used (seac 65 193) sans)) @?= out,
      testCase "root ADR 0420 I1: the base component calls the last local subroutine, or one past it" $ do
        verdict (base (call 503) (used (seac 65 193) sans)) @?= clean
        verdict (base (call 504) (used (seac 65 193) sans)) @?= out,
      testCase "root ADR 0420 I1: the accent component calls the last local subroutine, or one past it" $ do
        verdict (accent (call 503 <> [14]) (used (seac 65 193) sans)) @?= clean
        verdict (accent (call 504 <> [14]) (used (seac 65 193) sans)) @?= out,
      testCase "root ADR 0420 I1: a subroutine of the accent component divides by an interval holding 0" $
        -- the local subroutine 503: 1 random 0.5 sub div drop return
        verdict (subroutine503 brokenDivision (accent (call 503 <> [14]) (used (seac 65 193) sans))) @?= (CffInTable, [29], []),
      testCase "root ADR 0420 I2: bchar 256 or -1, or not an integer, is G08114; 255 is a code of no character" $ do
        verdict (used (seac 256 193) sans) @?= wrong SeacArguments
        verdict (used (seac (-1) 193) sans) @?= wrong SeacArguments
        -- 0 0 131 2 div 193 endchar: bchar 65.5
        verdict (used (num 0 <> num 0 <> num 131 <> num 2 <> [12, 12] <> num 193 <> [14]) sans) @?= wrong SeacArguments
        verdict (used (seac 255 193) sans) @?= wrong SeacMissingComponent
        verdict (used (seac 65 256) sans) @?= wrong SeacArguments,
      testCase "root ADR 0420 I2: arguments besides the width other than 0 or 4 are G08114" $ do
        -- 2, 3 (a width and 2) and 6 arguments
        verdict (used (num 65 <> num 193 <> [14]) sans) @?= wrong SeacArguments
        verdict (used (num 200 <> num 65 <> num 193 <> [14]) sans) @?= wrong SeacArguments
        verdict (used (num 0 <> num 0 <> seac 65 193) sans) @?= wrong SeacArguments,
      testCase "root ADR 0420 I2: bchar 0, a code of no character in StandardEncoding, is G08115" $
        verdict (used (seac 0 193) sans) @?= wrong SeacMissingComponent,
      testCase "root ADR 0420 I2: an achar whose character the charset has not is G08115" $
        -- code 166 is florin (SID 101), which the font has not
        verdict (used (seac 65 166) sans) @?= wrong SeacMissingComponent,
      testCase "root ADR 0420 I2: a component that is a seac itself is G08116" $ do
        verdict (accent (seac 65 66) (used (seac 65 193) sans)) @?= wrong SeacNested
        -- a component with the width alone is not a seac
        verdict (accent (num 200 <> [14]) (used (seac 65 193) sans)) @?= clean,
      testCase "root ADR 0420 I2: a seac in a CID-keyed font is G08117" $ do
        -- glyph 503 (あ) of the subset of Source Han Sans, 151 bytes
        BS.take 3 (BS.drop 153634 han) @?= BS.pack [75, 10, 248]
        let cid program = checkCffReferences (patch 153634 151 14 program han) [503]
        cffSeac (cid (seac 65 66)) @?= [(503, SeacCidKeyed)]
        cffSeac (cid (num 65 <> num 66 <> [14])) @?= [(503, SeacArguments)]
        cffSeac (cid (num 200 <> [14])) @?= [],
      testCase "root ADR 0420 I1: a bchar from random whose components are all right is accepted" $ do
        -- 0 0 random 64 add 193 endchar: bchar in (64, 65], the codes 64 (at) and 65 (A)
        let r = checkCffReferences (used (num 0 <> num 0 <> [12, 23] <> num 64 <> [12, 10] <> num 193 <> [14]) sans) [29]
        (cffCheck r, cffUnverifiable r, cffSeac r, cffRandom r) @?= (CffInTable, [], [], [29]),
      testCase "root ADR 0420 I2: a bchar from random is checked over every value it may take" $ do
        -- random 192 add: the codes 192 (no character) and 193
        verdict (used (num 0 <> num 0 <> [12, 23] <> num 192 <> [12, 10] <> num 193 <> [14]) sans) @?= wrong SeacMissingComponent
        -- random 256 mul: the codes 0 to 256, past 255
        verdict (used (num 0 <> num 0 <> [12, 23] <> num 256 <> [12, 24] <> num 193 <> [14]) sans) @?= wrong SeacArguments
        -- the accent of base A in every branch: 1 random div, an interval to infinity, cannot be followed (G08108)
        verdict (used (num 0 <> num 0 <> num 65 <> num 1 <> [12, 23, 12, 12] <> [14]) sans) @?= (CffInTable, [29], []),
      testCase "root ADR 0420 I2: a seac in a glyph not used is not followed" $
        verdict' [2] (used (seac 256 193) sans) @?= clean,
      testCase "root ADR 0420 I3: no glyph of the fonts of the repository has a wrong seac" $ do
        cffSeac (checkCffReferences sans [0 .. sansGlyphs - 1]) @?= []
        cffSeac (checkCffReferences han [0 .. hanGlyphs - 1]) @?= []
        cffSeac (checkCffReferences noto [0 .. notoGlyphs - 1]) @?= []
    ]
  where
    verdict = verdict' [29]
    verdict' gids f = let r = checkCffReferences f gids in (cffCheck r, cffUnverifiable r, cffSeac r)
    clean = (CffInTable, [], [])
    out = (CffOutOfTable, [], [])
    wrong e = (CffInTable, [], [(29, e)])
    -- adx ady bchar achar endchar, the offsets 0
    seac :: Int -> Int -> [Word8]
    seac b a = num 0 <> num 0 <> num b <> num a <> [14]
    call :: Int -> [Word8]
    call k = num k <> [10]
    -- the glyph used b, the base A, the accent grave and the local subroutine 503
    used program f = expect 51650 [134, 248, 81] f (patch 51650 56 14 program f)
    base program f = expect 51363 [97, 29, 14] f (patch 51363 3 14 program f)
    accent program f = expect 116734 [123, 248, 49] f (patch 116734 15 14 program f)
    subroutine503 program f = expect 130482 [57, 251, 118] f (patch 130482 34 11 program f)
    brokenDivision = [140, 12, 23, 255, 0, 0, 0x80, 0, 12, 11, 12, 12, 12, 18, 11]
    -- the three-byte end offset of a CharString in the CharStrings INDEX
    charStringEnd :: Int -> Int -> ByteString -> ByteString
    charStringEnd at v f = BS.take at f <> BS.pack [fromIntegral (v `shiftR` 16), fromIntegral (v `shiftR` 8), fromIntegral v] <> BS.drop (at + 3) f
    expect at bytes f patched = if BS.unpack (BS.take (length bytes) (BS.drop at f)) == bytes then patched else error ("not the bytes at " <> show at)

-- | The bytes of a font file from an offset replaced by a program, the rest of the length filled.
patch :: Int -> Int -> Word8 -> [Word8] -> ByteString -> ByteString
patch at len fill program f
  | length program > len = error ("a program longer than " <> show len)
  | otherwise = BS.take at f <> BS.pack program <> BS.replicate (len - length program) fill <> BS.drop (at + len) f

-- | A number of a Type 2 CharString.
num :: Int -> [Word8]
num v
  | v >= -107 && v <= 107 = [fromIntegral (v + 139)]
  | v >= 108 && v <= 1131 = let w = v - 108 in [fromIntegral (247 + w `div` 256), fromIntegral (w `mod` 256)]
  | v <= -108 && v >= -1131 = let w = negate v - 108 in [fromIntegral (251 + w `div` 256), fromIntegral (w `mod` 256)]
  | otherwise = [28, fromIntegral (v `shiftR` 8), fromIntegral v]

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
