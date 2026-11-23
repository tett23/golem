{- | The CCITTFaxDecode filter (root ADR 0425 I8: a mask encoded with
CCITTFaxDecode is judged by its decoded values). The tests follow those of
the decoder of golang.org/x/image/ccitt: the code tables, an invalid code,
and the Group 3 and Group 4 encodings of one picture against its PNG. They
add the two-dimensional modes by hand from ITU-T T.4, Group 3
two-dimensional coding, and round trips through an encoder written from
the coding procedures of T.4 and T.6 for every combination of the
parameters of the filter.
-}
module CcittSpec (ccittTests) where

import CcittEncode (changesOf, encodeCcitt, endMarked, packRows)
import Codec.Picture (DynamicImage, Image (..), PixelRGB8 (..), convertRGB8, pixelAt, readImage)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.List (isPrefixOf)
import Data.Word (Word8)
import Golem.Typeset.Ccitt
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

ccittTests :: [TestTree]
ccittTests =
  [ testGroup "root ADR 0425 I8: the code tables of T.4" tableTests,
    testGroup "root ADR 0425 I8: the Group 3 and Group 4 encodings of one picture" fixtureTests,
    testGroup "root ADR 0425 I8: the modes of two-dimensional coding" modeTests,
    testGroup "root ADR 0425 I8: the parameters of the filter" parameterTests,
    testGroup "root ADR 0425 I8: damaged data" damageTests,
    testGroup "root ADR 0425 I8: round trips" roundTrips
  ]

-- Tables -------------------------------------------------------------------

tableTests :: [TestTree]
tableTests =
  [ testCase "root ADR 0425 I8: the white and black tables have 64 terminating, 27 make-up and 13 extended codes" $ do
      map length [whiteCodes, blackCodes] @?= [104, 104]
      map codeValue whiteCodes @?= [0 .. 63] <> [64, 128 .. 1728] <> [1792, 1856 .. 2560]
      map codeValue blackCodes @?= map codeValue whiteCodes,
    testCase "root ADR 0425 I8: no code of a table is a prefix of another" $
      mapM_ (\(name, table) -> assertBool name (prefixFree (map codeBits table))) [("mode", modeCodes), ("white", whiteCodes), ("black", blackCodes)],
    testCase "root ADR 0425 I8: no code has eleven zeros, so that EOL cannot be read as data" $
      assertBool "eleven zeros" (not (any (("00000000000" `isPrefixOf`) . codeBits) (modeCodes <> whiteCodes <> blackCodes))),
    testCase "root ADR 0425 I8: the codes of T.4 Table 1 spot-checked" $ do
      lookup 0 [(codeValue c, codeBits c) | c <- whiteCodes] @?= Just "00110101"
      lookup 1728 [(codeValue c, codeBits c) | c <- whiteCodes] @?= Just "010011011"
      lookup 0 [(codeValue c, codeBits c) | c <- blackCodes] @?= Just "0000110111"
      lookup 1728 [(codeValue c, codeBits c) | c <- blackCodes] @?= Just "0000001100101"
      lookup 2560 [(codeValue c, codeBits c) | c <- blackCodes] @?= Just "000000011111",
    testCase "root ADR 0425 I8: every run from 0 to 2700 of each colour decodes to itself" $ do
      let runs = [0 .. 2700]
      mapM_ (\n -> decodeRows (g3 (n + 1)) 1 (encodeCcitt (g3 (n + 1)) [replicate n False <> [True]]) @?= Right (packRows False [replicate n False <> [True]])) runs
      mapM_ (\n -> decodeRows (g3 (n + 1)) 1 (encodeCcitt (g3 (n + 1)) [True : replicate n True]) @?= Right (packRows False [True : replicate n True])) runs
  ]
  where
    prefixFree codes = and [not (a `isPrefixOf` b) | (i, a) <- zip [0 :: Int ..] codes, (j, b) <- zip [0 ..] codes, i /= j]
    g3 columns = defaultCcittParams {ccittColumns = columns}

-- The Go fixtures ------------------------------------------------------------

