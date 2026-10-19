-- | The rules and the checks of golem preflight (golem-cli ADR 0006), on hand-made views.
module Main (main) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.LayoutSpec (Rect (..))
import Golem.Pdf (ColorSpace (..), ColorUse (..), Drawing (..), FigureContent (..), ImageData (..), ImportedPage (..), Obj (..), X4Problem (..))
import Golem.Preflight
import Golem.Preflight.Rules
import Golem.Preflight.View
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

-- ------------------------------------------------------------------ fixtures

pt, mm, inch :: Rational -> Integer
pt x = round (x * 65536)
mm x = round (x * 72 / 25.4 * 65536)
inch x = round (x * 72 * 65536)

-- | A B6 trimmed page (128mm × 182mm).
trim :: Rect
trim = Rect 0 0 (mm 128) (mm 182)

styleSpan, manifestSpan, srcSpan :: SrcSpan
styleSpan = mkSpan (FileId 9) 0 0
manifestSpan = mkSpan (FileId 8) 0 0
srcSpan = mkSpan (FileId 0) 10 20

emptyPage :: Int -> PageView
emptyPage n = PageView n trim [] [] [] [] False (odd n)

emptyView :: View
emptyView =
  View
    { vwPages = [emptyPage 1],
      vwFonts = [],
      vwSwatchesUsed = Map.empty,
      vwBleed = mm 3,
      vwIntentProfile = Just "intent",
      vwX4 = [],
      vwPdf = "%PDF-1.6",
      vwStyleSpan = styleSpan,
      vwManifestSpan = manifestSpan
    }

withPages :: [PageView] -> View
withPages ps = emptyView {vwPages = ps}

image :: ColorSpace -> Int -> Int -> Int -> Maybe BS.ByteString -> ImageData
image cs bits w h icc = ImageData w h bits cs icc "" False False Nothing

placed :: ImageData -> Rect -> ImageView
placed img r = ImageView r (RasterFigure img) srcSpan "images/photo.jpg" False

-- | A page of a PDF figure that uses the colour spaces given, placed well inside the page (golem-pdf ADR 0008).
vector :: [ColorUse] -> ImageView
vector cs = ImageView (Rect (mm 20) (mm 20) (inch 4) (inch 3)) (VectorFigure page) srcSpan "images/figure.pdf" False
  where
    page = ImportedPage "file" 1 (0, 0, 288, 216) 0 (288, 216) (ODict []) Nothing "" [] cs

-- | An image of w × h pixels placed at w' × h' inches well inside the page.
placedAt :: ColorSpace -> Int -> Int -> Rational -> Rational -> ImageView
placedAt cs w h w' h' = placed (image cs 8 w h Nothing) (Rect (mm 20) (mm 20) (inch w') (inch h'))

imagePage :: [ImageView] -> View
imagePage ivs = withPages [(emptyPage 1) {pvImages = ivs}]

glyph :: Int -> Text -> Rational -> Maybe (Text, Cmyk) -> GlyphView
glyph g t size color = GlyphView t "fonts/a.otf" g (pt size) color "body" srcSpan

codesOf :: [Diagnostic] -> [Text]
codesOf ds = [c | DiagnosticCode c <- map diagCode ds]

only :: Text -> [Diagnostic] -> [Diagnostic]
only c = filter ((== DiagnosticCode c) . diagCode)

parsed :: Text -> Rules
parsed src = either (error . show) id (parseRules (FileId 0) src)

g0901 :: Text -> Int -> Assertion
g0901 src line = case parseRules (FileId 0) src of
  Right _ -> assertFailure ("accepted: " <> T.unpack src)
  Left ds -> do
    codesOf ds @?= ["G0901"]
    let li = mkLineIndex src
    map (lcLine . offsetToLineCol li . spanStart . diagSpan) ds @?= [line]

-- ------------------------------------------------------------------ tests

tests :: TestTree
tests =
  testGroup
    "golem-preflight (golem-cli ADR 0006)"
    [ rulesTests,
      testGroup "checks" checkTests
    ]

