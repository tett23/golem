{- | The CharString operator random read deterministically (Golem ADR 0390):
the metrics FreeType gives, the library Golem makes, and the fonts of the
repository.

The test font @test/fonts/RandomSansPro-Regular.otf@ is Source Sans Pro
with the CharStrings of four glyphs rewritten in place, each to a program of
its length or shorter, the rest of it endchar. 'randomFont' rewrites it, and
a golden test keeps the committed file equal to what it gives (tasty-golden's
--accept writes it again). Source Sans Pro has the Reserved Font Name
"Source" under the SIL Open Font License, which a Modified Version may not
use, so the family and PostScript names become "Random Sans Pro" and
"RandomSansPro" with the same lengths; the copyright and trademark notices
are left as they are.

| glyph | character | program |
|---|---|---|
| 44 | q | random 1000 mul random 1000 mul rmoveto 500 0 rlineto 0 500 rlineto endchar |
| 29 | b | 1 random 0.5 sub div drop 100 0 rmoveto 500 0 rlineto 0 500 rlineto endchar |
| 31 | d | random 1 mul callsubr endchar |
| 49 | v | random 504 mul callsubr endchar |

The font has 611 local subroutines, so the bias is 107 and the largest
number a CharString may write is 503: the glyph v calls past the INDEX
(G08107), the glyph b divides by an interval holding 0 (G08108), and the
glyphs d and v give FreeType a number made by arithmetic, which it does
not take, so that their metrics cannot be read (G08109). The glyph q uses
random as coordinates only, so FreeType reads it and its box depends on the
values of random.
-}
module RandomFontSpec
  ( randomFontTests,
    randomFontPath,
    metricsChild,
  )
where

import Control.Monad (forM, forM_)
import Data.Bifunctor (bimap)
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Digest.Pure.SHA (sha256, showDigest)
import Data.List (isInfixOf, sort)
import Data.Maybe (isJust, isNothing)
import Data.Word (Word8)
import Golem.Font
import Golem.Font.Cff (CffResult (..), checkCffReferences, sfntCffTable)
import Golem.TestSupport.Parallel (inParallel)
import System.Directory (listDirectory)
import System.Environment (getEnvironment, getExecutablePath, setEnv, unsetEnv)
import System.Info (arch)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Tasty
import Test.Tasty.Golden.Advanced (goldenTest)
import Test.Tasty.HUnit

-- | Where the rewritten font is committed, from the package directory.
randomFontPath :: FilePath
randomFontPath = "test/fonts/RandomSansPro-Regular.otf"

-- | The font the rewritten one is made from.
originalPath :: FilePath
originalPath = "test/fonts/SourceSansPro-Regular.otf"

{- | Every font of the repository but the rewritten one, from the package
directory (Golem ADR 0390, I4 and A1).
-}
repositoryFonts :: [FilePath]
repositoryFonts =
  [ "../golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf",
    "../golem-driver/test/fixtures/tempest/fonts/SourceSerifVariable-Roman.ttf",
    "cbits/harfbuzz/src/wasm/sample/c/test.ttf",
    "test/fonts/SourceHanSans-Regular_subset.otf",
    "test/fonts/SourceSansPro-Regular.otf",
    "test/fonts/SourceSerif4Variable-Roman.otf",
    "test/fonts/SourceSerifVariable-Roman.ttf"
  ]

-- | The glyph whose box comes from random.
randomGlyph :: Int
randomGlyph = 44

-- | The glyphs rewritten and their programs.
rewrites :: [(Int, [Word8])]
rewrites =
  [ -- q: random 1000 mul random 1000 mul rmoveto 500 0 rlineto 0 500 rlineto endchar
    (44, [12, 23, 28, 3, 0xe8, 12, 24, 12, 23, 28, 3, 0xe8, 12, 24, 21, 28, 1, 0xf4, 139, 5, 139, 28, 1, 0xf4, 5, 14]),
    -- b: 1 random 0.5 sub div drop 100 0 rmoveto 500 0 rlineto 0 500 rlineto endchar
    (29, [140, 12, 23, 255, 0, 0, 0x80, 0, 12, 11, 12, 12, 12, 18, 239, 139, 21, 28, 1, 0xf4, 139, 5, 139, 28, 1, 0xf4, 5, 14]),
    -- d: random 1 mul callsubr endchar
    (31, [12, 23, 140, 12, 24, 10, 14]),
    -- v: random 504 mul callsubr endchar
    (49, [12, 23, 248, 140, 12, 24, 10, 14])
  ]

{- | Source Sans Pro with the 'rewrites' and the names of the module
header, every length and offset as it was.
-}
randomFont :: ByteString -> ByteString
randomFont original = rename (foldl rewrite original rewrites)
  where
    rewrite font (gid, program) =
      let (off, len) = charString font gid
       in if length program > len
            then error ("the CharString of glyph " <> show gid <> " is shorter than its program")
            else BS.take off font <> BS.pack program <> BS.replicate (len - length program) 14 <> BS.drop (off + len) font
    rename font = foldl (\f (from, to) -> replaceAll from to f) font (names <> map (bimap utf16 utf16) names)
    names = [("Source Sans Pro", "Random Sans Pro"), ("SourceSansPro", "RandomSansPro")]
    utf16 = BS.concatMap (\c -> BS.pack [0, c])