fixtureTests :: [TestTree]
fixtureTests =
  [ fixture "bw-gopher.ccitt_group3" group3,
    fixture "bw-gopher-inverted.ccitt_group3" group3 {ccittBlackIs1 = True},
    fixture "bw-gopher-truncated0.ccitt_group3" group3,
    fixture "bw-gopher-truncated1.ccitt_group3" group3,
    fixture "bw-gopher.ccitt_group4" group4,
    fixture "bw-gopher-aligned.ccitt_group4" group4 {ccittByteAlign = True},
    fixture "bw-gopher-inverted.ccitt_group4" group4 {ccittBlackIs1 = True},
    fixture "bw-gopher-inverted-aligned.ccitt_group4" group4 {ccittBlackIs1 = True, ccittByteAlign = True},
    fixture "bw-gopher-truncated0.ccitt_group4" group4,
    fixture "bw-gopher-truncated1.ccitt_group4" group4,
    testCase "root ADR 0425 I8: without Rows, the Group 3 picture ends at its RTC and the Group 4 one at its EOFB" $ do
      expected <- gopher
      g3 <- BS.readFile "test/fixtures/ccitt/bw-gopher.ccitt_group3"
      g4 <- BS.readFile "test/fixtures/ccitt/bw-gopher.ccitt_group4"
      decodeRows group3 {ccittRows = 0} 1000 g3 @?= Right expected
      decodeRows group4 {ccittRows = 0} 1000 g4 @?= Right expected
  ]
  where
    group3 = defaultCcittParams {ccittColumns = 153, ccittRows = 55, ccittEndOfLine = True}
    group4 = defaultCcittParams {ccittK = -1, ccittColumns = 153, ccittRows = 55}
    fixture name params = testCase ("root ADR 0425 I8: " <> name <> " decodes to bw-gopher.png") $ do
      expected <- gopher
      input <- BS.readFile ("test/fixtures/ccitt/" <> name)
      -- an inverted file encodes the inverse; BlackIs1 writes it back
      decodeRows params 55 input @?= Right expected

-- | bw-gopher.png, 153 by 55, packed with 1 for white.
gopher :: IO ByteString
gopher = do
  loaded <- readImage "test/fixtures/ccitt/bw-gopher.png"
  image <- either assertFailure (pure . convertRGB8) (loaded :: Either String DynamicImage)
  let white x y = let PixelRGB8 r _ _ = pixelAt image x y in r >= 128
  pure (packRows False [[not (white x y) | x <- [0 .. imageWidth image - 1]] | y <- [0 .. imageHeight image - 1]])

-- Two-dimensional modes -------------------------------------------------------

