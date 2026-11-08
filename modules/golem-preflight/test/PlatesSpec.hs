{- | G09019 to G09021 (docs/adr ADR 0232): fonts not embedded, spot
colour spaces and colours on the C, M and Y plates, on hand-made views.
The numbers of the tests are those of the invariants of the ADR.
-}
module PlatesSpec (tests, viewWith) where

import Data.List (nub, sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Length (Sp (..))
import Golem.Pdf (Paint (..), PaintSource (..), PaintSpace (..), X4Problem (..))
import Golem.Pdf.Rect (Rect (..))
import Golem.Preflight
import Golem.Preflight.Rules
import Golem.Preflight.View
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

styleSpan :: SrcSpan
styleSpan = mkSpan (FileId 9) 0 0

-- | A view of pages with nothing on them but the paints, the fonts and the colorants given.
viewWith :: [Paint] -> [Text] -> [Text] -> View
viewWith paints fonts spots =
  View
    { vwPages = [PageView n (Rect 0 0 (Sp 1000) (Sp 1000)) [] [] [] [] False True | n <- [1 .. 3]],
      vwFonts = [],
      vwSwatchesUsed = Map.empty,
      vwBleed = Sp 1000000,
      vwIntentProfile = Just "intent",
      vwX4 = [],
      vwPdf = "%PDF-1.6",
      vwStyleSpan = styleSpan,
      vwManifestSpan = mkSpan (FileId 8) 0 0,
      vwPaints = paints,
      vwUnembeddedFonts = fonts,
      vwSpotColorants = spots
    }

-- | All three checks as errors.
allOn :: Rules
allOn = noneRules {ruFontEmbedding = LevelError, ruSpotColors = LevelError, ruCmyPlates = LevelError}

only :: Text -> [Diagnostic] -> [Diagnostic]
only c = filter ((== DiagnosticCode c) . diagCode)

fill :: Int -> PaintSpace -> [Text] -> Paint
fill page = Paint page "f" PageContent

g09021 :: [Paint] -> [Diagnostic]
g09021 ps = only "G09021" (check allOn (viewWith ps [] []))

described :: Diagnostic -> (Text, Severity, SrcSpan, Text, [(Text, Fact)])
described d = let DiagnosticCode c = diagCode d in (c, diagSeverity d, diagSpan d, diagMessage d, diagFacts d)

tests :: TestTree
tests =
  testGroup
    "G09019 to G09021 (docs/adr ADR 0232)"
    [ rulesTests,
      g09019Tests,
      g09020Tests,
      g09021Tests,
      determinismTests
    ]

rulesTests :: TestTree
rulesTests =
  testGroup
    "the rules"
    [ testCase "font-embedding is error in basic and print, spot-colors only in print, cmy-plates in neither" $ do
        [(ruFontEmbedding r, ruSpotColors r, ruCmyPlates r) | r <- [basicRules, printRules, noneRules]]
          @?= [(LevelError, LevelOff, LevelOff), (LevelError, LevelError, LevelOff), (LevelOff, LevelOff, LevelOff)],
      testCase "the three tables are read with severity alone" $
        parseRules (FileId 0) "based-on = \"none\"\n[font-embedding]\nseverity = \"warning\"\n[spot-colors]\nseverity = \"error\"\n[cmy-plates]\nseverity = \"error\"\n"
          @?= Right noneRules {ruFontEmbedding = LevelWarning, ruSpotColors = LevelError, ruCmyPlates = LevelError},
      testCase "another key of the three tables is G09001" $
        either (map diagCode) (const []) (parseRules (FileId 0) "[cmy-plates]\nmax = 1\n") @?= [DiagnosticCode "G09001"],
      testCase "the schema has the three tables with severity" $
        [k | NTable kvs <- [rulesSchema], (k, NTable [("severity", _)]) <- kvs, k `elem` ["font-embedding", "spot-colors", "cmy-plates"]]
          @?= ["font-embedding", "spot-colors", "cmy-plates"]
    ]

g09019Tests :: TestTree
g09019Tests =
  testGroup
    "G09019"
    [ testCase "I3: no font descriptor, no G09019" $
        only "G09019" (check allOn (viewWith [] [] [])) @?= [],
      testCase "I3: one not embedded, one G09019 at the top of style.toml" $
        map described (only "G09019" (check allOn (viewWith [] ["ABCDEF+Body"] [])))
          @?= [("G09019", Error, styleSpan, "フォントを埋め込んでいません: ABCDEF+Body", [("font", FactText "ABCDEF+Body")])],
      testCase "I3: two descriptors of one name, one G09019" $
        length (only "G09019" (check allOn (viewWith [] ["ABCDEF+Body", "ABCDEF+Body"] []))) @?= 1,
      testCase "I3: one per name, in their order" $
        map diagFacts (only "G09019" (check allOn (viewWith [] ["B", "A", "B"] []))) @?= [[("font", FactText "B")], [("font", FactText "A")]],
      testCase "I3: with an output intent, G09019 alone; G09014 does not report the embedding" $ do
        let v = (viewWith [] ["ABCDEF+Body"] []) {vwX4 = [X4Problem "フォントの埋め込み" "ABCDEF+Body を埋め込んでいません"]}
        length (only "G09019" (check printRules v)) @?= 1
        only "G09014" (check printRules v) @?= [],
      testCase "I3: G09014 still reports the other requirements" $ do
        let v = (viewWith [] ["X"] []) {vwX4 = [X4Problem "フォントの埋め込み" "X を埋め込んでいません", X4Problem "Trapped" "t"]}
        map diagFacts (only "G09014" (check printRules v)) @?= [[("requirement", FactText "Trapped")]],
      testCase "I3: without an output intent, G09019 too" $
        length (only "G09019" (check printRules (viewWith [] ["X"] []) {vwIntentProfile = Nothing, vwX4 = [X4Problem "出力インテント" "x"]})) @?= 1,
      testCase "off: no G09019" $
        only "G09019" (check noneRules (viewWith [] ["X"] [])) @?= []
    ]

g09020Tests :: TestTree
g09020Tests =
  testGroup
    "G09020"
    [ testCase "I4: no colorant, no G09020" $
        only "G09020" (check allOn (viewWith [fill 1 (PsSeparation "All") ["1"]] [] [])) @?= [],
      testCase "I4: PANTONE 185 C, one G09020" $
        map described (only "G09020" (check allOn (viewWith [] [] ["PANTONE 185 C"])))
          @?= [("G09020", Error, styleSpan, "特色の色空間があります: PANTONE 185 C", [("colorant", FactText "PANTONE 185 C")])],
      testCase "I4: one per colorant, in their order" $
        map diagMessage (only "G09020" (check allOn (viewWith [] [] ["Spot1", "Gold"]))) @?= ["特色の色空間があります: Spot1", "特色の色空間があります: Gold"],
      testCase "off in basic" $
        only "G09020" (check basicRules (viewWith [] [] ["Gold"])) @?= []
    ]

g09021Tests :: TestTree
g09021Tests =
  testGroup
    "G09021"
    [ testCase "I5: no paint, no G09021" $
        g09021 [] @?= [],
      testCase "I5: 0 0 0 1 k, no G09021" $
        g09021 [fill 1 PsDeviceCmyk ["0", "0", "0", "1"]] @?= [],
      testCase "I5: 0 0 0.01 1 k, one G09021" $
        map described (g09021 [fill 1 PsDeviceCmyk ["0", "0", "0.01", "1"]])
          @?= [("G09021", Error, styleSpan, "C、M、Y の版に出る色があります: DeviceCMYK 0 0 0.01 1（PDF の 1 ページ目）", [("color", FactText "DeviceCMYK 0 0 0.01 1"), ("pdf-pages", FactInts [1])])],
      testCase "I5: zeros written in other ways are zero" $
        g09021 [fill 1 PsDeviceCmyk ["0.0", ".0", "-0", "1"], fill 1 PsDeviceCmyk ["0.000", "0", "0.", "0.5"]] @?= [],
      testCase "I5: Separation All alone, no G09021" $
        g09021 [fill 1 (PsSeparation "All") ["1"]] @?= [],
      testCase "I5: 0 g, no G09021" $
        g09021 [fill 1 PsDeviceGray ["0"]] @?= [],
      testCase "I5: ICCBased of one component, no G09021" $
        g09021 [fill 1 (PsIccBased 1) ["0.5"]] @?= [],
      testCase "I5: ICCBased of four components with C, M and Y 0, no G09021" $
        g09021 [fill 1 (PsIccBased 4) ["0", "0", "0", "0"]] @?= [],
      testCase "I5: ICCBased of four components with M, one G09021" $
        map diagFacts (g09021 [fill 1 (PsIccBased 4) ["0", "0.3", "0", "0"]]) @?= [[("color", FactText "ICCBased 0 0.3 0 0"), ("pdf-pages", FactInts [1])]],
      testCase "I5: 1 0 0 rg, one G09021" $
        length (g09021 [fill 1 PsDeviceRgb ["1", "0", "0"]]) @?= 1,
      testCase "I5: whatever the value, the other colour spaces count" $
        length (g09021 [fill 1 sp cs | (sp, cs) <- [(PsDeviceRgb, ["0", "0", "0"]), (PsIccBased 3, ["0", "0", "0"]), (PsLab, ["0", "0", "0"]), (PsPattern, ["/P1"]), (PsIndexed, ["0"]), (PsDeviceN ["Black"], ["1"]), (PsSeparation "Black", ["1"]), (PsSeparation "None", ["1"]), (PsUnknown "X", [])]]) @?= 9,
      testCase "I5: one colour on two pages, one G09021 with both pages" $
        map diagFacts (g09021 [fill 1 PsDeviceRgb ["1", "0", "0"], fill 3 PsDeviceRgb ["1", "0", "0"]]) @?= [[("color", FactText "DeviceRGB 1 0 0"), ("pdf-pages", FactInts [1, 3])]],
      testCase "I5: the pages in order without repeats" $
        map diagFacts (g09021 [fill p PsDeviceRgb ["1", "0", "0"] | p <- [3, 1, 3, 2, 1]]) @?= [[("color", FactText "DeviceRGB 1 0 0"), ("pdf-pages", FactInts [1, 2, 3])]],
      testCase "I5: two colours three times each by turns, two G09021 in the order they first appear" $
        map diagFacts (g09021 (concat (replicate 3 [fill 1 PsDeviceRgb ["0", "1", "0"], fill 1 PsDeviceCmyk ["1", "0", "0", "0"]])))
          @?= [[("color", FactText "DeviceRGB 0 1 0"), ("pdf-pages", FactInts [1])], [("color", FactText "DeviceCMYK 1 0 0 0"), ("pdf-pages", FactInts [1])]],
      testCase "I6: 1 0 0 rg inside a Form XObject alone, no G09021" $
        g09021 [Paint 1 "f" (FormXObject ["Fm1"]) PsDeviceRgb ["1", "0", "0"]] @?= [],
      testCase "the name of a swatch of the same value goes first" $
        map diagMessage (only "G09021" (check allOn (viewWith [fill 2 PsDeviceCmyk ["0.2", "0", "0", "1"]] [] []) {vwSwatchesUsed = Map.fromList [("accent", (20, 0, 0, 100))]}))
          @?= ["C、M、Y の版に出る色があります: accent、DeviceCMYK 0.2 0 0 1（PDF の 2 ページ目）"],
      testCase "off in basic and print" $ do
        only "G09021" (check basicRules (viewWith [fill 1 PsDeviceRgb ["1", "0", "0"]] [] [])) @?= []
        only "G09021" (check printRules (viewWith [fill 1 PsDeviceRgb ["1", "0", "0"]] [] [])) @?= []
    ]

-- | Small views: every list of at most three paints of a few colours over two pages and the two sources.
smallViews :: [View]
smallViews =
  [ viewWith ps fonts spots
  | n <- [0 .. 3],
    ps <- sequence (replicate n paints),
    (fonts, spots) <- [([], []), (["A", "B", "A"], ["Gold"])]
  ]
  where
    paints =
      [ Paint page "f" src sp cs
      | page <- [1, 2],
        src <- [PageContent, FormXObject ["Fm1"]],
        (sp, cs) <- [(PsDeviceGray, ["0"]), (PsDeviceCmyk, ["0", "0", "0", "1"]), (PsDeviceCmyk, ["0", "0.5", "0", "1"]), (PsDeviceRgb, ["1", "0", "0"]), (PsSeparation "All", ["1"])]
      ]

{- | Whether a paint of the content of a page is on a C, M or Y plate, as
the ADR writes it, for the small views.
-}
onCmy :: Paint -> Bool
onCmy p =
  paSource p == PageContent && case paSpace p of
    PsDeviceCmyk -> take 3 (paComponents p) /= ["0", "0", "0"]
    PsDeviceGray -> False
    PsSeparation "All" -> False
    _ -> True

determinismTests :: TestTree
determinismTests =
  testGroup
    "on all small views (docs/adr 0204)"
    [ testCase "I8: two runs of the checks on one view give the same diagnostics in the same order" $
        mapM_ (\v -> check allOn v @?= check allOn v) smallViews,
      testCase "I5: G09021 as many as the distinct colours on C, M or Y, with the pages of each in order" $
        mapM_
          ( \v -> do
              let ps = filter onCmy (vwPaints v)
                  keys = nub [(paSpace p, paComponents p) | p <- ps]
                  ds = only "G09021" (check allOn v)
              length ds @?= length keys
              map (lookup "pdf-pages" . diagFacts) ds @?= [Just (FactInts (map toInteger (sort (nub [paPage p | p <- ps, (paSpace p, paComponents p) == k])))) | k <- keys]
          )
          smallViews,
      testCase "I6: the paints inside Form XObjects do not change G09021" $
        mapM_ (\v -> only "G09021" (check allOn v) @?= only "G09021" (check allOn v {vwPaints = [p | p <- vwPaints v, paSource p == PageContent]})) smallViews,
      testCase "I3 and I4: as many as the distinct names" $
        mapM_ (\v -> (length (only "G09019" (check allOn v)), length (only "G09020" (check allOn v))) @?= (length (nub (vwUnembeddedFonts v)), length (nub (vwSpotColorants v)))) smallViews,
      testCase "the small views are many" $
        assertBool "more than 1000" (length smallViews > 1000)
    ]