-- | Every occurrence of a string replaced by another of the same length.
replaceAll :: ByteString -> ByteString -> ByteString -> ByteString
replaceAll from to = go
  where
    go s = case BS.breakSubstring from s of
      (before, rest)
        | BS.null rest -> before
        | otherwise -> before <> to <> go (BS.drop (BS.length from) rest)

{- | The offset in the file and the length of the CharString of a glyph, from
the CFF table of an sfnt font: its header, Name INDEX, Top DICT INDEX, the
CharStrings operator (17) of the Top DICT and the CharStrings INDEX.
-}
charString :: ByteString -> Int -> (Int, Int)
charString font gid =
  let numTables = be 2 font 4
      base = case [be 4 font (r + 8) | k <- [0 .. numTables - 1], let r = 12 + 16 * k, BS.take 4 (BS.drop r font) == "CFF "] of
        b : _ -> b
        [] -> error "no CFF table"
      (_, afterNames) = index (base + be 1 font (base + 2))
      (topOff, topLen) = case fst (index afterNames) of
        top : _ -> top
        [] -> error "no Top DICT"
      charStrings = base + dictOperand (17 :: Int) (BS.take topLen (BS.drop topOff font))
      (entries, _) = index charStrings
   in entries !! gid
  where
    -- the entries of an INDEX (offset, length) and the offset after it
    index p =
      let count = be 2 font p
          size = be 1 font (p + 2)
          offs = [be size font (p + 3 + k * size) | k <- [0 .. count]]
          dataStart = p + 3 + (count + 1) * size - 1
       in if count == 0 then ([], p + 2) else (zip [dataStart + o | o <- offs] (zipWith (-) (drop 1 offs) offs), dataStart + last offs)
    -- the last integer operand of an operator of a DICT
    dictOperand :: Int -> ByteString -> Int
    dictOperand op = go []
      where
        go acc d = case BS.uncons d of
          Nothing -> error "no CharStrings in the Top DICT"
          Just (b, rest)
            | b == 12 -> go [] (BS.drop 1 rest)
            | fromIntegral b == op -> last acc
            | b <= 21 -> go [] rest
            | b == 28 -> go (acc <> [signed 16 (be 2 rest 0)]) (BS.drop 2 rest)
            | b == 29 -> go (acc <> [signed 32 (be 4 rest 0)]) (BS.drop 4 rest)
            | b == 30 -> go acc (BS.drop 1 (BS.dropWhile (\w -> w `mod` 16 /= 15 && w `div` 16 /= 15) rest))
            | b <= 246 -> go (acc <> [fromIntegral b - 139]) rest
            | b <= 250 -> go (acc <> [(fromIntegral b - 247) * 256 + fromIntegral (BS.index rest 0) + 108]) (BS.drop 1 rest)
            | otherwise -> go (acc <> [negate ((fromIntegral b - 251) * 256 + fromIntegral (BS.index rest 0) + 108)]) (BS.drop 1 rest)
    signed bits v = if v >= 2 ^ (bits - 1 :: Int) then v - 2 ^ bits else v

-- | A big-endian unsigned integer of n bytes.
be :: Int -> ByteString -> Int -> Int
be n b o = foldl (\a i -> a `shiftL` 8 .|. fromIntegral (BS.index b (o + i))) 0 [0 .. n - 1]

-- | The metrics of every glyph of a font as lines of text.
metricsText :: Font -> BL.ByteString
metricsText f = BL.fromStrict (BC.unlines [BC.pack (show g <> " " <> show (glyphMetrics f g)) | g <- [0 .. fontNumGlyphs f - 1]])

{- | What the suite does when it runs as the process that reads a glyph in
another environment (I1): the metrics of the glyph of a font file, given as
@path:glyph@, on the standard output.
-}
metricsChild :: String -> IO ()
metricsChild spec = do
  let (path, gid) = fmap (read . drop 1) (break (== ':') spec)
  f <- BS.readFile path >>= loadFont >>= either (fail . show) pure
  print (glyphMetrics f gid)

load :: ByteString -> IO Font
load b = loadFont b >>= either (assertFailure . show) pure