rulesTests :: TestTree
rulesTests =
  testGroup
    "rules"
    [ testCase "basic, print and none as the table of the ADR" $ do
        let levels r =
              [ ruGlyphMissing r,
                ruFontFormats r,
                ruTypeSize r,
                ruImageResolutionMax r,
                ruImageColorSpace r,
                ruImageIcc r,
                ruBleedSize r,
                ruBleedTrimHazard r,
                ruLiveArea r,
                ruOverfullLines r,
                ruPdfX r,
                ruInkCoverage r,
                ruPageCount r,
                ruBlankPages r,
                ruStrokeWeight r
              ]
            e = LevelError
            w = LevelWarning
            o = LevelOff
        levels basicRules @?= [e, o, o, o, o, o, o, o, o, w, e, o, o, o, o]
        levels printRules @?= [e, o, w, o, w, w, e, e, w, w, e, w, o, o, w]
        levels noneRules @?= replicate 15 o
        (ruResolutionColor printRules, ruResolutionGray printRules, ruResolutionBitmap printRules) @?= (Tier 150 300, Tier 150 300, Tier 600 1200)
        (ruResolutionColor basicRules, ruResolutionBitmap noneRules) @?= (Tier 0 0, Tier 0 0)
        (ruTypeSizeMin printRules, ruTypeSizeMultiInkOnly printRules) @?= (pt 5, True)
        ruColorSpacesAllowed printRules @?= ["cmyk", "gray"]
        ruFontFormatsAllowed printRules @?= ["cff", "truetype"]
        (ruBleedMin printRules, ruTrimHazardDistance printRules, ruLiveAreaDistance printRules) @?= (mm 3, mm 3, mm 3)
        (ruInkMax printRules, ruPageMultiple printRules, ruStrokeMin printRules) @?= (350, 1, mm 0.1)
        map fst builtinRules @?= ["basic", "print", "none"],
      testCase "a key written replaces only itself" $ do
        let r = parsed "based-on = \"print\"\n[image-resolution]\ncolor = { warning-below = 350 }\n"
        ruResolutionColor r @?= Tier 150 350
        r {ruResolutionColor = Tier 150 300} @?= printRules,
      testCase "based-on is print when omitted, and name is kept" $ do
        parsed "" @?= printRules
        ruName (parsed "name = \"A 印刷\"\n") @?= Just "A 印刷"
        parsed "based-on = \"basic\"\n" @?= basicRules
        parsed "based-on = \"none\"\n" @?= noneRules,
      testCase "image-unplaceable is an unknown check (golem-pdf ADR 0008)" $ g0901 "[image-unplaceable]\nseverity = \"off\"\n" 0,
      testCase "an unknown top-level key is G0901 at its line" $ g0901 "based-on = \"print\"\nfoo = 1\n" 1,
      testCase "an unknown key of a check is G0901 at its line" $ g0901 "[bleed-size]\nseverity = \"error\"\nmaximum = \"3mm\"\n" 2,
      testCase "an unknown check is G0901" $ g0901 "[no-such-check]\nseverity = \"off\"\n" 0,
      testCase "severity = notice is G0901 at its line" $ g0901 "[pdf-x]\nseverity = \"notice\"\n" 1,
      testCase "zw is G0901 at its line" $ g0901 "[bleed-size]\nmin = \"1zw\"\n" 1,
      testCase "error-below above warning-below is G0901 at its line" $ g0901 "[image-resolution]\ngray = { error-below = 400, warning-below = 300 }\n" 1,
      testCase "an unknown based-on is G0901" $ g0901 "based-on = \"strict\"\n" 0,
      testCase "a negative threshold is G0901" $ g0901 "[ink-coverage]\nmax = -1\n" 1,
      testCase "TOML that does not parse is G0901" $
        either codesOf (const []) (parseRules (FileId 0) "[[") @?= ["G0901"]
    ]

