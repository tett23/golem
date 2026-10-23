module Main (main) where

import ConcurrencySpec (concurrencyTests, raceFactor)
import Control.Monad (void)
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Font
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

main :: IO ()
main = do
  han <- load "SourceHanSans-Regular_subset.otf"
  sans <- load "SourceSansPro-Regular.otf"
  serif <- BS.readFile "test/fonts/SourceSerifVariable-Roman.ttf"
  -- the subset of Source Han Sans has no palt; Noto Serif JP of golem-driver's 蟹工船 fixture has
  noto <- BS.readFile "../golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" >>= loadFont >>= either (fail . show) pure
  race <- raceFactor
  defaultMain (tests race han sans serif noto)

load :: FilePath -> IO Font
load name = do
  b <- BS.readFile ("test/fonts/" <> name)
  loadFont b >>= either (fail . show) pure

-- | A copy of the font with the OS/2 fsType set.
withFsType :: Int -> ByteString -> ByteString
withFsType v font =
  let numTables = be16 4
      be16 i = fromIntegral (BS.index font i) `shiftL` 8 .|. fromIntegral (BS.index font (i + 1)) :: Int
      be32 i = be16 i `shiftL` 16 .|. be16 (i + 2)
      records = [(BS.take 4 (BS.drop r font), be32 (r + 8)) | k <- [0 .. numTables - 1], let r = 12 + 16 * k]
   in case lookup "OS/2" records of
        Just off -> BS.take (off + 8) font <> BS.pack [fromIntegral (v `div` 256), fromIntegral v] <> BS.drop (off + 10) font
        Nothing -> font

render :: [(Int, Int, (Int, Int, Int, Int))] -> Text
render gs = T.unlines [T.pack (show g <> " @" <> show c <> " " <> show p) | (g, c, p) <- gs]

goldenShape :: String -> Font -> ShapeRequest -> TestTree
goldenShape name f req = goldenVsString name ("test/golden/" <> name <> ".txt") (pure (BL.fromStrict (TE.encodeUtf8 (render (shapeUnits f req)))))