randomFontTests :: TestTree
randomFontTests =
  testGroup
    "random read deterministically (Golem ADR 0390)"
    [ goldenTest
        "ADR 0390 I1: the rewritten font is the rewriting of Source Sans Pro"
        (BS.readFile randomFontPath)
        (randomFont <$> BS.readFile originalPath)
        (\golden new -> pure (if golden == new then Nothing else Just "the rewritten font differs from the rewriting; --accept writes it again"))
        (BS.writeFile randomFontPath),
      testCase "ADR 0390 I1: the glyph whose box comes from random is read alike every way" $ do
        bytes <- BS.readFile randomFontPath
        first <- load bytes
        let m = glyphMetrics first randomGlyph
        assertBool "FreeType reads the glyph" (isJust m)
        -- the same glyph read twice from one font
        glyphMetrics first randomGlyph @?= m
        -- in another order: other glyphs with random first
        other <- load bytes
        mapM_ (\g -> pure $! glyphMetrics other g) [29, 31, 49]
        glyphMetrics other randomGlyph @?= m
        -- from two threads at once
        threads <- load bytes
        inParallel [pure (glyphMetrics threads g) | g <- [randomGlyph, 29, randomGlyph, 29]]
          >>= (@?= [Right m, Right (glyphMetrics threads 29), Right m, Right (glyphMetrics threads 29)])
        -- from two fonts opened apart
        a <- load bytes
        b <- load bytes
        (glyphMetrics a randomGlyph, glyphMetrics b randomGlyph) @?= (m, m)
        -- after another font is opened and read
        sans <- BS.readFile originalPath >>= load
        _ <- pure $! glyphMetrics sans randomGlyph
        later <- load bytes
        glyphMetrics later randomGlyph @?= m,
      testCase "ADR 0390 I1: a bare CFF file is read alike every time" $ do
        bare <- maybe (assertFailure "no CFF table") pure . sfntCffTable =<< BS.readFile randomFontPath
        a <- load bare
        let m = glyphMetrics a randomGlyph
        assertBool "FreeType reads the glyph of the bare CFF" (isJust m)
        glyphMetrics a randomGlyph @?= m
        b <- load bare
        glyphMetrics b randomGlyph @?= m,
      testCase "ADR 0390 I1: FREETYPE_PROPERTIES=cff:random-seed=777 does not change the glyph" $ do
        m <- (`glyphMetrics` randomGlyph) <$> (BS.readFile randomFontPath >>= load)
        out <-
          if arch == "wasm32"
            then -- no processes on wasm32: the variable is set in this one-threaded process
              do
                setEnv "FREETYPE_PROPERTIES" "cff:random-seed=777"
                f <- BS.readFile randomFontPath >>= load
                let r = glyphMetrics f randomGlyph
                _ <- pure $! r
                unsetEnv "FREETYPE_PROPERTIES"
                pure (show r <> "\n")
            else do
              exe <- getExecutablePath
              env <- filter ((`notElem` ["FREETYPE_PROPERTIES", "GOLEM_FONT_TEST_METRICS"]) . fst) <$> getEnvironment
              let vars = ("FREETYPE_PROPERTIES", "cff:random-seed=777") : ("GOLEM_FONT_TEST_METRICS", randomFontPath <> ":" <> show randomGlyph) : env
              (_, o, e) <- readCreateProcessWithExitCode (proc exe []) {env = Just vars} ""
              assertEqual "no error output" "" e
              pure o
        out @?= show m <> "\n",
      testCase "ADR 0390 I2: the C sources of golem-font call neither FT_Init_FreeType nor FT_Set_Default_Properties" $ do
        files <- sort <$> listDirectory "cbits/golem"
        assertBool "the C sources are found" ("golem_font.c" `elem` files)
        forM_ files $ \file -> do
          source <- BC.unpack <$> BS.readFile ("cbits/golem/" <> file)
          forM_ ["FT_Init_FreeType", "FT_Set_Default_Properties"] $ \name ->
            assertBool (file <> " names " <> name) (not (name `isInfixOf` source)),
      -- the fonts of the repository are loaded once: each glyph of a CFF font is read once
      withResource (forM repositoryFonts (\path -> BS.readFile path >>= \b -> (,,) path b <$> load b)) (const (pure ())) $ \fonts ->
        testGroup
          "the fonts of the repository"
          [ goldenTest
              "ADR 0390 I4: the metrics of every glyph of every font of the repository are those before ADR 0390"
              (BC.lines <$> BS.readFile "test/golden/adr-0390-metrics.txt")
              (map (\(path, _, f) -> BC.pack (path <> " " <> show (fontNumGlyphs f) <> " " <> showDigest (sha256 (metricsText f)))) <$> fonts)
              (\golden new -> pure (if golden == new then Nothing else Just (unlines ("expected:" : map BC.unpack golden <> ("but got:" : map BC.unpack new)))))
              (BS.writeFile "test/golden/adr-0390-metrics.txt" . BC.unlines),
            testCase "ADR 0390 A1: no glyph of a font of the repository is G08108 or G08109, nor runs random" $ do
              loaded <- fonts
              forM_ loaded $ \(path, bytes, f) -> do
                let gids = [0 .. fontNumGlyphs f - 1]
                    r = checkCffReferences bytes gids
                assertEqual (path <> ": G08108") [] (cffUnverifiable r)
                assertEqual (path <> ": random") [] (cffRandom r)
                assertEqual (path <> ": G08109") [] [g | g <- gids, isNothing (glyphMetrics f g)]
          ]
    ]