checkTests :: [TestTree]
checkTests =
  [ testCase "G0902: one per character and font, with every page and the count" $ do
      let page n = (emptyPage n) {pvGlyphs = [glyph 0 "\xE000" 10 Nothing, glyph 0 "\xE000" 10 Nothing, glyph 5 "あ" 10 Nothing]}
          ds = only "G0902" (check printRules (withPages (map page [1, 2, 3])))
      length ds @?= 1
      map diagSeverity ds @?= [Error]
      map diagSpan ds @?= [srcSpan]
      lookup "pdf-pages" (concatMap diagFacts ds) @?= Just (FactInts [1, 2, 3])
      lookup "count" (concatMap diagFacts ds) @?= Just (FactInt 6)
      lookup "code-point" (concatMap diagFacts ds) @?= Just (FactText "U+E000")
      assertBool (show ds) (all (("U+E000" `T.isInfixOf`) . diagMessage) ds),
    testCase "G0902: a glyph that is not 0 is not reported" $
      only "G0902" (check printRules (withPages [(emptyPage 1) {pvGlyphs = [glyph 5 "あ" 10 Nothing]}])) @?= [],
    testCase "G0903: a TrueType font with allowed = [cff]" $ do
      let r = printRules {ruFontFormats = LevelError, ruFontFormatsAllowed = ["cff"]}
          v = emptyView {vwFonts = [FontView "fonts/a.ttf" "truetype", FontView "fonts/b.otf" "cff"]}
      map diagMessage (only "G0903" (check r v)) @?= ["この設定では使えない形式のフォントです: fonts/a.ttf（truetype）"],
    testCase "G0904: small text in two inks or more" $ do
      let k100 = Just ("black", (0, 0, 0, 100))
          rich = Just ("rich", (100, 0, 0, 100))
          v gs = withPages [(emptyPage 1) {pvGlyphs = gs}]
          count r gs = length (only "G0904" (check r (v gs)))
      count printRules [glyph 5 "あ" 4 k100] @?= 0
      count printRules [glyph 5 "あ" 4 rich] @?= 1
      count printRules [glyph 5 "あ" 5 rich] @?= 0
      count printRules {ruTypeSizeMultiInkOnly = False} [glyph 5 "あ" 4 k100] @?= 1
      count printRules {ruTypeSizeMultiInkOnly = False} [glyph 5 "あ" 4 k100, glyph 6 "い" 4 rich] @?= 2,
    testCase "G0908: a PDF figure in DeviceRGB and DeviceCMYK is one diagnostic with rgb (golem-pdf ADR 0008)" $ do
      let ds = only "G0908" (check printRules (imagePage [vector [UseRgb, UseCmyk, UseGray]]))
      length ds @?= 1
      assertBool (show ds) (all (("rgb" `T.isInfixOf`) . diagMessage) ds)
      only "G0908" (check printRules (imagePage [vector [UseCmyk, UseIcc 4 "intent"]])) @?= []
      map diagMessage (only "G0908" (check printRules (imagePage [vector [UseRgb, UseLab, UseIcc 3 "srgb"]])))
        @?= ["この設定では使えない色空間の図版です: images/figure.pdf（rgb、lab）。Golem は画像の色を変換しないので、CMYK に変換した画像に替えます"],
    testGroup
      "G0908 names each colour space of a PDF figure; an ICC profile by its components (golem-pdf ADR 0008)"
      [ testCase (show use <> " is " <> T.unpack name) $
          map (lookup "color-space" . diagFacts) (only "G0908" (check printRules {ruColorSpacesAllowed = []} (imagePage [vector [use]])))
            @?= [Just (FactText name)]
      | (use, name) <-
          [ (UseGray, "gray"),
            (UseRgb, "rgb"),
            (UseCmyk, "cmyk"),
            (UseIcc 1 "p", "gray"),
            (UseIcc 3 "p", "rgb"),
            (UseIcc 4 "p", "cmyk"),
            (UseIcc 2 "p", "icc"),
            (UseLab, "lab")
          ]
      ],
    testCase "G0908: a gray ICC profile is allowed where gray is" $
      only "G0908" (check printRules (imagePage [vector [UseIcc 1 "p", UseCmyk]])) @?= [],
    testCase "an SVG figure is rgb for G0908 and not checked by G0906, G0907 and G0909 (golem-pdf ADR 0009)" $ do
      let iv = ImageView (Rect (mm 20) (mm 20) (inch 100) (inch 100)) (SvgFigure (Drawing (10, 10) [])) srcSpan "images/a.svg" False
          r = printRules {ruImageResolutionMax = LevelWarning, ruColorMax = 1}
      map (lookup "color-space" . diagFacts) (only "G0908" (check printRules (imagePage [iv]))) @?= [Just (FactText "rgb")]
      only "G0906" (check printRules (imagePage [iv])) @?= []
      only "G0907" (check r (imagePage [iv])) @?= []
      only "G0909" (check printRules (imagePage [iv])) @?= [],
    testCase "G0909: a PDF figure with a CMYK profile other than the intent (golem-pdf ADR 0008)" $ do
      length (only "G0909" (check printRules (imagePage [vector [UseIcc 4 "other"]]))) @?= 1
      length (only "G0909" (check printRules (imagePage [vector [UseIcc 4 "intent"], vector [UseIcc 3 "other"]]))) @?= 0,
    testCase "G0906 and G0907 do not look at a PDF figure (golem-pdf ADR 0008)" $ do
      let tiny = (vector [UseCmyk]) {ivRect = Rect (mm 20) (mm 20) (inch 100) (inch 100)}
          r = printRules {ruImageResolutionMax = LevelWarning, ruColorMax = 1}
      only "G0906" (check printRules (imagePage [tiny])) @?= []
      only "G0907" (check r (imagePage [tiny])) @?= [],
    testCase "G0911: a PDF figure is checked by its rectangle (golem-pdf ADR 0008)" $
      length (only "G0911" (check printRules emptyView {vwPages = [(emptyPage 1) {pvImages = [(vector [UseCmyk]) {ivRect = Rect (mm 30) (mm 30) (mm 128 - mm 30 - mm 2) (mm 100)}]}]})) @?= 1,
    testCase "G0906: 300ppi passes, 200ppi warns, 120ppi is an error" $ do
      let res w' h' = [(diagSeverity d, diagFacts d) | d <- only "G0906" (check printRules (imagePage [placedAt CsCmyk 1200 900 w' h']))]
      res 4 3 @?= []
      map fst (res 6 4.5) @?= [Warning]
      lookup "ppi" (concatMap snd (res 6 4.5)) @?= Just (FactInt 200)
      lookup "limit" (concatMap snd (res 6 4.5)) @?= Just (FactInt 300)
      lookup "pixels" (concatMap snd (res 6 4.5)) @?= Just (FactInts [1200, 900])
      map fst (res 10 7.5) @?= [Error]
      lookup "ppi" (concatMap snd (res 10 7.5)) @?= Just (FactInt 120),
    testCase "G0906: the smaller of the two directions" $
      [lookup "ppi" (diagFacts d) | d <- only "G0906" (check printRules (imagePage [placedAt CsCmyk 1200 600 4 3]))] @?= [Just (FactInt 200)],
    testCase "G0906: a turned image divides its pixel width by the height of its rectangle (golem-driver ADR 0034)" $ do
      let iv turned = (placedAt CsCmyk 300 600 2 1.5) {ivTurned = turned}
          ppis turned = [lookup "ppi" (diagFacts d) | d <- only "G0906" (check printRules (imagePage [iv turned]))]
      -- turned: 300 / 1.5 and 600 / 2; not turned: 300 / 2 and 600 / 1.5
      ppis True @?= [Just (FactInt 200)]
      ppis False @?= [Just (FactInt 150)],
    testCase "G0911: a turned image is checked by its rectangle on the page (golem-driver ADR 0034)" $ do
      let iv = (placed (image CsCmyk 8 4000 4000 Nothing) (Rect (mm 30) (mm 30) (mm 128 - mm 30 - mm 2) (mm 100))) {ivTurned = True}
      length (only "G0911" (check printRules emptyView {vwPages = [(emptyPage 1) {pvImages = [iv]}]})) @?= 1,
    testCase "G0906: one-bit gray uses the bitmap thresholds" $ do
      let iv = placed (image CsGray 1 2400 1800 Nothing) (Rect (mm 20) (mm 20) (inch 4) (inch 3))
      [(diagSeverity d, lookup "limit" (diagFacts d)) | d <- only "G0906" (check printRules (imagePage [iv]))] @?= [(Warning, Just (FactInt 1200))],
    testCase "G0906: error-below = 0 skips that tier" $ do
      let r = printRules {ruResolutionColor = Tier 0 300}
      map diagSeverity (only "G0906" (check r (imagePage [placedAt CsCmyk 1200 900 10 7.5]))) @?= [Warning],
    testCase "G0907: above color-max" $ do
      let r = printRules {ruImageResolutionMax = LevelWarning, ruColorMax = 600}
      length (only "G0907" (check r (imagePage [placedAt CsCmyk 2800 2100 4 3]))) @?= 1
      length (only "G0907" (check r (imagePage [placedAt CsCmyk 1200 900 4 3]))) @?= 0,
    testCase "G0908: RGB warns in print, CMYK and gray do not, a palette is RGB" $ do
      let at cs = map diagSeverity (only "G0908" (check printRules (imagePage [placedAt cs 1200 900 4 3])))
      at CsRgb @?= [Warning]
      at CsCmyk @?= []
      at CsGray @?= []
      at (CsIndexed "\0\0\0") @?= [Warning],
    testCase "G0909: a CMYK profile other than the intent" $ do
      let at icc v = length (only "G0909" (check printRules v {vwPages = [(emptyPage 1) {pvImages = [placed (image CsCmyk 8 1200 900 icc) (Rect (mm 20) (mm 20) (inch 4) (inch 3))]}]}))
      at (Just "intent") emptyView @?= 0
      at (Just "other") emptyView @?= 1
      at Nothing emptyView @?= 0
      at (Just "other") emptyView {vwIntentProfile = Nothing} @?= 0,
    testCase "G0910: 2mm of bleed is an error in print, 3mm passes" $ do
      map diagSeverity (only "G0910" (check printRules emptyView {vwBleed = mm 2})) @?= [Error]
      only "G0910" (check printRules emptyView {vwBleed = mm 3}) @?= []
      map diagSpan (only "G0910" (check printRules emptyView {vwBleed = mm 2})) @?= [styleSpan],
    testCase "G0911: the trim hazard of the edges of an image" $ do
      -- the right edge e from the trim line (inside is positive), the others far inside
      let right b e = length (only "G0911" (check printRules emptyView {vwBleed = b, vwPages = [(emptyPage 1) {pvImages = [placed (image CsCmyk 8 4000 4000 Nothing) (Rect (mm 30) (mm 30) (mm 128 - mm 30 - e) (mm 100))]}]}))
      right (mm 3) (mm 2) @?= 1
      right (mm 3) (mm 5) @?= 0
      right (mm 3) 0 @?= 1
      right (mm 3) (mm (-3)) @?= 0
      right (mm 3) (mm (-1)) @?= 1
      right 0 0 @?= 1,
    testCase "G0912: a folio 2mm from the trim line on every page is one diagnostic" $ do
      let folio n = (emptyPage n) {pvLines = [LineView (Rect (mm 60) (mm 2) (mm 5) (mm 3)) "ノンブル" styleSpan Nothing]}
          ds = only "G0912" (check printRules (withPages (map folio [1 .. 4])))
      length ds @?= 1
      map diagSeverity ds @?= [Warning]
      lookup "pdf-pages" (concatMap diagFacts ds) @?= Just (FactInts [1, 2, 3, 4])
      assertBool (show ds) (all (\d -> "ノンブル" `T.isInfixOf` diagMessage d && "地" `T.isInfixOf` diagMessage d) ds),
    testCase "G0912: a line well inside is not reported" $
      only "G0912" (check printRules (withPages [(emptyPage 1) {pvLines = [LineView (Rect (mm 20) (mm 20) (mm 50) (mm 3)) "本文の行" srcSpan Nothing]}])) @?= [],
    testCase "G0913: an overfull line, in mm to one decimal" $ do
      let ds = only "G0913" (check printRules (withPages [(emptyPage 1) {pvLines = [LineView (Rect (mm 20) (mm 20) (mm 50) (mm 3)) "本文の行" srcSpan (Just (mm 1.24))]}]))
      map diagMessage ds @?= ["行が行長から 1.2mm はみ出しています（PDF の 1 ページ目）"]
      map diagSeverity ds @?= [Warning]
      map diagSpan ds @?= [srcSpan],
    testCase "G0914: one problem, off, and the missing intent alone" $ do
      let v = emptyView {vwX4 = [X4Problem "TrimBox" "1 ページ目に TrimBox がありません"]}
      map diagMessage (only "G0914" (check printRules v)) @?= ["PDF/X-4 の要件を満たしていません: TrimBox（1 ページ目に TrimBox がありません）"]
      only "G0914" (check printRules {ruPdfX = LevelOff} v) @?= []
      let noIntent = emptyView {vwIntentProfile = Nothing, vwX4 = [X4Problem "出力インテント" "x", X4Problem "GTS_PDFXVersion" "y", X4Problem "Trapped" "z"]}
      map diagMessage (only "G0914" (check printRules noIntent)) @?= ["PDF/X-4 の要件を満たしていません: 出力インテントがありません（style.toml の [color] に intent を書きます）"],
    testCase "G0915: 400% is too much, and only colours used count" $ do
      length (only "G0915" (check printRules emptyView {vwSwatchesUsed = Map.fromList [("rich", (100, 100, 100, 100))]})) @?= 1
      only "G0915" (check printRules emptyView {vwSwatchesUsed = Map.fromList [("plain", (0, 0, 0, 100))]}) @?= [],
    testCase "G0916: 130 pages are 14 short of 144" $ do
      let ds = only "G0916" (check printRules {ruPageCount = LevelError, ruPageMultiple = 16} (withPages (map emptyPage [1 .. 130])))
      length ds @?= 1
      assertBool (show ds) (all (("あと 14 ページ" `T.isInfixOf`) . diagMessage) ds)
      map diagSpan ds @?= [manifestSpan],
    testCase "G0917: a page of the master page alone, off by default" $ do
      let v = withPages [(emptyPage 1) {pvBlank = True}, emptyPage 2, (emptyPage 3) {pvBlank = True}]
      only "G0917" (check printRules v) @?= []
      map diagMessage (only "G0917" (check printRules {ruBlankPages = LevelWarning} v)) @?= ["空白のページです（PDF の 1、3 ページ目）"],
    testCase "G0918: 0.2pt is too thin in print, 0.3pt is not" $ do
      let at w = length (only "G0918" (check printRules (withPages [(emptyPage 1) {pvRules = [RuleView "表の罫線" (pt w) (Rect (mm 20) (mm 20) (mm 50) (pt w))]}])))
      at 0.2 @?= 1
      at 0.3 @?= 0,
    testCase "twelve pages: ten are listed, then ほか 2 ページ" $ do
      pagesPhrase [1 .. 12] @?= "PDF の 1、2、3、4、5、6、7、8、9、10 ページ目ほか 2 ページ"
      let v = withPages [(emptyPage n) {pvBlank = True} | n <- [1 .. 12]]
      map diagMessage (only "G0917" (check printRules {ruBlankPages = LevelWarning} v)) @?= ["空白のページです（PDF の 1、2、3、4、5、6、7、8、9、10 ページ目ほか 2 ページ）"],
    testCase "the template of print reports nothing on a clean view" $
      check printRules emptyView @?= []
  ]