tests :: Int -> Font -> Font -> ByteString -> Font -> TestTree
tests race han sans serif noto =
  testGroup
    "golem-font (ADR 0001, 0002)"
    [ testGroup
        "shaping"
        [ goldenShape "latin-ligature-kerning" sans (shapeRequest 1000 "office AVA Typography"),
          goldenShape "japanese-horizontal" han (shapeRequest 1000 "「日本語の組版」、ー。"),
          goldenShape "japanese-vertical" han ((shapeRequest 1000 "「日本語の組版」、ー。") {srDirection = Vertical}),
          testCase "vertical forms differ from horizontal ones for brackets and marks" $ do
            let h = [g | (g, _, _) <- shapeUnits han (shapeRequest 1000 "「、ー")]
                v = [g | (g, _, _) <- shapeUnits han ((shapeRequest 1000 "「、ー") {srDirection = Vertical})]
            assertBool (show (h, v)) (and (zipWith (/=) h v)),
          testCase "palt moves a bracket within its narrowed box; without palt it has no offset (golem-driver ADR 0020)" $ do
            let offsets feats = [(xo, yo) | (_, _, (_, _, xo, yo)) <- shapeUnits noto ((shapeRequest 1000 "「") {srFeatures = feats})]
            case offsets ["palt"] of
              [(xo, _)] -> assertBool "x offset with palt" (xo /= 0)
              other -> assertFailure (show other)
            offsets ["-palt"] @?= [(0, 0)],
          testCase "vertical shaping gives offsets less the vertical origin (golem-driver ADR 0020)" $ do
            let vertical feats t = [(xo + ox, yo + oy) | (g, _, (_, _, xo, yo)) <- shapeUnits han ((shapeRequest 1000 t) {srDirection = Vertical, srFeatures = feats}), let (ox, oy) = glyphVerticalOrigin han g]
            vertical [] "漢" @?= [(0, 0)]
            case vertical ["vpal"] "「" of
              [(_, yo)] -> assertBool "y offset with vpal" (yo /= 0)
              other -> assertFailure (show other),
          testCase "the ff ligature is one glyph whose cluster covers two letters" $ do
            let gs = shape sans (shapeRequest (10 * 65536) "office")
            length gs @?= 5
            map sgCluster gs @?= [0, 1, 3, 4, 5]
        ],
      testGroup
        "licence and units"
        [ testCase "a font whose fsType forbids embedding is an error" $ do
            loadFont serif >>= (@?= Right ()) . void
            loadFont (withFsType 0x0002 serif) >>= (@?= Left (EmbeddingRestricted 0x0002)) . void
            loadFont (withFsType 0x0200 serif) >>= (@?= Left (EmbeddingRestricted 0x0200)) . void
            loadFont (withFsType 0x0008 serif) >>= (@?= Right ()) . void,
          testCase "CFF2 outlines are told from CFF and glyf ones (golem-font ADR 0003)" $ do
            cff2 <- load "SourceSerif4Variable-Roman.otf"
            glyfVariable <- loadFont serif >>= either (assertFailure . show) pure
            map fontIsCff2 [cff2, sans, glyfVariable] @?= [True, False, False]
            map fontIsCff [cff2, sans, glyfVariable] @?= [False, True, False],
          testCase "fsType as the OpenType specification reads it: the least restrictive usage, no subsetting (golem-driver ADR 0016)" $ do
            sequence_ [loadFont (withFsType v serif) >>= (@?= Left (EmbeddingRestricted v)) . void | v <- [0x0102, 0x0100, 0x0302]]
            sequence_ [loadFont (withFsType v serif) >>= (@?= Right ()) . void | v <- [0x0000, 0x0004, 0x0008, 0x0006, 0x000A]],
          testCase "units are converted to sp with a single rounding" $ do
            -- 333 units of 1000 at 10.5pt: 333 × 688128 / 1000 = 229146.624
            unitsToSp 1000 688128 333 @?= 229147
            -- rounding each step separately would give a different value
            unitsToSp 1000 688128 333 /= round (fromIntegral (round (333 / 1000 * 10.5 * 100 :: Double) :: Integer) / 100 * 65536 :: Double) @?= True
            -- half to even
            unitsToSp 2 1 1 @?= 0
            unitsToSp 2 3 1 @?= 2,
          testCase "the centre of the ideographic em box lies within the extents (golem-driver ADR 0015)" $ do
            let (asc, desc, _) = fontExtents han
                c = fontEmBoxCentral han
            assertBool (show (desc, c, asc)) (desc < c && c < asc)
            -- the subset has no BASE table: HarfBuzz takes the middle of the hhea ascender (1160) and descender (-320)
            c @?= 420,
          testCase "metrics come from FreeType in font units" $ do
            fontUnitsPerEm han @?= 1000
            case glyphMetrics han (head' [g | (g, _, _) <- shapeUnits han (shapeRequest 1000 "日")]) of
              Just m -> gmAdvance m @?= 1000
              Nothing -> assertFailure "no metrics"
        ],
      testGroup
        "subsetting (ADR 0002)"
        [ testCase "the same glyph set gives the same bytes" $ do
            let gids = [g | (g, _, _) <- shapeUnits han (shapeRequest 1000 "日本語の組版")]
            a <- subsetFont han gids
            b <- subsetFont han (reverse gids)
            a @?= b
            assertBool "non-empty" (maybe False ((> 100) . BS.length) a),
          testCase "used glyphs stay with their ids; unused ones are emptied" $ do
            let used = [g | (g, _, _) <- shapeUnits han (shapeRequest 1000 "日本")]
                unused = head' [g | (g, _, _) <- shapeUnits han (shapeRequest 1000 "語")]
            sub <- subsetFont han used >>= maybe (assertFailure "subset failed") pure
            f <- loadFont sub >>= either (assertFailure . show) pure
            [g | (g, _, _) <- shapeUnits han (shapeRequest 1000 "日本")] @?= used
            mapM_ (assertBool "outline kept" . maybe False ((/= (0, 0, 0, 0)) . gmBBox) . glyphMetrics f) used
            assertBool "outline dropped" (maybe True ((== (0, 0, 0, 0)) . gmBBox) (glyphMetrics f unused)),
          testCase "the subset tag comes from the glyph set" $ do
            subsetTag [3, 1, 2] @?= subsetTag [1, 2, 3, 3]
            assertBool "differs" (subsetTag [1, 2, 3] /= subsetTag [1, 2, 4])
            T.length (subsetTag [1]) @?= 6
            assertBool "upper case" (T.all (`elem` ['A' .. 'Z']) (subsetTag [1, 2]))
            -- FNV-1a over the sorted set, six base-26 digits from the low end; the tag is in the bytes of every PDF
            map subsetTag [[], [0], [1], [1, 2, 3], [65535]] @?= ["BYZWAK", "FHVIXO", "WVLLDI", "PYHSSW", "SSGMLZ"]
        ],
      testGroup
        "CIDSystemInfo (golem-pdf ADR 0006)"
        [ testCase "a CID-keyed CFF font has its ROS" $
            fontCidSystemInfo han @?= Just (CidSystemInfo "Adobe" "Identity" 0),
          testCase "a name-keyed CFF font and a TrueType font have none" $ do
            fontCidSystemInfo sans @?= Nothing
            f <- loadFont serif >>= either (assertFailure . show) pure
            fontCidSystemInfo f @?= Nothing,
          testCase "a subset keeps the ROS and the CIDs of the glyphs used" $ do
            let used = [g | (g, _, _) <- shapeUnits han (shapeRequest 1000 "「日本語の組版」、ー。")]
            sub <- subsetFont han used >>= maybe (assertFailure "subset failed") pure
            f <- loadFont sub >>= either (assertFailure . show) pure
            fontCidSystemInfo f @?= fontCidSystemInfo han
            map (glyphCid f) used @?= map (glyphCid han) used,
          testCase "a glyph id outside a CID-keyed font is its own CID (docs/adr ADR 0034)" $ do
            let n = fontNumGlyphs han
            map (glyphCid han) [n, n + 1, n + 1000] @?= [n, n + 1, n + 1000]
            glyphCid han 0 @?= 0,
          testCase "a font that is not CID-keyed gives the glyph id as the CID" $
            map (glyphCid sans) [0, 1, 2, fontNumGlyphs sans + 3] @?= [0, 1, 2, fontNumGlyphs sans + 3]
        ],
      concurrencyTests race han noto
    ]
  where
    head' (x : _) = x
    head' [] = -1
