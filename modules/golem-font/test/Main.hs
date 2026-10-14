module Main (main) where

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
  defaultMain (tests han sans serif)

load :: FilePath -> IO Font
load name = do
  b <- BS.readFile ("test/fonts/" <> name)
  either (fail . show) pure (loadFont b)

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

tests :: Font -> Font -> ByteString -> TestTree
tests han sans serif =
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
          testCase "the ff ligature is one glyph whose cluster covers two letters" $ do
            let gs = shape sans (shapeRequest (10 * 65536) "office")
            length gs @?= 5
            map sgCluster gs @?= [0, 1, 3, 4, 5]
        ],
      testGroup
        "licence and units"
        [ testCase "a font whose fsType forbids embedding is an error" $ do
            void (loadFont serif) @?= Right ()
            void (loadFont (withFsType 0x0002 serif)) @?= Left (EmbeddingRestricted 0x0002)
            void (loadFont (withFsType 0x0200 serif)) @?= Left (EmbeddingRestricted 0x0200)
            void (loadFont (withFsType 0x0008 serif)) @?= Right (),
          testCase "fsType as the OpenType specification reads it: the least restrictive usage, no subsetting (golem-driver ADR 0016)" $ do
            sequence_ [void (loadFont (withFsType v serif)) @?= Left (EmbeddingRestricted v) | v <- [0x0102, 0x0100, 0x0302]]
            sequence_ [void (loadFont (withFsType v serif)) @?= Right () | v <- [0x0000, 0x0004, 0x0008, 0x0006, 0x000A]],
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
            subsetFont han gids @?= subsetFont han (reverse gids)
            assertBool "non-empty" (maybe False ((> 100) . BS.length) (subsetFont han gids)),
          testCase "used glyphs stay with their ids; unused ones are emptied" $ do
            let used = [g | (g, _, _) <- shapeUnits han (shapeRequest 1000 "日本")]
                unused = head' [g | (g, _, _) <- shapeUnits han (shapeRequest 1000 "語")]
            sub <- maybe (assertFailure "subset failed") pure (subsetFont han used)
            f <- either (assertFailure . show) pure (loadFont sub)
            [g | (g, _, _) <- shapeUnits han (shapeRequest 1000 "日本")] @?= used
            mapM_ (assertBool "outline kept" . maybe False ((/= (0, 0, 0, 0)) . gmBBox) . glyphMetrics f) used
            assertBool "outline dropped" (maybe True ((== (0, 0, 0, 0)) . gmBBox) (glyphMetrics f unused)),
          testCase "the subset tag comes from the glyph set" $ do
            subsetTag [3, 1, 2] @?= subsetTag [1, 2, 3, 3]
            assertBool "differs" (subsetTag [1, 2, 3] /= subsetTag [1, 2, 4])
            T.length (subsetTag [1]) @?= 6
            assertBool "upper case" (T.all (`elem` ['A' .. 'Z']) (subsetTag [1, 2])),
          testCase "ToUnicode: ligatures map to their text, the first mapping wins" $ do
            let run t = (t, shape sans (shapeRequest 65536 t))
                m = toUnicode [run "office", run "fit"]
                ff = head' [sgGlyphId g | g <- snd (run "office"), sgCluster g == 1]
            lookup ff m @?= Just "ff"
            lookup (head' [sgGlyphId g | g <- snd (run "office")]) m @?= Just "o"
        ],
      testGroup
        "CIDSystemInfo (golem-pdf ADR 0006)"
        [ testCase "a CID-keyed CFF font has its ROS" $
            fontCidSystemInfo han @?= Just (CidSystemInfo "Adobe" "Identity" 0),
          testCase "a name-keyed CFF font and a TrueType font have none" $ do
            fontCidSystemInfo sans @?= Nothing
            f <- either (assertFailure . show) pure (loadFont serif)
            fontCidSystemInfo f @?= Nothing,
          testCase "a subset keeps the ROS and the CIDs of the glyphs used" $ do
            let used = [g | (g, _, _) <- shapeUnits han (shapeRequest 1000 "「日本語の組版」、ー。")]
            sub <- maybe (assertFailure "subset failed") pure (subsetFont han used)
            f <- either (assertFailure . show) pure (loadFont sub)
            fontCidSystemInfo f @?= fontCidSystemInfo han
            map (glyphCid f) used @?= map (glyphCid han) used
        ]
    ]
  where
    head' (x : _) = x
    head' [] = -1
