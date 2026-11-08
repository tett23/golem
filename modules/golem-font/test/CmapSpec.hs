{- | The cmap subtables that FreeType refuses (docs/adr/0238, I3).

FreeType validates each cmap subtable in tt_face_build_cmaps; one that it
finds broken it leaves by longjmp, and it keeps the others. The input
broken-cmap of scripts/wasm/compare.sh is kanikosen with the entryCount of
the format 6 subtable of Noto Serif JP (the two bytes at 30205) set to FF
FF, so that golem.wasm goes through the exception handling of wasm there.
These tests make the broken fonts from the bytes of the font, and count the
charmaps of FreeType with a C function of the test suite.
-}
module CmapSpec (cmapTests) where

import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Unsafe (unsafeUseAsCStringLen)
import Data.Word (Word8)
import Foreign.C.Types (CInt (..), CSize (..))
import Foreign.Ptr (Ptr, castPtr)
import Test.Tasty
import Test.Tasty.HUnit

foreign import ccall safe "golem_test_num_charmaps" c_numCharmaps :: Ptr Word8 -> CSize -> IO CInt

-- | The num_charmaps of FreeType for the font, -1 when it cannot open it.
numCharmaps :: ByteString -> IO Int
numCharmaps b = unsafeUseAsCStringLen b $ \(p, n) -> fromIntegral <$> c_numCharmaps (castPtr p) (fromIntegral n)

-- | The cmap subtables, by their format and their offset from the start of the file.
subtables :: ByteString -> [(Int, Int)]
subtables font =
  [ (be16 o, o)
  | Just cmap <- [lookup "cmap" records],
    k <- [0 .. be16 (cmap + 2) - 1],
    let o = cmap + be32 (cmap + 4 + 8 * k + 4)
  ]
  where
    be16 i = fromIntegral (BS.index font i) `shiftL` 8 .|. fromIntegral (BS.index font (i + 1)) :: Int
    be32 i = be16 i `shiftL` 16 .|. be16 (i + 2)
    records = [(BS.take 4 (BS.drop r font), be32 (r + 8)) | k <- [0 .. be16 4 - 1], let r = 12 + 16 * k]

-- | The font with the two bytes at an offset replaced.
poke2 :: Int -> (Word8, Word8) -> ByteString -> ByteString
poke2 at (a, b) font = BS.take at font <> BS.pack [a, b] <> BS.drop (at + 2) font

-- | The offset of a field of the first subtable of the format.
field :: Int -> Int -> ByteString -> Maybe Int
field format off font = case [o | (f, o) <- subtables font, f == format] of
  o : _ -> Just (o + off)
  [] -> Nothing

cmapTests :: FilePath -> TestTree
cmapTests notoPath =
  testGroup
    "the cmap subtables that FreeType refuses (docs/adr/0238)"
    [ testCase "I3: the format 6 subtable broken as broken-cmap breaks it is left out: one charmap less" $ do
        noto <- BS.readFile notoPath
        -- entryCount of the format 6 subtable, which compare.sh sets to FF FF
        field 6 8 noto @?= Just 30205
        BS.unpack (BS.take 2 (BS.drop 30205 noto)) @?= [0x00, 0x01]
        before <- numCharmaps noto
        after <- numCharmaps (poke2 30205 (0xFF, 0xFF) noto)
        (before, after) @?= (6, 5),
      testCase "I3: a broken format 4 subtable, to which two encoding records point, is left out twice" $ do
        noto <- BS.readFile notoPath
        -- segCountX2 of the format 4 subtable
        at <- maybe (assertFailure "no format 4 subtable") pure (field 4 6 noto)
        before <- numCharmaps noto
        after <- numCharmaps (poke2 at (0xFF, 0xFE) noto)
        (before, after) @?= (6, 4)
    ]
