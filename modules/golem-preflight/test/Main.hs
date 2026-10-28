-- | The rules and the checks of golem preflight (golem-cli ADR 0006), on hand-made views.
module Main (main) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Pdf (ColorSpace (..), ColorUse (..), Drawing (..), FigureContent (..), ImageData (..), ImportedPage (..), Obj (..), X4Problem (..))
import Golem.Pdf.Rect (Rect (..))
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
glyph g t size color = GlyphView t "fonts/a.otf" g (pt size) color (SourceParagraphStyle "body") PartBase srcSpan srcSpan

-- | A glyph of 4pt in two inks from a size source, of a part, at an offset of the source (golem-cli ADR 0008).
smallAt :: SizeSource -> GlyphPart -> Int -> GlyphView
smallAt src part off = GlyphView "あ" "fonts/a.otf" 5 (pt 4) (Just ("rich", (100, 0, 0, 100))) src part (mkSpan (FileId 0) off (off + 1)) srcSpan

codesOf :: [Diagnostic] -> [Text]
codesOf ds = [c | DiagnosticCode c <- map diagCode ds]

only :: Text -> [Diagnostic] -> [Diagnostic]
only c = filter ((== DiagnosticCode c) . diagCode)

parsed :: Text -> Rules
parsed src = either (error . show) id (parseRules (FileId 0) src)

g09001 :: Text -> Int -> Assertion
g09001 src line = case parseRules (FileId 0) src of
  Right _ -> assertFailure ("accepted: " <> T.unpack src)
  Left ds -> do
    codesOf ds @?= ["G09001"]
    let li = mkLineIndex src
    map (lcLine . offsetToLineCol li . spanStart . diagSpan) ds @?= [line]

-- ------------------------------------------------------------------ tests

tests :: TestTree
tests =
  testGroup
    "golem-preflight (golem-cli ADR 0006)"
    [ rulesTests,
      testGroup "checks" checkTests,
      auditTests
    ]