{- | Rows of 8 pixels coded by hand with T.4 Table 4 against the reference row
"wwbbbbww" (changing elements 2 and 6), which the first two rows build.
-}
modeTests :: [TestTree]
modeTests =
  [ testCase "root ADR 0425 I8: V0 on an all-white reference ends a white row" $
      decodeBits 1 "1" @?= Right [rowOf "wwwwwwww"],
    testCase "root ADR 0425 I8: horizontal mode codes a white run of 2 and a black run of 4, then V0" $
      decodeBits 2 (prefix <> "") @?= Right [rowOf "wwwwwwww", reference],
    testCase "root ADR 0425 I8: VR1 twice moves both changing elements one pixel right" $
      decodeBits 3 (prefix <> "011" <> "011" <> "1") @?= Right [rowOf "wwwwwwww", reference, rowOf "wwwbbbbw"],
    testCase "root ADR 0425 I8: VL1 twice moves both changing elements one pixel left" $
      decodeBits 3 (prefix <> "010" <> "010" <> "1") @?= Right [rowOf "wwwwwwww", reference, rowOf "wbbbbwww"],
    testCase "root ADR 0425 I8: pass mode skips the black run of the reference" $
      decodeBits 3 (prefix <> "0001" <> "1") @?= Right [rowOf "wwwwwwww", reference, rowOf "wwwwwwww"],
    testCase "root ADR 0425 I8: VR3 then VR1" $
      decodeBits 3 (prefix <> "0000011" <> "011" <> "1") @?= Right [rowOf "wwwwwwww", reference, rowOf "wwwwwbbw"],
    testCase "root ADR 0425 I8: VL2 then VL3" $
      decodeBits 3 (prefix <> "000010" <> "0000010" <> "1") @?= Right [rowOf "wwwwwwww", reference, rowOf "bbbwwwww"],
    testCase "root ADR 0425 I8: VR2 twice ends the row at its right edge" $
      decodeBits 3 (prefix <> "000011" <> "000011") @?= Right [rowOf "wwwwwwww", reference, rowOf "wwwwbbbb"],
    testCase "root ADR 0425 I8: horizontal mode with a black run to the right edge" $
      decodeBits 3 (prefix <> "001" <> "0111" <> "0010") @?= Right [rowOf "wwwwwwww", reference, rowOf "wwbbbbbb"],
    testCase "root ADR 0425 I8: Group 3 two-dimensional rows follow their tag bits" $ do
      -- EOL, tag 1, 1-D "wwbbbbww"; EOL, tag 0, 2-D VR1 VR1 V0; RTC
      let eol = "000000000001"
          bits = eol <> "1" <> "0111" <> "011" <> "0111" <> eol <> "0" <> "011" <> "011" <> "1" <> concat (replicate 6 (eol <> "1"))
      decodeRows defaultCcittParams {ccittK = 2, ccittColumns = 8} 10 (bitsOf bits) @?= Right (BS.concat [reference, rowOf "wwwbbbbw"])
  ]
  where
    prefix = "1" <> "001" <> "0111" <> "011" <> "1"
    reference = rowOf "wwbbbbww"
    decodeBits n bits = splitRows 1 <$> decodeRows defaultCcittParams {ccittK = -1, ccittColumns = 8} n (bitsOf bits)

rowOf :: String -> ByteString
rowOf pixels = packRows False [map (== 'b') pixels]

-- | Bits written as 0 and 1, zero-padded to a byte.
bitsOf :: String -> ByteString
bitsOf bits = BS.pack (map byte (chunks bits))
  where
    chunks [] = []
    chunks xs = let (h, t) = splitAt 8 xs in take 8 (h <> repeat '0') : chunks t
    byte = foldl (\acc c -> acc * 2 + (if c == '1' then 1 else 0)) (0 :: Word8)

splitRows :: Int -> ByteString -> [ByteString]
splitRows size bytes
  | BS.null bytes = []
  | otherwise = BS.take size bytes : splitRows size (BS.drop size bytes)

-- Parameters -------------------------------------------------------------------

parameterTests :: [TestTree]
parameterTests =
  [ testCase "root ADR 0425 I8: BlackIs1 writes black as 1" $
      decodeRows defaultCcittParams {ccittK = -1, ccittColumns = 8, ccittBlackIs1 = True} 2 (bitsOf ("1" <> "001" <> "0111" <> "011" <> "1")) @?= Right (BS.pack [0x00, 0x3C]),
    testCase "root ADR 0425 I8: Rows stops the decoding before the end of the data" $
      decodeRows defaultCcittParams {ccittK = -1, ccittColumns = 8, ccittRows = 1} 10 (bitsOf ("1" <> "001" <> "0111" <> "011" <> "1")) @?= Right (BS.pack [0xFF]),
    testCase "root ADR 0425 I8: the limit of the caller stops the decoding" $
      decodeRows defaultCcittParams {ccittK = -1, ccittColumns = 8} 1 (bitsOf ("1" <> "001" <> "0111" <> "011" <> "1")) @?= Right (BS.pack [0xFF]),
    testCase "root ADR 0425 I8: without EOFB, trailing zero bits end the data" $
      decodeRows defaultCcittParams {ccittK = -1, ccittColumns = 8} 10 (bitsOf "1" <> BS.replicate 3 0) @?= Right (BS.pack [0xFF]),
    testCase "root ADR 0425 I8: Columns of 0 is an error" $
      assertBool "columns" (isLeft (decodeRows defaultCcittParams {ccittColumns = 0} 1 (bitsOf "1")))
  ]

