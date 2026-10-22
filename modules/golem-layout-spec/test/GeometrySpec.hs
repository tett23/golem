{- | Page geometry by page parity and at the boundaries of its checks
(golem-layout-spec ADR 0001): the type area and the columns of odd and
even pages, the inside and outside anchors of masters, a type area that
fills the page exactly, and the line pitch equal to the font size.
-}
module GeometrySpec (geometryTests) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.LayoutSpec
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

pt :: Integer -> Sp
pt = (* 65536)

-- 18mm and 20mm, as in the tests of Main
mm18, mm20 :: Sp
mm18 = 3343884
mm20 = 3715427

-- | 10pt characters on a 17pt pitch, 18mm from the top, 20mm from the gutter.
grid :: Int -> Int -> Int -> Maybe Dim -> Grid
grid chars ls cols gap = Grid (Abs (pt 10)) chars ls (Abs (pt 17)) cols gap (Abs mm18) (Abs mm20)

-- | A5, left binding, horizontal.
a5 :: Grid -> Style
a5 g = defaultStyle {stPage = Just (Page (NamedSize "A5") False False (Just g) 0)}

-- | A page of the given size in sp, left binding, horizontal.
sized :: Sp -> Sp -> Grid -> Style
sized w h g = defaultStyle {stPage = Just (Page (CustomSize w h) False False (Just g) 0)}

geom :: Style -> PageGeometry
geom s = either (error . show) id (pageGeometry (FileId 0) False s)

-- | The message of the one G07001, or what came instead.
g07001 :: Style -> Either Text [Sp]
g07001 s = case pageGeometry (FileId 0) False s of
  Left [d] | diagCode d == DiagnosticCode "G07001" -> Left (diagMessage d)
  Left ds -> Left (T.pack (show ds))
  Right g -> Right (pgLineGrid g)

{- On A5 (27494158 × 39011981 sp), 30 characters of 10pt and 30 lines of 17pt:
the type area is 300pt × 503pt (19660800 × 32964608 sp), at y = 39011981 −
3343884 − 32964608 = 2703489; odd pages (gutter on the left) at x = 3715427,
even pages at x = 27494158 − 3715427 − 19660800 = 4117931. -}

geometryTests :: TestTree
geometryTests =
  testGroup
    "page geometry by parity and at the boundaries (golem-layout-spec ADR 0001)"
    [ testCase "page 3 takes the type area of odd pages" $
        typeAreaFor (geom (a5 (grid 30 30 1 Nothing))) 3 @?= Rect 3715427 2703489 19660800 32964608,
      testCase "page 4 takes the type area of even pages" $
        typeAreaFor (geom (a5 (grid 30 30 1 Nothing))) 4 @?= Rect 4117931 2703489 19660800 32964608,
      testCase "the columns of an even page are in the type area of even pages" $
        -- 14 characters (140pt = 9175040sp) a column, a gap of 2zw (20pt)
        columnsFor (geom (a5 (grid 14 30 2 (Just (Zw 2))))) 4
          @?= [Rect 4117931 2703489 9175040 32964608, Rect 14603691 2703489 9175040 32964608],
      testCase "the columns of an odd page are in the type area of odd pages" $
        columnsFor (geom (a5 (grid 14 30 2 (Just (Zw 2))))) 1
          @?= [Rect 3715427 2703489 9175040 32964608, Rect 14201187 2703489 9175040 32964608],
      testCase "top-inside is at the gutter edge: the left of odd pages, the right of even pages" $ do
        let s = (a5 (grid 30 30 1 Nothing)) {stMasters = Map.fromList [("body", MasterDef (Just (RunningHeadDef "top-inside" title title)) Nothing)]}
            title = RunningLines ([PartRef (RefMeta "title") False] :| [])
            -- y: the middle of the head margin, (2703489 + 32964608 + 39011981) / 2
            heads = [(ho, he) | MasterGeometry (Just (_, _, ho, he)) _ <- Map.elems (pgMasters (geom s))]
        heads @?= [(Anchor 3715427 37340039 AlignStart, Anchor 23778731 37340039 AlignEnd)],
      testCase "bottom-outside is at the fore-edge: the right of odd pages, the left of even pages" $ do
        let s = (a5 (grid 30 30 1 Nothing)) {stMasters = Map.fromList [("body", MasterDef Nothing (Just ("bottom-outside", "{n}")))]}
            -- y: the middle of the foot margin, 2703489 / 2
            folios = [(fo, fe) | MasterGeometry _ (Just (_, fo, fe)) <- Map.elems (pgMasters (geom s))]
        folios @?= [(Anchor 23376227 1351744 AlignEnd, Anchor 4117931 1351744 AlignStart)],
      testCase "a type area that fills the page to the edge is accepted" $
        -- width 20mm + 300pt, height 18mm + 503pt
        fmap length (g07001 (sized (mm20 + pt 300) (mm18 + pt 503) (grid 30 30 1 Nothing))) @?= Right 30,
      testCase "a type area one sp wider than the page is G07001" $
        g07001 (sized (mm20 + pt 300 - 1) (mm18 + pt 503) (grid 30 30 1 Nothing)) @?= Left "版面がページからはみ出しています",
      testCase "a type area one sp taller than the page is G07001" $
        g07001 (sized (mm20 + pt 300) (mm18 + pt 503 - 1) (grid 30 30 1 Nothing)) @?= Left "版面がページからはみ出しています",
      testCase "a line pitch equal to the font size is accepted: the lines touch" $
        -- the baselines 10pt apart, the first at 8.8pt = 576717sp
        fmap (take 3) (g07001 (a5 ((grid 30 30 1 Nothing) {gridLinePitch = Abs (pt 10)}))) @?= Right [576717, 576717 + pt 10, 576717 + pt 20],
      testCase "a line pitch one sp below the font size is G07001" $
        g07001 (a5 ((grid 30 30 1 Nothing) {gridLinePitch = Abs (pt 10 - 1)}))
          @?= Left "字数、行数、段数は 1 以上、行送りは文字の大きさ以上にしてください",
      testCase "a grid of one line has one line" $
        fmap length (g07001 (a5 (grid 30 1 1 Nothing))) @?= Right 1
    ]