-- | G08100 of golem build groups the glyphs of a whole book: in time n log n (security audit 2026-10-24).
auditTests :: TestTree
auditTests =
  testGroup
    "the grouping of glyph 0 for G08100 and G09002 (security audit 2026-10-24)"
    [ localOption (mkTimeout 30000000) $
        testCase "300000 glyphs 0 of one character are one group, in time" $ do
          let v = withPages [(emptyPage 1) {pvGlyphs = replicate 300000 (glyph 0 (T.singleton (toEnum 0xF0000)) 10 Nothing)}]
          map mgFacts (missingGlyphs v) @?= [[("code-point", FactText "U+F0000"), ("font", FactText "fonts/a.otf"), ("pdf-pages", FactInts [1]), ("count", FactInt 300000)]],
      localOption (mkTimeout 30000000) $
        testCase "200000 glyphs 0 of distinct characters are as many groups, in time" $ do
          let v = withPages [(emptyPage 1) {pvGlyphs = [glyph 0 (T.singleton (toEnum (0x20000 + i))) 10 Nothing | i <- [0 .. 199999]]}]
          length (missingGlyphs v) @?= 200000
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
      testCase "image-unplaceable is an unknown check (golem-pdf ADR 0008)" $ g09001 "[image-unplaceable]\nseverity = \"off\"\n" 0,
      testCase "an unknown top-level key is G09001 at its line" $ g09001 "based-on = \"print\"\nfoo = 1\n" 1,
      testCase "an unknown key of a check is G09001 at its line" $ g09001 "[bleed-size]\nseverity = \"error\"\nmaximum = \"3mm\"\n" 2,
      testCase "an unknown check is G09001" $ g09001 "[no-such-check]\nseverity = \"off\"\n" 0,
      testCase "severity = notice is G09001 at its line" $ g09001 "[pdf-x]\nseverity = \"notice\"\n" 1,
      testCase "zw is G09001 at its line" $ g09001 "[bleed-size]\nmin = \"1zw\"\n" 1,
      testCase "error-below above warning-below is G09001 at its line" $ g09001 "[image-resolution]\ngray = { error-below = 400, warning-below = 300 }\n" 1,
      testCase "an unknown based-on is G09001" $ g09001 "based-on = \"strict\"\n" 0,
      testCase "TOML that does not parse is G09001" $
        either codesOf (const []) (parseRules (FileId 0) "[[") @?= ["G09001"],
      testCase "every key of every check goes to its own field" $
        parsed
          ( T.unlines
              [ "based-on = \"basic\"",
                "name = \"all\"",
                "[glyph-missing]\nseverity = \"warning\"",
                "[font-formats]\nseverity = \"error\"\nallowed = [\"cff2\"]",
                "[type-size]\nseverity = \"error\"\nmin-size = \"6pt\"\nmulti-ink-only = false",
                "[image-resolution]\ncolor = { error-below = 101, warning-below = 201 }\ngray = { error-below = 102, warning-below = 202 }\nbitmap = { error-below = 103, warning-below = 203 }",
                "[image-resolution-max]\nseverity = \"warning\"\ncolor-max = 901\ngray-max = 902\nbitmap-max = 903",
                "[image-color-space]\nseverity = \"error\"\nallowed = [\"rgb\"]",
                "[image-icc]\nseverity = \"error\"",
                "[bleed-size]\nseverity = \"warning\"\nmin = \"1pt\"",
                "[bleed-trim-hazard]\nseverity = \"warning\"\ndistance = \"2pt\"",
                "[live-area]\nseverity = \"error\"\ndistance = \"3pt\"",
                "[overfull-lines]\nseverity = \"error\"",
                "[pdf-x]\nseverity = \"warning\"",
                "[ink-coverage]\nseverity = \"error\"\nmax = 301",
                "[page-count]\nseverity = \"warning\"\nmultiple-of = 16",
                "[blank-pages]\nseverity = \"warning\"",
                "[stroke-weight]\nseverity = \"error\"\nmin = \"4pt\""
              ]
          )
          @?= Rules
            { ruBasedOn = "basic",
              ruName = Just "all",
              ruGlyphMissing = LevelWarning,
              ruFontFormats = LevelError,
              ruFontFormatsAllowed = ["cff2"],
              ruTypeSize = LevelError,
              ruTypeSizeMin = pt 6,
              ruTypeSizeMultiInkOnly = False,
              ruResolutionColor = Tier 101 201,
              ruResolutionGray = Tier 102 202,
              ruResolutionBitmap = Tier 103 203,
              ruImageResolutionMax = LevelWarning,
              ruColorMax = 901,
              ruGrayMax = 902,
              ruBitmapMax = 903,
              ruImageColorSpace = LevelError,
              ruColorSpacesAllowed = ["rgb"],
              ruImageIcc = LevelError,
              ruBleedSize = LevelWarning,
              ruBleedMin = pt 1,
              ruBleedTrimHazard = LevelWarning,
              ruTrimHazardDistance = pt 2,
              ruLiveArea = LevelError,
              ruLiveAreaDistance = pt 3,
              ruOverfullLines = LevelError,
              ruPdfX = LevelWarning,
              ruInkCoverage = LevelError,
              ruInkMax = 301,
              ruPageCount = LevelWarning,
              ruPageMultiple = 16,
              ruBlankPages = LevelWarning,
              ruStrokeWeight = LevelError,
              ruStrokeMin = pt 4
            },
      testCase "the edges of the numbers: error-below may equal warning-below, a million is the largest count" $ do
        ruResolutionColor (parsed "[image-resolution]\ncolor = { error-below = 300, warning-below = 300 }\n") @?= Tier 300 300
        ruResolutionColor (parsed "[image-resolution]\ncolor = { error-below = 400, warning-below = 0 }\n") @?= Tier 400 0
        ruInkMax (parsed "[ink-coverage]\nmax = 1000000\n") @?= 1000000
        ruInkMax (parsed "[ink-coverage]\nmax = 0\n") @?= 0
        g09001 "[ink-coverage]\nmax = 1000001\n" 1
        ruPageMultiple (parsed "[page-count]\nmultiple-of = 1\n") @?= 1
        g09001 "[page-count]\nmultiple-of = 0\n" 1,
      -- docs/adr ADR 0102
      testCase "a negative count is G02103 at its value, with the message of the key" $ do
        let errs src = either (map (\d -> let DiagnosticCode c = diagCode d in (c, diagMessage d, spanStart (diagSpan d)))) (const []) (parseRules (FileId 0) src)
        errs "[ink-coverage]\nmax = -1\n" @?= [("G02103", "ink-coverage.max には 0 以上の整数を書きます", 21)]
        errs "[page-count]\nmultiple-of = -1\n" @?= [("G02103", "page-count.multiple-of には 0 以上の整数を書きます", 27)]
        errs "[image-resolution]\ncolor = { error-below = -1 }\n" @?= [("G02103", "image-resolution.color.error-below には 0 以上の整数を書きます", 43)],
      testCase "the messages of G09001 name the key, the value and what to write" $ do
        let msgs src = either (map diagMessage) (const []) (parseRules (FileId 0) src)
        msgs "[image-resolution]\ngray = { error-below = 400, warning-below = 300 }\n"
          @?= ["gray.error-below の値が正しくありません: 400（warning-below の 300 より大きくできません） (image-resolution.gray)"]
        msgs "[page-count]\nmultiple-of = 0\n" @?= ["multiple-of の値が正しくありません: 0（1 以上の整数にします） (page-count.multiple-of)"]
        msgs "[image-color-space]\nallowed = [\"cmyk\", \"lab\"]\n" @?= ["allowed の値が正しくありません: lab（cmyk、gray、rgb のどれかにします） (image-color-space.allowed)"]
        msgs "[font-formats]\nallowed = [\"opentype\"]\n" @?= ["allowed の値が正しくありません: opentype（cff、cff2、truetype のどれかにします） (font-formats.allowed)"]
        msgs "[bleed-size]\nmin = \"3\"\n" @?= ["min の値が正しくありません: 3（長さは 3mm や 0.25pt のように書きます） (bleed-size.min)"]
    ]