-- Damage -----------------------------------------------------------------------

damageTests :: [TestTree]
damageTests =
  [ testCase "root ADR 0425 I8: a code of no table is an error" $
      assertBool "invalid" (isLeft (decodeRows g4 2 (bitsOf "00000000111111111111"))),
    testCase "root ADR 0425 I8: the extension mode is an error" $
      assertBool "extension" (isLeft (decodeRows g4 1 (bitsOf "0000001111"))),
    testCase "root ADR 0425 I8: a run past the end of the row is an error" $
      -- horizontal: white 9 on a row of 8
      assertBool "overflow" (isLeft (decodeRows g4 1 (bitsOf ("001" <> "10100" <> "0000110111")))),
    testCase "root ADR 0425 I8: a vertical changing element left of a0 is an error" $
      -- horizontal white 2 black 4 (a0 = 6), then VL3 against an all-white reference (b1 = 8, a1 = 5)
      assertBool "offset" (isLeft (decodeRows g4 1 (bitsOf ("001" <> "0111" <> "011" <> "0000010")))),
    testCase "root ADR 0425 I8: data that ends inside a row is an error" $
      assertBool "truncated" (isLeft (decodeRows g4 1 (bitsOf "001")))
  ]
  where
    g4 = defaultCcittParams {ccittK = -1, ccittColumns = 8}

-- Round trips ------------------------------------------------------------------

roundTrips :: [TestTree]
roundTrips =
  [ testProperty "root ADR 0425 I8: any picture survives encoding and decoding with any parameters" $ withTests 2000 $ property $ do
      height <- forAll (Gen.int (Range.linear 1 6))
      params <- forAll (genParams height)
      rows <- forAll (Gen.list (Range.singleton height) (genRow (ccittColumns params)))
      let encoded = encodeCcitt params rows
      decodeRows params 100 encoded === Right (packRows (ccittBlackIs1 params) rows),
    testCase "root ADR 0425 I8: a row of 5000 pixels with runs beyond 2560 survives every K" $
      mapM_
        ( \k -> do
            let params = defaultCcittParams {ccittK = k, ccittColumns = 5000, ccittRows = 3}
                rows = [replicate 2600 False <> replicate 2400 True, replicate 10 True <> replicate 4990 False, replicate 5000 True]
            decodeRows params 3 (encodeCcitt params rows) @?= Right (packRows False rows)
        )
        [-1, 0, 1, 2],
    testCase "root ADR 0425 I8: the changing elements of a row start from white" $
      changesOf [True, True, False, True] @?= [0, 2, 3]
  ]

genParams :: Int -> Gen CcittParams
genParams height = do
  k <- Gen.element [-1, 0, 1, 2, 4]
  eol <- if k < 0 then pure False else Gen.bool
  aligned <- Gen.bool
  endOfBlock <- Gen.bool
  blackIs1 <- Gen.bool
  columns <- Gen.int (Range.linear 1 40)
  let params = defaultCcittParams {ccittK = k, ccittEndOfLine = eol, ccittByteAlign = aligned, ccittColumns = columns, ccittEndOfBlock = endOfBlock, ccittBlackIs1 = blackIs1}
  -- Rows is needed when no RTC or EOFB ends the data
  rows <- if endMarked params then Gen.element [0, height] else pure height
  pure params {ccittRows = rows}

genRow :: Int -> Gen [Bool]
genRow columns = do
  style <- Gen.element [0 :: Int, 1, 2]
  case style of
    0 -> Gen.list (Range.singleton columns) Gen.bool
    1 -> pure (replicate columns False)
    _ -> do
      -- long runs, so that horizontal mode and long codes appear
      cut <- Gen.int (Range.linear 0 columns)
      pure (replicate cut True <> replicate (columns - cut) False)

decodeRows :: CcittParams -> Int -> ByteString -> Either String ByteString
decodeRows params limit = either (Left . show) Right . decodeCcitt params limit
