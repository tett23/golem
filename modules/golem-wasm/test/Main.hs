-- | The frames of the wasm entry point (docs/adr/0199).
module Main (main) where

import Data.Bits (shiftL, (.|.))
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

{- | The reading of the frames before the security audit of 2026-11-08
(W-01), whose check of duplicates is quadratic: the reference for the
errors of 'readFiles', in particular which one comes first.
-}
readFilesByList :: BS.ByteString -> Either FrameError [(FilePath, BS.ByteString)]
readFilesByList = go [] []
  where
    go seen acc bs
      | BS.null bs = Right (reverse acc)
      | otherwise = do
          (rawPath, rest) <- field bs
          (content, rest') <- field rest
          p <- either (const (Left (NotUtf8 rawPath))) Right (readPath rawPath)
          if not (isNormalized p)
            then Left (NotNormalized p)
            else
              if p `elem` seen
                then Left (Duplicate p)
                else go (p : seen) ((p, content) : acc) rest'
    field bs
      | BS.length bs < 4 = Left Truncated
      | otherwise =
          let (h, rest) = BS.splitAt 4 bs
              n = foldr (\b m -> m `shiftL` 8 .|. toInteger b) 0 (BS.unpack h)
           in if n > toInteger (BS.length rest) then Left Truncated else Right (BS.splitAt (fromInteger n) rest)
    -- the path of one file alone, through readFiles itself
    readPath raw = case readFiles (BS.pack (le32 (BS.length raw)) <> raw <> BS.pack (le32 0)) of
      Right [(p, _)] -> Right p
      Left (NotNormalized p) -> Right p
      other -> Left other

{- | A frame that may not be read: files whose paths come from a few, so
that some come twice, and one of them, perhaps, not normalised, not
UTF-8, or cut short.
-}
anyFrame :: Gen BS.ByteString
anyFrame = do
  pool <- Gen.list (Range.linear 1 6) path
  ps <- Gen.list (Range.linear 0 30) (Gen.element pool)
  fs <- mapM (\p -> (p,) <$> Gen.bytes (Range.linear 0 4)) ps
  let whole = writeFiles fs
  Gen.choice
    [ pure whole,
      (`BS.take` whole) <$> Gen.int (Range.linear 0 (BS.length whole)),
      (\bad -> whole <> writeFiles [(bad, "")]) <$> Gen.element ["./a.gm", "a//b.gm", "/a.gm"],
      pure (whole <> BS.pack (le32 1 <> [0xFF] <> le32 0) <> writeFiles fs)
    ]

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
    [ testProperty "F3: the files written and read again are the same" $ property $ do
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
      testCase "the first path that comes again is the duplicate, and an error before it comes first" $ do
        readFiles (writeFiles [("b.gm", ""), ("a.gm", ""), ("a.gm", ""), ("b.gm", "")]) @?= Left (Duplicate "a.gm")
        readFiles (writeFiles [("a.gm", ""), ("./b.gm", ""), ("a.gm", "")]) @?= Left (NotNormalized "./b.gm")
        readFiles (writeFiles [("a.gm", ""), ("a.gm", ""), ("./b.gm", "")]) @?= Left (Duplicate "a.gm")
        readFiles (writeFiles [("a.gm", ""), ("a.gm", "")] <> BS.pack [1]) @?= Left (Duplicate "a.gm"),
      testCase "F1: an empty path is refused (docs/adr/0225)" $
        readFiles (writeFiles [("", "x")]) @?= Left EmptyPath,
      testCase "F1, F2: the error of the first file that cannot be taken, and of the first of its conditions (docs/adr/0225)" $ do
        -- the paths of the boundaries: "." and "a/.." are made "" by
        -- normalizeRelative but are not "", "/" is absolute
        readFiles (writeFiles [(".", "")]) @?= Left (NotNormalized ".")
        readFiles (writeFiles [("a/..", "")]) @?= Left (NotNormalized "a/..")
        readFiles (writeFiles [("/", "")]) @?= Left (NotNormalized "/")
        readFiles (writeFiles [("a", "")]) @?= Right [("a", "")]
        -- the empty path first, in the middle and last; the content empty or one byte
        readFiles (writeFiles [("", ""), ("a.gm", "1")]) @?= Left EmptyPath
        readFiles (writeFiles [("a.gm", "1"), ("", "x"), ("b.gm", "")]) @?= Left EmptyPath
        readFiles (writeFiles [("a.gm", ""), ("b.gm", ""), ("", "")]) @?= Left EmptyPath
        -- a duplicate before the empty path comes first; after it, the empty path
        readFiles (writeFiles [("a.gm", ""), ("a.gm", ""), ("", "")]) @?= Left (Duplicate "a.gm")
        readFiles (writeFiles [("a.gm", ""), ("", ""), ("a.gm", "")]) @?= Left EmptyPath
        -- the empty path twice: the first
        readFiles (writeFiles [("", ""), ("", "")]) @?= Left EmptyPath
        -- a file cut short before it
        readFiles (BS.pack (le32 100 <> [0x61]) <> writeFiles [("", "")]) @?= Left Truncated
        readFiles (writeFiles [("", "")] <> BS.pack [1]) @?= Left EmptyPath
        -- a path not UTF-8 before it
        readFiles (BS.pack (le32 1 <> [0xFF] <> le32 0) <> writeFiles [("", "")]) @?= Left (NotUtf8 (BS.pack [0xFF])),
      testProperty "F3: every frame is read as the quadratic check of duplicates read it" $ withTests 1000 $ property $ do
        frame <- forAll anyFrame
        readFiles frame === readFilesByList frame,
      -- 200,000 files take minutes with a check of every earlier path (the
      -- security audit of 2026-11-08, W-01: 40,000 took 16 s natively)
      localOption (mkTimeout 30000000) $ testCase "a frame of 200,000 files is read in less than half a minute" $ do
        let many = [(show i <> ".gm", "") | i <- [1 :: Int .. 200000]]
        fmap length (readFiles (writeFiles many)) @?= Right 200000
        readFiles (writeFiles (many <> [("1.gm", "")])) @?= Left (Duplicate "1.gm"),
      testCase "every input that cannot be read is the result of status 1, without a build" $
        mapM_
          (\input -> respond noBuild input >>= (@?= unreadable))
          [ BS.pack [1, 2],
            writeFiles [("./a.gm", "")],
            writeFiles [("a.gm", ""), ("a.gm", "")],
            writeFiles [("", "x")],
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