checkTests :: [TestTree]
checkTests =
  [ testCase "G09002: one per character and font, with every page and the count" $ do
      let page n = (emptyPage n) {pvGlyphs = [glyph 0 "\xE000" 10 Nothing, glyph 0 "\xE000" 10 Nothing, glyph 5 "あ" 10 Nothing]}
          ds = only "G09002" (check printRules (withPages (map page [1, 2, 3])))
      length ds @?= 1
      map diagSeverity ds @?= [Error]
      map diagSpan ds @?= [srcSpan]
      lookup "pdf-pages" (concatMap diagFacts ds) @?= Just (FactInts [1, 2, 3])
      lookup "count" (concatMap diagFacts ds) @?= Just (FactInt 6)
      lookup "code-point" (concatMap diagFacts ds) @?= Just (FactText "U+E000")
      assertBool (show ds) (all (("U+E000" `T.isInfixOf`) . diagMessage) ds),
    testCase "G09002: a glyph that is not 0 is not reported" $
      only "G09002" (check printRules (withPages [(emptyPage 1) {pvGlyphs = [glyph 5 "あ" 10 Nothing]}])) @?= [],
    testCase "G09003: a TrueType font with allowed = [cff]" $ do
      let r = printRules {ruFontFormats = LevelError, ruFontFormatsAllowed = ["cff"]}
          v = emptyView {vwFonts = [FontView "fonts/a.ttf" "truetype", FontView "fonts/b.otf" "cff"]}
      map diagMessage (only "G09003" (check r v)) @?= ["この設定では使えない形式のフォントです: fonts/a.ttf（truetype）"],
    testCase "G09003: a CFF2 font is of the form cff2, which allowed may name (golem-font ADR 0003)" $ do
      let v = emptyView {vwFonts = [FontView "fonts/v.otf" "cff2"]}
      map diagMessage (only "G09003" (check printRules {ruFontFormats = LevelError} v)) @?= ["この設定では使えない形式のフォントです: fonts/v.otf（cff2）"]
      fmap ruFontFormatsAllowed (parseRules (FileId 0) "[font-formats]\nallowed = [\"cff\", \"cff2\"]\n") @?= Right ["cff", "cff2"],
    testCase "G09004: small text in two inks or more" $ do
      let k100 = Just ("black", (0, 0, 0, 100))
          rich = Just ("rich", (100, 0, 0, 100))
          v gs = withPages [(emptyPage 1) {pvGlyphs = gs}]
          count r gs = length (only "G09004" (check r (v gs)))
      count printRules [glyph 5 "あ" 4 k100] @?= 0
      count printRules [glyph 5 "あ" 4 rich] @?= 1
      count printRules [glyph 5 "あ" 5 rich] @?= 0
      count printRules {ruTypeSizeMultiInkOnly = False} [glyph 5 "あ" 4 k100] @?= 1
      count printRules {ruTypeSizeMultiInkOnly = False} [glyph 5 "あ" 4 k100, glyph 6 "い" 4 rich] @?= 2,
    testCase "G09004: two definitions of one size, role and colour are two causes (golem-cli ADR 0008)" $ do
      let ds = only "G09004" (check printRules (withPages [(emptyPage 1) {pvGlyphs = [smallAt (SourceParagraphStyle "a") PartBase 10, smallAt (SourceParagraphStyle "b") PartBase 20]}]))
      map diagMessage ds
        @?= [ "文字が小さすぎます: 1.41mm（1.76mm 未満、段落スタイル a の size、色 rich、PDF の 1 ページ目）",
              "文字が小さすぎます: 1.41mm（1.76mm 未満、段落スタイル b の size、色 rich、PDF の 1 ページ目）"
            ]
      map (lookup "source" . diagFacts) ds @?= [Just (FactText "paragraph-styles.a.size"), Just (FactText "paragraph-styles.b.size")]
      -- the size in mm to two decimals (docs/adr ADR 0103)
      map (lookup "size" . diagFacts) ds @?= [Just (FactText "1.41mm"), Just (FactText "1.41mm")],
    testCase "G09004: the text and its ruby of one definition are two causes (golem-cli ADR 0008)" $ do
      let ds = only "G09004" (check printRules (withPages [(emptyPage 1) {pvGlyphs = [smallAt (SourceCharacterStyle "s") PartBase 10, smallAt (SourceCharacterStyle "s") PartRuby 10]}]))
      map diagMessage ds
        @?= [ "文字が小さすぎます: 1.41mm（1.76mm 未満、文字スタイル s の size、色 rich、PDF の 1 ページ目）",
              "文字が小さすぎます: 1.41mm（1.76mm 未満、文字スタイル s の size のルビ、色 rich、PDF の 1 ページ目）"
            ]
      map (lookup "part" . diagFacts) ds @?= [Just (FactText "base"), Just (FactText "ruby")],
    testCase "G09004: at the character first in the source, not on the first page (golem-cli ADR 0008)" $ do
      let src = SourceParagraphStyle "a"
          ds = only "G09004" (check printRules (withPages [(emptyPage 1) {pvGlyphs = [smallAt src PartBase 50]}, (emptyPage 2) {pvGlyphs = [smallAt src PartBase 10]}]))
      map (spanStart . diagSpan) ds @?= [10]
      map (lookup "pdf-pages" . diagFacts) ds @?= [Just (FactInts [1, 2])],
    testCase "G09004: in the order of the source, not of the pages (golem-cli ADR 0008)" $ do
      let ds = only "G09004" (check printRules (withPages [(emptyPage 1) {pvGlyphs = [smallAt (SourceParagraphStyle "a") PartBase 90]}, (emptyPage 2) {pvGlyphs = [smallAt SourceNoteMark PartBase 5]}]))
      map (spanStart . diagSpan) ds @?= [5, 90]
      map (lookup "source" . diagFacts) ds @?= [Just (FactText "notes.mark-size"), Just (FactText "paragraph-styles.a.size")],
    testCase "G09008: a PDF figure in DeviceRGB and DeviceCMYK is one diagnostic with rgb (golem-pdf ADR 0008)" $ do
      let ds = only "G09008" (check printRules (imagePage [vector [UseRgb, UseCmyk, UseGray]]))
      length ds @?= 1
      assertBool (show ds) (all (("rgb" `T.isInfixOf`) . diagMessage) ds)
      only "G09008" (check printRules (imagePage [vector [UseCmyk, UseIcc 4 "intent"]])) @?= []
      map diagMessage (only "G09008" (check printRules (imagePage [vector [UseRgb, UseLab, UseIcc 3 "srgb"]])))
        @?= ["この設定では使えない色空間の図版です: images/figure.pdf（rgb、lab）。Golem は画像の色を変換しないので、CMYK に変換した画像に替えます"],
    testGroup
      "G09008 names each colour space of a PDF figure; an ICC profile by its components (golem-pdf ADR 0008)"
      [ testCase (show use <> " is " <> T.unpack name) $
          map (lookup "color-space" . diagFacts) (only "G09008" (check printRules {ruColorSpacesAllowed = []} (imagePage [vector [use]])))
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
    testCase "G09008: a gray ICC profile is allowed where gray is" $
      only "G09008" (check printRules (imagePage [vector [UseIcc 1 "p", UseCmyk]])) @?= [],
    testCase "an SVG figure is rgb for G09008 and not checked by G09006, G09007 and G09009 (golem-pdf ADR 0009)" $ do
      let iv = ImageView (Rect (mm 20) (mm 20) (inch 100) (inch 100)) (SvgFigure (Drawing (10, 10) [])) srcSpan "images/a.svg" False
          r = printRules {ruImageResolutionMax = LevelWarning, ruColorMax = 1}
      map (lookup "color-space" . diagFacts) (only "G09008" (check printRules (imagePage [iv]))) @?= [Just (FactText "rgb")]
      only "G09006" (check printRules (imagePage [iv])) @?= []
      only "G09007" (check r (imagePage [iv])) @?= []
      only "G09009" (check printRules (imagePage [iv])) @?= [],
    testCase "G09009: a PDF figure with a CMYK profile other than the intent (golem-pdf ADR 0008)" $ do
      length (only "G09009" (check printRules (imagePage [vector [UseIcc 4 "other"]]))) @?= 1
      length (only "G09009" (check printRules (imagePage [vector [UseIcc 4 "intent"], vector [UseIcc 3 "other"]]))) @?= 0,
    testCase "G09006 and G09007 do not look at a PDF figure (golem-pdf ADR 0008)" $ do
      let tiny = (vector [UseCmyk]) {ivRect = Rect (mm 20) (mm 20) (inch 100) (inch 100)}
          r = printRules {ruImageResolutionMax = LevelWarning, ruColorMax = 1}
      only "G09006" (check printRules (imagePage [tiny])) @?= []
      only "G09007" (check r (imagePage [tiny])) @?= [],
    testCase "G09011: a PDF figure is checked by its rectangle (golem-pdf ADR 0008)" $
      length (only "G09011" (check printRules emptyView {vwPages = [(emptyPage 1) {pvImages = [(vector [UseCmyk]) {ivRect = Rect (mm 30) (mm 30) (mm 128 - mm 30 - mm 2) (mm 100)}]}]})) @?= 1,
    testCase "G09006: 300ppi passes, 200ppi warns, 120ppi is an error" $ do
      let res w' h' = [(diagSeverity d, diagFacts d) | d <- only "G09006" (check printRules (imagePage [placedAt CsCmyk 1200 900 w' h']))]
      res 4 3 @?= []
      map fst (res 6 4.5) @?= [Warning]
      lookup "ppi" (concatMap snd (res 6 4.5)) @?= Just (FactInt 200)
      lookup "limit" (concatMap snd (res 6 4.5)) @?= Just (FactInt 300)
      lookup "pixels" (concatMap snd (res 6 4.5)) @?= Just (FactInts [1200, 900])
      map fst (res 10 7.5) @?= [Error]
      lookup "ppi" (concatMap snd (res 10 7.5)) @?= Just (FactInt 120),
    testCase "G09006: the smaller of the two directions" $
      [lookup "ppi" (diagFacts d) | d <- only "G09006" (check printRules (imagePage [placedAt CsCmyk 1200 600 4 3]))] @?= [Just (FactInt 200)],
    testCase "G09006: a turned image divides its pixel width by the height of its rectangle (golem-driver ADR 0034)" $ do
      let iv turned = (placedAt CsCmyk 300 600 2 1.5) {ivTurned = turned}
          ppis turned = [lookup "ppi" (diagFacts d) | d <- only "G09006" (check printRules (imagePage [iv turned]))]
      -- turned: 300 / 1.5 and 600 / 2; not turned: 300 / 2 and 600 / 1.5
      ppis True @?= [Just (FactInt 200)]
      ppis False @?= [Just (FactInt 150)],
    testCase "G09011: a turned image is checked by its rectangle on the page (golem-driver ADR 0034)" $ do
      let iv = (placed (image CsCmyk 8 4000 4000 Nothing) (Rect (mm 30) (mm 30) (mm 128 - mm 30 - mm 2) (mm 100))) {ivTurned = True}
      length (only "G09011" (check printRules emptyView {vwPages = [(emptyPage 1) {pvImages = [iv]}]})) @?= 1,
    testCase "G09006: one-bit gray uses the bitmap thresholds" $ do
      let iv = placed (image CsGray 1 2400 1800 Nothing) (Rect (mm 20) (mm 20) (inch 4) (inch 3))
      [(diagSeverity d, lookup "limit" (diagFacts d)) | d <- only "G09006" (check printRules (imagePage [iv]))] @?= [(Warning, Just (FactInt 1200))],
    testCase "G09006: error-below = 0 skips that tier" $ do
      let r = printRules {ruResolutionColor = Tier 0 300}
      map diagSeverity (only "G09006" (check r (imagePage [placedAt CsCmyk 1200 900 10 7.5]))) @?= [Warning],
    testCase "G09007: above color-max" $ do
      let r = printRules {ruImageResolutionMax = LevelWarning, ruColorMax = 600}
      length (only "G09007" (check r (imagePage [placedAt CsCmyk 2800 2100 4 3]))) @?= 1
      length (only "G09007" (check r (imagePage [placedAt CsCmyk 1200 900 4 3]))) @?= 0,
    testCase "G09008: RGB warns in print, CMYK and gray do not, a palette is RGB" $ do
      let at cs = map diagSeverity (only "G09008" (check printRules (imagePage [placedAt cs 1200 900 4 3])))
      at CsRgb @?= [Warning]
      at CsCmyk @?= []
      at CsGray @?= []
      at (CsIndexed "\0\0\0") @?= [Warning],
    testCase "G09009: a CMYK profile other than the intent" $ do
      let at icc v = length (only "G09009" (check printRules v {vwPages = [(emptyPage 1) {pvImages = [placed (image CsCmyk 8 1200 900 icc) (Rect (mm 20) (mm 20) (inch 4) (inch 3))]}]}))
      at (Just "intent") emptyView @?= 0
      at (Just "other") emptyView @?= 1
      at Nothing emptyView @?= 0
      at (Just "other") emptyView {vwIntentProfile = Nothing} @?= 0,
    testCase "G09010: 2mm of bleed is an error in print, 3mm passes" $ do
      map diagSeverity (only "G09010" (check printRules emptyView {vwBleed = mm 2})) @?= [Error]
      only "G09010" (check printRules emptyView {vwBleed = mm 3}) @?= []
      map diagSpan (only "G09010" (check printRules emptyView {vwBleed = mm 2})) @?= [styleSpan],
    testCase "G09011: the trim hazard of the edges of an image" $ do
      -- the right edge e from the trim line (inside is positive), the others far inside
      let right b e = length (only "G09011" (check printRules emptyView {vwBleed = b, vwPages = [(emptyPage 1) {pvImages = [placed (image CsCmyk 8 4000 4000 Nothing) (Rect (mm 30) (mm 30) (mm 128 - mm 30 - e) (mm 100))]}]}))
      right (mm 3) (mm 2) @?= 1
      right (mm 3) (mm 5) @?= 0
      right (mm 3) 0 @?= 1
      right (mm 3) (mm (-3)) @?= 0
      right (mm 3) (mm (-1)) @?= 1
      right 0 0 @?= 1,
    testCase "G09012: a folio 2mm from the trim line on every page is one diagnostic" $ do
      let folio n = (emptyPage n) {pvLines = [LineView (Rect (mm 60) (mm 2) (mm 5) (mm 3)) "ノンブル" styleSpan Nothing]}
          ds = only "G09012" (check printRules (withPages (map folio [1 .. 4])))
      length ds @?= 1
      map diagSeverity ds @?= [Warning]
      lookup "pdf-pages" (concatMap diagFacts ds) @?= Just (FactInts [1, 2, 3, 4])
      assertBool (show ds) (all (\d -> "ノンブル" `T.isInfixOf` diagMessage d && "地" `T.isInfixOf` diagMessage d) ds),
    testCase "G09012: a line well inside is not reported" $
      only "G09012" (check printRules (withPages [(emptyPage 1) {pvLines = [LineView (Rect (mm 20) (mm 20) (mm 50) (mm 3)) "本文の行" srcSpan Nothing]}])) @?= [],
    testCase "G09013: an overfull line, in mm to two decimals (docs/adr ADR 0103)" $ do
      let ds = only "G09013" (check printRules (withPages [(emptyPage 1) {pvLines = [LineView (Rect (mm 20) (mm 20) (mm 50) (mm 3)) "本文の行" srcSpan (Just (mm 1.24))]}]))
      map diagMessage ds @?= ["行が行長から 1.24mm はみ出しています（PDF の 1 ページ目）"]
      map (lookup "overfull" . diagFacts) ds @?= [Just (FactText "1.24mm")]
      map diagSeverity ds @?= [Warning]
      map diagSpan ds @?= [srcSpan],
    testCase "G09014: one problem, off, and the missing intent alone" $ do
      let v = emptyView {vwX4 = [X4Problem "TrimBox" "1 ページ目に TrimBox がありません"]}
      map diagMessage (only "G09014" (check printRules v)) @?= ["PDF/X-4 の要件を満たしていません: TrimBox（1 ページ目に TrimBox がありません）"]
      only "G09014" (check printRules {ruPdfX = LevelOff} v) @?= []
      let noIntent = emptyView {vwIntentProfile = Nothing, vwX4 = [X4Problem "出力インテント" "x", X4Problem "GTS_PDFXVersion" "y", X4Problem "Trapped" "z"]}
      map diagMessage (only "G09014" (check printRules noIntent)) @?= ["PDF/X-4 の要件を満たしていません: 出力インテントがありません（style.toml の [color] に intent を書きます）"],
    testCase "G09015: 400% is too much, and only colours used count" $ do
      length (only "G09015" (check printRules emptyView {vwSwatchesUsed = Map.fromList [("rich", (100, 100, 100, 100))]})) @?= 1
      only "G09015" (check printRules emptyView {vwSwatchesUsed = Map.fromList [("plain", (0, 0, 0, 100))]}) @?= [],
    testCase "G09016: 130 pages are 14 short of 144" $ do
      let ds = only "G09016" (check printRules {ruPageCount = LevelError, ruPageMultiple = 16} (withPages (map emptyPage [1 .. 130])))
      length ds @?= 1
      assertBool (show ds) (all (("あと 14 ページ" `T.isInfixOf`) . diagMessage) ds)
      map diagSpan ds @?= [manifestSpan],
    testCase "G09017: a page of the master page alone, off by default" $ do
      let v = withPages [(emptyPage 1) {pvBlank = True}, emptyPage 2, (emptyPage 3) {pvBlank = True}]
      only "G09017" (check printRules v) @?= []
      map diagMessage (only "G09017" (check printRules {ruBlankPages = LevelWarning} v)) @?= ["空白のページです（PDF の 1、3 ページ目）"],
    testCase "G09018: 0.2pt is too thin in print, 0.3pt is not" $ do
      let at w = length (only "G09018" (check printRules (withPages [(emptyPage 1) {pvRules = [RuleView "表の罫線" (pt w) (Rect (mm 20) (mm 20) (mm 50) (pt w))]}])))
      at 0.2 @?= 1
      at 0.3 @?= 0,
    testCase "G09018: a line of 0.06mm is told apart from the threshold of 0.1mm (docs/adr ADR 0103)" $ do
      let ds = only "G09018" (check printRules (withPages [(emptyPage 1) {pvRules = [RuleView "表の罫線" (mm 0.06) (Rect (mm 20) (mm 20) (mm 50) (mm 0.06))]}]))
      map diagMessage ds @?= ["線が細すぎます: 表の罫線（0.06mm、0.10mm 未満、PDF の 1 ページ目）"],
    testCase "twelve pages: ten are listed, then ほか 2 ページ" $ do
      pagesPhrase [1 .. 12] @?= "PDF の 1、2、3、4、5、6、7、8、9、10 ページ目ほか 2 ページ"
      let v = withPages [(emptyPage n) {pvBlank = True} | n <- [1 .. 12]]
      map diagMessage (only "G09017" (check printRules {ruBlankPages = LevelWarning} v)) @?= ["空白のページです（PDF の 1、2、3、4、5、6、7、8、9、10 ページ目ほか 2 ページ）"],
    testCase "the template of print reports nothing on a clean view" $
      check printRules emptyView @?= []
  ]
