-- | The frames of the wasm entry point (docs/adr/0199).
module Main (main) where

import Data.ByteString qualified as BS
import Data.List (nub)
import Data.Word (Word8)
import Golem.Wasm.Frame
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

main :: IO ()
main = defaultMain tests

-- | A path segment: ASCII or Japanese, never . nor .. nor empty.
segment :: Gen String
segment = Gen.filter (`notElem` [".", ".."]) (Gen.string (Range.linear 1 8) (Gen.choice [Gen.alphaNum, Gen.element (".-_" :: String), Gen.element ("章蟹工船あ" :: String)]))

-- | A normalised path of one to four segments.
path :: Gen FilePath
path = foldr1 (\a b -> a <> "/" <> b) <$> Gen.list (Range.linear 1 4) segment

-- | Files with distinct paths.
files :: Gen [(FilePath, BS.ByteString)]
files = do
  ps <- nub <$> Gen.list (Range.linear 0 10) path
  mapM (\p -> (p,) <$> Gen.bytes (Range.linear 0 200)) ps

-- | The bytes of a little-endian uint32.
le32 :: Int -> [Word8]
le32 n = map (\s -> fromIntegral (n `div` (256 ^ s) `mod` 256)) [0 :: Int .. 3]

-- | A call of the entry point that must not build.
noBuild :: [(FilePath, BS.ByteString)] -> IO (Maybe BS.ByteString, BS.ByteString)
noBuild fs = assertFailure ("built " <> show (map fst fs)) >> pure (Nothing, BS.empty)

unreadable :: BS.ByteString
unreadable = BS.pack [1, 0, 0, 0, 0, 0, 0, 0, 0]

tests :: TestTree
tests =
  testGroup
    "golem-wasm: the frames (docs/adr/0199)"
    [ testProperty "the files written and read again are the same" $ property $ do
        fs <- forAll files
        readFiles (writeFiles fs) === Right fs,
      testCase "an input frame is lengths, paths and contents, little-endian" $
        writeFiles [("a.gm", "xyz")] @?= BS.pack (le32 4 <> map (fromIntegral . fromEnum) "a.gm" <> le32 3 <> map (fromIntegral . fromEnum) "xyz"),
      testCase "the empty input is no file" $ readFiles BS.empty @?= Right [],
      testCase "a frame cut short is refused" $ do
        let whole = writeFiles [("a.gm", "abc"), ("b.gm", "")]
        mapM_ (\n -> readFiles (BS.take n whole) @?= Left Truncated) ([1 .. 3] <> [5 .. 7] <> [BS.length whole - 1])
        readFiles (BS.pack (le32 100 <> [0x61])) @?= Left Truncated,
      testCase "a path that is not UTF-8 is refused" $ do
        let frame = BS.pack (le32 1 <> [0xFF] <> le32 0)
        readFiles frame @?= Left (NotUtf8 (BS.pack [0xFF]))
        -- an overlong /, a surrogate, a sequence cut short
        mapM_ (\bad -> readFiles (BS.pack (le32 (length bad) <> bad <> le32 0)) @?= Left (NotUtf8 (BS.pack bad))) [[0xC0, 0xAF], [0xED, 0xA0, 0x80], [0xE3, 0x81]],
      testCase "paths that normalizeRelative changes or rejects are refused" $
        mapM_
          (\p -> readFiles (writeFiles [(p, "x")]) @?= Left (NotNormalized p))
          ["./a.gm", "a//b.gm", "../a.gm", "a/./b.gm", "a/../b.gm", "a/", "/a.gm", "https://example.com/a.gm"],
      testCase "normalised paths are taken" $
        mapM_ (\p -> assertBool p (isNormalized p)) ["manifest.toml", "fonts/NotoSerifJP-Regular.otf", "章/一.gm", "a..b/.c"],
      testCase "a path twice is refused" $
        readFiles (writeFiles [("a.gm", "1"), ("b.gm", "2"), ("a.gm", "3")]) @?= Left (Duplicate "a.gm"),
      testCase "every input that cannot be read is the result of status 1, without a build" $
        mapM_
          (\input -> respond noBuild input >>= (@?= unreadable))
          [ BS.pack [1, 2],
            writeFiles [("./a.gm", "")],
            writeFiles [("a.gm", ""), ("a.gm", "")],
            BS.pack (le32 1 <> [0xFF] <> le32 0)
          ],
      testCase "the result frames (golden)" $ do
        writeResult (Built (Just "%PDF") "[]\n") @?= BS.pack ([0] <> le32 4 <> [0x25, 0x50, 0x44, 0x46] <> le32 3 <> [0x5B, 0x5D, 0x0A])
        writeResult (Built Nothing "[{}]\n") @?= BS.pack ([0] <> le32 0 <> le32 5 <> [0x5B, 0x7B, 0x7D, 0x5D, 0x0A])
        writeResult Unreadable @?= unreadable,
      testCase "an input that can be read is built from its files" $ do
        r <- respond (\fs -> pure (Just (BS.concat (map snd fs)), "[]\n")) (writeFiles [("a.gm", "ab"), ("b/c.gm", "c")])
        r @?= writeResult (Built (Just "abc") "[]\n")
    ]
