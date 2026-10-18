module Main (main) where

import Control.Monad (void)
import Data.Either (isLeft)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import GeometrySpec (geometryTests)
import Golem.LayoutSpec
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

pt :: Integer -> Sp
pt = (* 65536)

-- A5 = 148mm × 210mm; 18mm and 20mm, rounded once from exact rationals.
a5W, a5H, mm18, mm20 :: Sp
a5W = 27494158
a5H = 39011981
mm18 = 3343884
mm20 = 3715427

grid :: Int -> Int -> Int -> Maybe Dim -> Grid
grid chars ls cols gap = Grid (Abs (pt 10)) chars ls (Abs (pt 17)) cols gap (Abs mm18) (Abs mm20)

styleWith :: Bool -> Bool -> Grid -> Style
styleWith bindingRight vertical g = defaultStyle {stPage = Just (Page (NamedSize "A5") bindingRight vertical (Just g) 0)}

geom :: Style -> PageGeometry
geom s = either (error . show) id (pageGeometry (FileId 0) False s)

tests :: TestTree
tests =
  testGroup
    "golem-layout-spec (ADR 0001)"
    [ geometryTests,
      testCase "a page size by dimensions is the same as the named size (golem-project ADR 0005)" $ do
        let withSize sz = defaultStyle {stPage = Just (Page sz True True (Just (grid 30 15 1 Nothing)) 0)}
            dim t = case parseDim t of
              Just (Abs x) -> x
              d -> error (show d)
            named = geom (withSize (NamedSize "B6"))
            custom = geom (withSize (CustomSize (dim "128mm") (dim "182mm")))
        pgPageSize custom @?= pgPageSize named
        pgTypeArea custom @?= pgTypeArea named
        pgTypeAreaEven custom @?= pgTypeAreaEven named,
      testCase "horizontal, one column, left binding" $ do
        let g = geom (styleWith False False (grid 30 30 1 Nothing))
        pgPageSize g @?= (a5W, a5H)
        -- width 10pt × 30, height 17pt × 29 + 10pt
        pgTypeArea g @?= Rect mm20 (a5H - mm18 - pt 503) (pt 300) (pt 503)
        pgTypeAreaEven g @?= Rect (a5W - mm20 - pt 300) (a5H - mm18 - pt 503) (pt 300) (pt 503),
      testCase "vertical, right binding: odd pages are left pages with the gutter on the right" $ do
        let g = geom (styleWith True True (grid 40 20 1 Nothing))
        -- height 10pt × 40, width 17pt × 19 + 10pt
        pgTypeArea g @?= Rect (a5W - mm20 - pt 333) (a5H - mm18 - pt 400) (pt 333) (pt 400)
        pgTypeAreaEven g @?= Rect mm20 (a5H - mm18 - pt 400) (pt 333) (pt 400)
        gutterSide True 1 @?= SideRight
        gutterSide True 2 @?= SideLeft
        gutterSide False 1 @?= SideLeft
        gutterSide False 2 @?= SideRight,
      testCase "two columns with a gap" $ do
        let g = geom (styleWith False False (grid 14 30 2 (Just (Zw 2))))
            Rect x y _ h = pgTypeArea g
        rectW (pgTypeArea g) @?= pt 300
        pgColumns g @?= [Rect x y (pt 140) h, Rect (x + pt 160) y (pt 140) h]
        let gv = geom (styleWith True True (grid 14 20 2 (Just (Zw 2))))
            Rect vx vy vw vh = pgTypeArea gv
        vh @?= pt 300
        pgColumns gv @?= [Rect vx (vy + pt 160) vw (pt 140), Rect vx vy vw (pt 140)],
      testCase "the line grid has one entry per line at the line pitch" $ do
        let g = geom (styleWith False False (grid 30 30 1 Nothing))
        length (pgLineGrid g) @?= 30
        take 2 (pgLineGrid g) @?= [576717, 576717 + pt 17] -- 10pt × 0.88 = 576716.8sp
        let gv = geom (styleWith True True (grid 40 20 1 Nothing))
        take 2 (pgLineGrid gv) @?= [pt 5, pt 22],
      testCase "a type area larger than the page is an error" $ do
        assertBool "too wide" (isLeft (pageGeometry (FileId 0) False (styleWith False False (grid 40 30 1 Nothing))))
        assertBool "too many lines" (isLeft (pageGeometry (FileId 0) False (styleWith False False (grid 30 60 1 Nothing)))),
      testCase "sidenote column on the fore-edge side; errors when vertical or too wide" $ do
        let sn w = SidenoteStyle (Abs (pt w)) (Abs (pt 10)) "{n}"
            s = (styleWith False False (grid 25 30 1 Nothing)) {stSidenotes = Just (sn 60)}
            g = geom s
            Rect ox oy _ oh = pgTypeArea g
            Rect ex _ _ _ = pgTypeAreaEven g
        sidenoteAreaFor g 1 @?= Just (Rect (ox + pt 250 + pt 10) oy (pt 60) oh)
        sidenoteAreaFor g 2 @?= Just (Rect (ex - pt 10 - pt 60) oy (pt 60) oh)
        assertBool "too wide" (isLeft (pageGeometry (FileId 0) False s {stSidenotes = Just (sn 200)}))
        assertBool "vertical" (isLeft (pageGeometry (FileId 0) False ((styleWith True True (grid 40 20 1 Nothing)) {stSidenotes = Just (sn 20)}))),
      testCase "G0701: one diagnostic per failed condition, at the top of the given file (golem-driver ADR 0016)" $ do
        let sn w = SidenoteStyle (Abs (pt w)) (Abs (pt 10)) "{n}"
            base = styleWith False False (grid 30 30 1 Nothing)
            noGrid = defaultStyle {stPage = Just (Page (NamedSize "A5") False False Nothing 0)}
            zwSize = styleWith False False ((grid 30 30 1 Nothing) {gridFontSize = Zw 1})
            cases =
              [ ("no [page]", defaultStyle, "style.toml に [page] がないため、版面を計算できません"),
                ("no [page.grid]", noGrid, "style.toml に [page.grid] がないため、版面を計算できません"),
                ("font-size in zw", zwSize, "文字の大きさは絶対的な寸法で書いてください"),
                ("no characters", styleWith False False (grid 0 30 1 Nothing), "字数、行数、段数は 1 以上、行送りは文字の大きさ以上にしてください"),
                ("overflow", styleWith False False (grid 40 30 1 Nothing), "版面がページからはみ出しています"),
                ("vertical with sidenotes", (styleWith True True (grid 40 20 1 Nothing)) {stSidenotes = Just (sn 20)}, "縦組みの版面には傍注欄を設けられません"),
                ("sidenotes overflow", base {stSidenotes = Just (sn 200)}, "版面と傍注欄の合計がページからはみ出しています")
              ]
        mapM_
          ( \(name, st, msg) -> case pageGeometry (FileId 7) False st of
              Left [d] -> do
                assertEqual name (DiagnosticCode "G0701") (diagCode d)
                assertEqual name msg (diagMessage d)
                assertEqual name (mkSpan (FileId 7) 0 0) (diagSpan d)
              other -> assertFailure (name <> ": " <> show other)
          )
          cases,
      testCase "a sidenote column on a page of two columns is G0701 (docs/adr ADR 0018)" $ do
        let sn = SidenoteStyle (Abs (pt 20)) (Abs (pt 10)) "{n}"
        case pageGeometry (FileId 0) False ((styleWith False False (grid 12 30 2 (Just (Abs (pt 20))))) {stSidenotes = Just sn}) of
          Left [d] -> do
            diagCode d @?= DiagnosticCode "G0701"
            assertBool "mentions columns" ("段組み" `T.isInfixOf` diagMessage d)
          other -> assertFailure (show other),
      testCase "running heads and folios: outside is the fore-edge, swapped on even pages" $ do
        let s = (styleWith False False (grid 30 30 1 Nothing)) {stMasters = Map.fromList [("body", MasterDef (Just (RunningHeadDef "top-outside" (oneLine (RefHeading 1 HeadShort PickFirst)) (oneLine (RefMeta "title")))) (Just ("bottom-center", "{n}")))]}
            g = geom s
            Rect ox oy ow oh = pgTypeArea g
            Rect ex _ _ _ = pgTypeAreaEven g
        case Map.lookup "body" (pgMasters g) of
          Just (MasterGeometry (Just (co, ce, ho, he)) (Just (_, fo, _))) -> do
            (co, ce) @?= (oneLine (RefHeading 1 HeadShort PickFirst), oneLine (RefMeta "title"))
            ho @?= Anchor (ox + ow) ((oy + oh + a5H) `div` 2) AlignEnd
            he @?= Anchor ex ((oy + oh + a5H) `div` 2) AlignStart
            fo @?= Anchor (ox + ow `div` 2) (oy `div` 2) AlignCenter
          other -> assertFailure (show other),
      testCase "a running head of more lines than the margin holds is G0752 (golem-driver ADR 0022)" $ do
        -- 30 lines of 10pt at a 17pt pitch: the type area is 503pt deep; the margin is 1.5 pitches
        let margin = pt 51 `div` 2
            depth = pt 503
            headGrid = (grid 30 30 1 Nothing) {gridTop = Abs margin}
            footGrid = (grid 30 30 1 Nothing) {gridTop = Abs (a5H - depth - margin)}
            withHead g pos n = (styleWith False False g) {stMasters = Map.fromList [("body", MasterDef (Just (RunningHeadDef pos (lines' n) (lines' n))) Nothing)]}
            lines' n = RunningLines ([PartText "柱"] :| replicate (n - 1) [PartText "柱"])
            codeOf st = case pageGeometry (FileId 3) False st of
              Left [d] -> Just (diagCode d, diagSpan d)
              Left ds -> error (show ds)
              Right _ -> Nothing
        codeOf (withHead headGrid "top-outside" 3) @?= Just (DiagnosticCode "G0752", mkSpan (FileId 3) 0 0)
        codeOf (withHead headGrid "top-outside" 1) @?= Nothing
        codeOf (withHead footGrid "bottom-center" 3) @?= Just (DiagnosticCode "G0752", mkSpan (FileId 3) 0 0)
        codeOf (withHead footGrid "bottom-center" 1) @?= Nothing,
      testCase "G0701: the footnote rule longer than a line (golem-driver ADR 0024)" $ do
        let small chars cols gap = Grid (Abs (pt 8)) chars 30 (Abs (pt 14)) cols gap (Abs mm18) (Abs mm20)
            ruled len g = (styleWith False False g) {stNotesRule = Just (RuleSpec (Just len) 19661 Nothing Nothing Nothing RuleSolid (Zw 0) Nothing True)}
            isG0701 = \case
              Left [d] -> diagCode d == DiagnosticCode "G0701"
              _ -> False
        assertBool "41zw on 40 characters" (isG0701 (pageGeometry (FileId 0) False (ruled (Zw 41) (small 40 1 Nothing))))
        assertBool "40zw on 40 characters" (not (isLeft (pageGeometry (FileId 0) False (ruled (Zw 40) (small 40 1 Nothing)))))
        assertBool "21zw on columns of 20 characters" (isG0701 (pageGeometry (FileId 0) False (ruled (Zw 21) (small 20 2 (Just (Zw 2))))))
        assertBool "20zw on columns of 20 characters" (not (isLeft (pageGeometry (FileId 0) False (ruled (Zw 20) (small 20 2 (Just (Zw 2))))))),
      testCase "G0701: paragraph and heading rules out of the trim or over half the column gap (golem-driver ADR 0027)" $ do
        let mm x = round (x * 72 / 25.4 * 65536 :: Rational) :: Integer
            a5W = mm 148
            gridOf size chars cols gap top gutter = Grid (Abs (pt size)) chars 30 (Abs (pt (size + 6))) cols gap (Abs top) (Abs gutter)
            rule = RuleSpec Nothing 19661 Nothing Nothing Nothing RuleSolid (Zw 0) Nothing True
            withRule g size r = (styleWith False False g) {stParaStyles = Map.insert "a" noParaDef {psSize = size, psRuleBefore = Just (Just r)} (stParaStyles defaultStyle)}
            onPage w st = st {stPage = fmap (\p -> p {pageSizeSpec = CustomSize w a5H}) (stPage st)}
            result = pageGeometry (FileId 0) False
            isG0701 = \case
              Left [d] -> diagCode d == DiagnosticCode "G0701"
              _ -> False
            ok = not . isLeft
            -- 40 characters of 9pt on A5 from a gutter of 20mm: 2.84pt to the right edge
            g40 = gridOf 9 40 1 Nothing mm18 mm20
        assertBool "41zw" (isG0701 (result (withRule g40 Nothing rule {rsLength = Just (Zw 41)})))
        assertBool "40zw" (ok (result (withRule g40 Nothing rule {rsLength = Just (Zw 40)})))
        assertBool "80zw of half size" (ok (result (withRule g40 (Just (Zw 0.5)) rule {rsLength = Just (Zw 80)})))
        assertBool "81zw of half size" (isG0701 (result (withRule g40 (Just (Zw 0.5)) rule {rsLength = Just (Zw 81)})))
        -- two columns of 20 characters of 8pt: 21zw goes 8pt into the gap from the left column
        let g20 gap = gridOf 8 20 2 (Just gap) mm18 mm20
        assertBool "half a gap of 1zw" (isG0701 (result (withRule (g20 (Zw 1)) Nothing rule {rsLength = Just (Zw 21)})))
        assertBool "half a gap of 4zw" (ok (result (withRule (g20 (Zw 4)) Nothing rule {rsLength = Just (Zw 21)})))
        -- margins of 15mm on both sides of 40 characters of 8pt
        let g15 = gridOf 8 40 1 Nothing mm18 (mm 15)
            w15 = mm 30 + 40 * pt 8
        assertBool "-14mm" (ok (result (onPage w15 (withRule g15 Nothing rule {rsStartIndent = Abs (negate (mm 14))}))))
        assertBool "-16mm" (isG0701 (result (onPage w15 (withRule g15 Nothing rule {rsStartIndent = Abs (negate (mm 16))}))))
        -- a gutter of 10mm and a fore-edge of 20mm: the narrower is checked
        let g10 = gridOf 8 40 1 Nothing mm18 (mm 10)
            w10 = mm 30 + 40 * pt 8
        assertBool "-9mm" (ok (result (onPage w10 (withRule g10 Nothing rule {rsStartIndent = Abs (negate (mm 9))}))))
        assertBool "-11mm" (isG0701 (result (onPage w10 (withRule g10 Nothing rule {rsStartIndent = Abs (negate (mm 11))}))))
        -- a head margin of 10mm: out of the column across the lines
        let gTop = gridOf 8 40 1 Nothing (mm 10) mm20
            out a = rule {rsKeepInColumn = False, rsWeight = 32768, rsSpaceAfter = Just (Abs (mm a))}
        assertBool "9mm" (ok (result (withRule gTop Nothing (out 9))))
        assertBool "10mm" (isG0701 (result (withRule gTop Nothing (out 10))))
        -- a heading rule is checked too, after the paragraph styles
        let heading = (styleWith False False g40) {stHeadings = Map.fromList [(1, HeadingStyle Nothing Nothing Nothing False Nothing Nothing (Just rule {rsLength = Just (Zw 41)}))]}
        case result heading of
          Left [d] -> diagMessage d @?= "見出し 1 の罫線が仕上がりの線を超えます"
          other -> assertFailure (show (void other))
        case result (withRule g40 Nothing rule {rsLength = Just (Zw 41)}) of
          Left [d] -> diagMessage d @?= "段落スタイル a の罫線が仕上がりの線を超えます"
          other -> assertFailure (show (void other))
        case result (withRule (g20 (Zw 1)) Nothing rule {rsLength = Just (Zw 21)}) of
          Left [d] -> diagMessage d @?= "段落スタイル a の罫線が段間の半分を超えます"
          other -> assertFailure (show (void other)),
      testCase "the lines of the footnote separator (golem-driver ADR 0024)" $ do
        let base = styleWith False False (grid 30 30 1 Nothing)
            withRule b w a = base {stNotesRule = Just (RuleSpec (Just (Zw 10)) w b a Nothing RuleSolid (Zw 0) Nothing True)}
        pgNoteSeparator (geom base) @?= 1
        pgNoteSeparator (geom (withRule Nothing 19661 Nothing)) @?= 1
        -- 5.3pt fits in 7pt + 17pt
        pgNoteSeparator (geom (withRule (Just (Abs 0)) 19661 (Just (Abs (pt 5))))) @?= 1
        -- 25.3pt - 7pt = 18.3pt over 17pt, rounded up
        pgNoteSeparator (geom (withRule (Just (Abs (pt 15))) 19661 (Just (Abs (pt 10))))) @?= 2
        -- zw is the size of the grid
        pgNoteSeparator (geom (withRule (Just (Zw 1.5)) 19661 (Just (Zw 1)))) @?= 2,
      testCase "G0701: rule-after takes its space across from the margin after the lines (golem-driver ADR 0027)" $ do
        -- 30 lines of 8pt on 14pt: 414pt from a head margin of 18mm (51.02pt) leave 130.26pt below
        let g = Grid (Abs (pt 8)) 40 30 (Abs (pt 14)) 1 Nothing (Abs mm18) (Abs mm20)
            after inner = rule0 {rsKeepInColumn = False, rsSpaceBefore = Just (Abs (pt inner))}
        ruleMessages (withParaRule False (styleWith False False g) (after 100)) @?= []
        ruleMessages (withParaRule False (styleWith False False g) (after 131)) @?= ["段落スタイル a の罫線が仕上がりの線を超えます"],
      testCase "G0701: in vertical text a rule runs from the head margin and reaches right before the lines (golem-driver ADR 0027)" $ do
        -- 40 characters of 9pt from a head margin of 18mm (51.02pt); 20 lines of 9pt on 15pt (294pt) from a gutter of 20mm (56.69pt) on A5
        let g = Grid (Abs (pt 9)) 40 20 (Abs (pt 15)) 1 Nothing (Abs mm18) (Abs mm20)
            vertical = styleWith True True g
            indent x = rule0 {rsStartIndent = Abs (negate (pt x))}
            out x = rule0 {rsKeepInColumn = False, rsSpaceAfter = Just (Abs (pt x))}
        -- along: the head margin, not the gutter
        ruleMessages (withParaRule True vertical (indent 50)) @?= []
        ruleMessages (withParaRule True vertical (indent 54)) @?= ["段落スタイル a の罫線が仕上がりの線を超えます"]
        -- across: the margin right of the lines, not the head margin; the rule is 0.3pt
        ruleMessages (withParaRule True vertical (out 53)) @?= []
        ruleMessages (withParaRule True vertical (out 57)) @?= ["段落スタイル a の罫線が仕上がりの線を超えます"],
      testCase "G0701: a rule into the column gap is named as over half the gap (golem-driver ADR 0027)" $ do
        -- two columns of 20 characters of 8pt with a gap of 1zw: 21zw reaches 8pt into a gap of 8pt
        let g = Grid (Abs (pt 8)) 20 30 (Abs (pt 14)) 2 (Just (Zw 1)) (Abs mm18) (Abs mm20)
        ruleMessages (withParaRule True (styleWith False False g) rule0 {rsLength = Just (Zw 21)}) @?= ["段落スタイル a の罫線が段間の半分を超えます"],
      testCase "G0750: a hidden folio on the type area, only with crop marks and when enabled (golem-driver ADR 0021)" $ do
        let mm15 = 2786570 -- 15mm
            mm15' = 278657 -- 1.5mm
            withGutter gt = defaultStyle {stPage = Just (Page (NamedSize "A5") False False (Just ((grid 30 30 1 Nothing) {gridGutter = Abs gt})) 0)}
            codesOf marks st = either (map diagCode) (const []) (pageGeometry (FileId 3) marks st)
        codesOf True (withGutter mm15') @?= [DiagnosticCode "G0750"]
        case pageGeometry (FileId 3) True (withGutter mm15') of
          Left [d] -> do
            diagMessage d @?= "隠しノンブルが版面に重なります。[hidden-folio] の gutter を小さくするか、ノドの余白を広げてください"
            diagSpan d @?= mkSpan (FileId 3) 0 0
          other -> assertFailure (show other)
        codesOf False (withGutter mm15') @?= []
        codesOf True ((withGutter mm15') {stHiddenFolio = (stHiddenFolio defaultStyle) {hfEnabled = False}}) @?= []
        codesOf True (withGutter mm15) @?= [],
      testCase "the hidden folio geometry is there only with crop marks and when enabled (golem-driver ADR 0021)" $ do
        let s = styleWith False False (grid 30 30 1 Nothing)
        pgHiddenFolio (either (error . show) id (pageGeometry (FileId 0) True s)) @?= Just (HiddenFolioGeometry (pt 6) 278657 False)
        pgHiddenFolio (geom s) @?= Nothing
        pgHiddenFolio (either (error . show) id (pageGeometry (FileId 0) True s {stHiddenFolio = (stHiddenFolio s) {hfEnabled = False}})) @?= Nothing
        pgHiddenFolio (either (error . show) id (pageGeometry (FileId 0) True s {stHiddenFolio = (stHiddenFolio s) {hfPages = HiddenAll}})) @?= Just (HiddenFolioGeometry (pt 6) 278657 True)
    ]
  where
    rule0 = RuleSpec Nothing 19661 Nothing Nothing Nothing RuleSolid (Zw 0) Nothing True
    -- the paragraph style "a" with a rule before (True) or after (False)
    withParaRule before st r =
      st {stParaStyles = Map.insert "a" (if before then noParaDef {psRuleBefore = Just (Just r)} else noParaDef {psRuleAfter = Just (Just r)}) (stParaStyles defaultStyle)}
    ruleMessages st = either (map diagMessage) (const []) (pageGeometry (FileId 0) False st)
    oneLine r = RunningLines ([PartRef r False] :| [])
