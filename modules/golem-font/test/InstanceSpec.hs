{- | The instance of a variable font that a role names (Golem ADR 0358, I1):
the coordinates of every axis that HarfBuzz shapes with, that FreeType
measures with and that the subset is fixed at are the same.

The fixture is Source Serif Variable (glyf outlines), whose one axis wght
runs from 200 to 900 with its default between Light (300) and Regular
(400), and whose named instances are ExtraLight, Light, Regular, Semibold,
Bold and Black.
-}
module InstanceSpec (instanceTests) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Golem.Font
import Hedgehog (annotateShow, evalIO, forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

instanceTests :: ByteString -> ByteString -> TestTree
instanceTests serif sans =
  testGroup
    "the instance of a variable font (Golem ADR 0358)"
    [ testPropertyNamed "ADR 0358 I1: inv1_font_instance_selection_property" "inv1_font_instance_selection_property" $ property $ do
        name <- forAll (Gen.maybe (Gen.element (map fst instances)))
        wght <- forAll (Gen.maybe (Gen.element [200, 900] `orDouble` Gen.double (Range.linearFrac 200 900)))
        f <- evalIO (loadFontAt (FontInstance name [("wght", w) | Just w <- [wght]]) serif) >>= either (fail . show) pure
        let expected = fromMaybe (maybe defaultWght (`lookupOr` instances) name) wght
        annotateShow (fontCoordinates f)
        map fst (fontCoordinates f) === ["wght"]
        -- the coordinates, in the precision of fvar (16.16); the three hold them as floats (HarfBuzz reads fvar so)
        [fixed v | (_, v) <- fontCoordinates f] === [fixed expected]
        shaping <- evalIO (fontCoordinatesFor CoordinatesShaping f)
        metrics <- evalIO (fontCoordinatesFor CoordinatesMetrics f)
        subset <- evalIO (fontCoordinatesFor CoordinatesSubset f)
        shaping === asFloat (fontCoordinates f)
        metrics === asFloat (fontCoordinates f)
        subset === asFloat (fontCoordinates f),
      testCase "ADR 0358 I1: inv1_font_instance_selection_case_1: no instance and no axes: the default coordinates" $ do
        f <- loaded (loadFontAt defaultInstance serif)
        map (fmap fixed) (fontCoordinates f) @?= [("wght", fixed defaultWght)]
        sequence_ [fontCoordinatesFor u f >>= (@?= asFloat (fontCoordinates f)) | u <- [CoordinatesShaping, CoordinatesMetrics, CoordinatesSubset]]
        -- loadFont is the default instance
        g <- loaded (loadFont serif)
        fontCoordinates g @?= fontCoordinates f,
      testCase "ADR 0358 I1: inv1_font_instance_selection_case_2: the upper end of the axis is accepted" $ do
        f <- loaded (loadFontAt (FontInstance Nothing [("wght", 900)]) serif)
        fontCoordinates f @?= [("wght", 900)]
        sequence_ [fontCoordinatesFor u f >>= (@?= [("wght", 900 :: Float)]) | u <- [CoordinatesShaping, CoordinatesMetrics, CoordinatesSubset]]
        g <- loaded (loadFontAt (FontInstance Nothing [("wght", 200)]) serif)
        fontCoordinates g @?= [("wght", 200)],
      testCase "ADR 0358 I1: inv1_font_instance_selection_case_3: past the upper end is rejected" $ do
        r <- loadFontAt (FontInstance Nothing [("wght", 900.5)]) serif
        either Just (const Nothing) r @?= Just (InstanceErrors [AxisOutOfRange "wght" 900.5 (200, 900)])
        below <- loadFontAt (FontInstance Nothing [("wght", 199.99)]) serif
        either Just (const Nothing) below @?= Just (InstanceErrors [AxisOutOfRange "wght" 199.99 (200, 900)]),
      testCase "ADR 0358: a named instance gives its coordinates; an axis written overrides them" $ do
        bold <- loaded (loadFontAt (FontInstance (Just "Bold") []) serif)
        fontCoordinates bold @?= [("wght", 700)]
        both <- loaded (loadFontAt (FontInstance (Just "Bold") [("wght", 650)]) serif)
        fontCoordinates both @?= [("wght", 650)],
      testCase "ADR 0358: an unknown name, an unknown axis: rejected, every one" $ do
        r <- loadFontAt (FontInstance (Just "Heavy") [("wdth", 90), ("wght", 1000)]) serif
        either Just (const Nothing) r @?= Just (InstanceErrors [UnknownInstance "Heavy", UnknownAxis "wdth", AxisOutOfRange "wght" 1000 (200, 900)])
        -- the names are compared as they are written
        lower <- loadFontAt (FontInstance (Just "bold") []) serif
        either Just (const Nothing) lower @?= Just (InstanceErrors [UnknownInstance "bold"]),
      testCase "ADR 0358: a font that is not variable has no instance and no axis" $ do
        r <- loadFontAt (FontInstance (Just "Bold") [("wght", 700)]) sans
        either Just (const Nothing) r @?= Just (InstanceErrors [UnknownInstance "Bold", UnknownAxis "wght"])
        f <- loaded (loadFontAt defaultInstance sans)
        fontCoordinates f @?= []
        fontAxes f @?= [],
      testCase "ADR 0358: the axes of the font, in the order of fvar" $ do
        f <- loaded (loadFont serif)
        [(axisTag a, axisMinimum a, axisMaximum a) | a <- fontAxes f] @?= [("wght", 200, 900)]
        [fixed (axisDefault a) | a <- fontAxes f] @?= [fixed defaultWght],
      testCase "ADR 0358: the subset is fixed at the coordinates: no variation tables, the advances of the instance" $ do
        regular <- loaded (loadFont serif)
        bold <- loaded (loadFontAt (FontInstance (Just "Bold") []) serif)
        let gids f = [g | (g, _, _) <- shapeUnits f (shapeRequest "Hamburgefonstiv")]
            advances f = [(g, gmAdvance <$> glyphMetrics f g) | g <- gids f]
        -- the instance shapes and measures at its own coordinates
        assertBool "Bold is wider than the default" (sum [a | (_, (_, _, (a, _, _, _))) <- zip [0 :: Int ..] (shapeUnits bold (shapeRequest "Hamburgefonstiv"))] > sum [a | (_, _, (a, _, _, _)) <- shapeUnits regular (shapeRequest "Hamburgefonstiv")])
        -- without kerning, the advances of shaping are those of the metrics
        [a | (_, _, (a, _, _, _)) <- shapeUnits bold ((shapeRequest "Hamburgefonstiv") {srFeatures = ["-kern"]})] @?= [fromMaybe 0 a | (_, a) <- advances bold]
        sequence_
          [ do
              Just sub <- subsetFont f (gids f)
              mapM_ (\t -> assertBool (show t) (not (hasTable t sub))) ["fvar", "gvar", "HVAR", "MVAR", "avar"]
              static <- loaded (loadFont sub)
              fontAxes static @?= []
              [(g, gmAdvance <$> glyphMetrics static g) | g <- gids f] @?= advances f
          | f <- [regular, bold]
          ],
      testCase "ADR 0358: each instance has its own PostScript name" $ do
        regular <- loaded (loadFont serif)
        bold <- loaded (loadFontAt (FontInstance (Just "Bold") []) serif)
        other <- loaded (loadFontAt (FontInstance Nothing [("wght", 650)]) serif)
        fontPostScriptName regular @?= "SourceSerifVariable-Roman"
        assertBool (show (map fontPostScriptName [regular, bold, other])) (length (distinct (map fontPostScriptName [regular, bold, other])) == 3)
    ]
  where
    loaded io = io >>= either (assertFailure . show) pure
    instances :: [(Text, Double)]
    instances = [("ExtraLight", 200), ("Light", 300), ("Regular", 400), ("Semibold", 600), ("Bold", 700), ("Black", 900)]
    lookupOr k xs = fromMaybe defaultWght (lookup k xs)
    -- the default of wght in fvar (25516065 in 16.16)
    defaultWght = 389.34425354003906
    asFloat cs = [(t, realToFrac v :: Float) | (t, v) <- cs]
    fixed v = round (v * 65536) :: Integer
    orDouble a b = Gen.choice [a, b]
    distinct = foldr (\x acc -> if x `elem` acc then acc else x : acc) []

-- | Whether an sfnt font has a table.
hasTable :: ByteString -> ByteString -> Bool
hasTable tag font = tag `elem` [BS.take 4 (BS.drop (12 + 16 * i) font) | i <- [0 .. numTables - 1]]
  where
    numTables = fromIntegral (BS.index font 4) * 256 + fromIntegral (BS.index font 5) :: Int
