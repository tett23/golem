-- | The boxes of paragraph styles (docs/adr/0271): B4 to B6, B8 and B9, and the bands of the border.
module BoxSpec (boxTests) where

import Control.Monad (forM_)
import Golem.LayoutSpec (Rect (..))
import Golem.Project.Style (BoxSide (..), RuleStyle (..), Sp (..))
import Golem.Typeset.Box
import Golem.Typeset.RuleShape (RuleShape (..))
import Test.Tasty
import Test.Tasty.HUnit

-- | An item of a flow: a paragraph of a box of a key, a space or a keep-with-next between, or anything else.
data Item = Para !Int !Char | Space | KeepNext | Other
  deriving stock (Eq, Show)

keyOf :: Item -> Maybe Int
keyOf = \case
  Para k _ -> Just k
  _ -> Nothing

between :: Item -> Bool
between = (`elem` [Space, KeepNext])

grouped :: [Item] -> [Either Item (Int, [Item])]
grouped = groupBoxes keyOf between

-- | The four lines of a border of width t centred on the sides of a rectangle, as code blocks drew them before docs/adr/0271.
borderRectsBefore :: Rect -> Sp -> [Rect]
borderRectsBefore (Rect x y w h) t =
  let half = Sp (unSp t `div` 2)
   in [Rect (x - half) (y + h - half) (w + t) t, Rect (x - half) (y - half) (w + t) t, Rect (x - half) (y - half) t (h + t), Rect (x + w - half) (y - half) t (h + t)]

allSides :: [BoxSide]
allSides = [SideBefore, SideAfter, SideStart, SideEnd]

boxTests :: [TestTree]
boxTests =
  [ testGroup
      "B4: the paragraphs that go into one box"
      [ testCase "B4: one box" $ grouped [Para 1 'a'] @?= [Right (1, [Para 1 'a'])],
        testCase "B4: two of the same settings, one right after the other, are one box" $
          grouped [Para 1 'a', Para 1 'b'] @?= [Right (1, [Para 1 'a', Para 1 'b'])],
        testCase "B4: the spaces and the keep-with-next between them go inside" $
          grouped [Space, Para 1 'a', KeepNext, Space, Para 1 'b', Space, KeepNext] @?= [Left Space, Right (1, [Para 1 'a', KeepNext, Space, Para 1 'b']), Left Space, Left KeepNext],
        testCase "B4: two of other settings (a padding only differs) are two boxes" $
          grouped [Para 1 'a', Space, Para 2 'b'] @?= [Right (1, [Para 1 'a']), Left Space, Right (2, [Para 2 'b'])],
        testCase "B4: anything else between, as a start of a page, makes two boxes" $
          grouped [Para 1 'a', Space, Other, Para 1 'b'] @?= [Right (1, [Para 1 'a']), Left Space, Left Other, Right (1, [Para 1 'b'])],
        testCase "B4: a paragraph without a box is not in one" $
          grouped [Other, Para 1 'a', Other] @?= [Left Other, Right (1, [Para 1 'a']), Left Other]
      ],
    testGroup
      "B5, B6: the grid lines around the lines and the rectangle"
      [ testCase "B6: k is the fewest grid lines that leave d with half the leading" $ do
          -- p = 1200, h = 800: half the leading is 200
          [boxLinesAround 1200 800 d | d <- [0, 200, 201, 1400, 1401]] @?= [0, 0, 1, 1, 2]
          -- an odd leading: half of it is 200.5
          [boxLinesAround 1201 800 d | d <- [200, 201]] @?= [0, 1],
        testCase "B6: across the lines, the space between the side and the face is at least d and less than d + p" $
          forM_ [(p, h) | (p, h) <- [(1200, 800), (1201, 800), (65536 * 18, 65536 * 13)]] $ \(p, h) -> do
            let halfLead = Sp (unSp (p - h) `div` 2)
            forM_ [0, halfLead, halfLead + 1, halfLead + p, halfLead + p + 1, 3 * p] $ \d -> do
              let k = boxLinesAround p h d
                  inner = (toRational (unSp p - unSp h) / 2) + toRational k * toRational (unSp p)
              assertBool (show (p, h, d, k)) (inner >= toRational (unSp d) && inner < toRational (unSp d + unSp p))
              assertBool (show (p, h, d, k)) (k == 0 || inner - toRational (unSp p) < toRational (unSp d)),
        testCase "B5, B6: the before side in the middle of the space above the first grid line; along the lines d inside, in horizontal text" $ do
          let (p, h, d) = (1200, 800, 500)
              k = boxLinesAround p h d
              col = Rect 1000 2000 30000 24000
              first = 3
              n = 2 * k + 2
              r = boxArea False col p h first n 600 900
              faceTop j = rectY col + rectH col - fromIntegral (first + k + j) * p
          k @?= 1
          -- the before side: the middle of the space above grid line first
          abs (toRational (unSp (rectY r + rectH r)) - (toRational (unSp (rectY col + rectH col - fromIntegral first * p)) + toRational (unSp (p - h)) / 2)) < 1 @?= True
          -- the first line keeps its grid line: the face top at grid line first + k, d + something from the side
          toRational (unSp (rectY r + rectH r - faceTop 0)) >= toRational (unSp d) @?= True
          -- the last line: its face bottom at least d above the after side
          toRational (unSp (faceTop 1 - h - rectY r)) >= toRational (unSp d) @?= True
          -- along the lines: from the start of the column plus the indent to its end less the end indent; the lines d inside
          (rectX r, rectX r + rectW r) @?= (rectX col + 600, rectX col + rectW col - 900)
          boxLineRange 600 900 d @?= (600 + d, 900 + d),
        testCase "B5, B6: the before side on the right in vertical text" $ do
          let (p, h, d) = (1200, 800, 500)
              col = Rect 1000 2000 24000 30000
              first = 3
              r = boxArea True col p h first 4 600 900
          abs (toRational (unSp (rectX r + rectW r)) - (toRational (unSp (rectX col + rectW col - fromIntegral first * p)) + toRational (unSp (p - h)) / 2)) < 1 @?= True
          rectW r @?= 4 * p
          (rectY r + rectH r, rectY r) @?= (rectY col + rectH col - 600, rectY col + 900)
          boxLineRange 600 900 d @?= (1100, 1400)
      ],
    testGroup
      "the bands of a border without round corners"
      [ testCase "solid on the four sides: the rectangles of the border of code blocks, in their order" $ do
          let r = Rect 100 200 3000 4000
          boxBands False r 600 RuleSolid allSides @?= map ShapeRect (borderRectsBefore r 600)
          boxBands True r 600 RuleSolid allSides @?= map ShapeRect (borderRectsBefore r 600),
        testCase "border-sides = [\"start\"]: one band, on the left in horizontal text and at the top in vertical text" $ do
          let r = Rect 100 200 3000 4000
          boxBands False r 600 RuleSolid [SideStart] @?= [ShapeRect (Rect (100 - 300) (200 - 300) 600 (4000 + 600))]
          boxBands True r 600 RuleSolid [SideStart] @?= [ShapeRect (Rect (100 - 300) (200 + 4000 - 300) (3000 + 600) 600)]
      ],
    testGroup "B8, B9: the round corners" cornerTests
  ]

-- | Every corner of every part, side and fill: the radius and the outline in the rectangle.
cornerTests :: [TestTree]
cornerTests =
  [ testCase "B8: the radius of each corner is min(r, w/2, h/2) where it is rounded, else 0, for every r, part, sides, fill and writing" $
      forM_ cases $ \(vertical, rect@(Rect _ _ w h), r, (first, lastPart), sides, border) -> do
        let cs = boxCorners border sides first lastPart (cornerRadius r rect)
            r' = minimum [toRational (unSp r), toRational (unSp w) / 2, toRational (unSp h) / 2]
            rounded (bs, se) = (if bs == SideBefore then first else lastPart) && (not border || (bs `elem` sides && se `elem` sides))
            expect c = if rounded c then r' else 0
        (vertical, r, first, lastPart, sides, border, [beforeStart cs, beforeEnd cs, afterStart cs, afterEnd cs])
          @?= (vertical, r, first, lastPart, sides, border, map expect [(SideBefore, SideStart), (SideBefore, SideEnd), (SideAfter, SideStart), (SideAfter, SideEnd)]),
    testCase "B9: the outline and the paths of the border are inside the rectangle, through its corners where they are square" $
      forM_ cases $ \(vertical, rect, r, (first, lastPart), sides, border) -> do
        let cs = boxCorners border sides first lastPart (cornerRadius r rect)
            outline = boxOutline vertical rect cs
            runs = boxBorderRuns vertical rect cs sides
            inside (x, y) = x >= toRational (unSp (rectX rect)) && x <= toRational (unSp (rectX rect + rectW rect)) && y >= toRational (unSp (rectY rect)) && y <= toRational (unSp (rectY rect + rectH rect))
            points (start, segs) = start : concatMap segPoints segs
            segPoints = \case
              SegLine q -> [q]
              SegCurve a b c -> [a, b, c]
            ends (start, segs) = start : map segEnd segs
            segEnd = \case
              SegLine q -> q
              SegCurve _ _ c -> c
            corner (cx, cy) = (toRational (unSp cx), toRational (unSp cy))
            physical = physicalCorners vertical rect cs
        assertBool (show (vertical, r, first, lastPart, sides, border)) (all inside (points outline))
        assertBool (show (vertical, r, first, lastPart, sides, border)) (all (all inside . points . (\(s, g, _) -> (s, g))) runs)
        forM_ physical $ \(pt, radius) -> if radius == 0 then assertBool (show (pt, outline)) (corner pt `elem` ends outline) else pure (),
    testCase "B9: with r = 0 the outline is the rectangle" $ do
      let rect = Rect 100 200 3000 4000
          cs = boxCorners True allSides True True (cornerRadius 0 rect)
      boxOutline False rect cs @?= ((100, 200), [SegLine (3100, 200), SegLine (3100, 4200), SegLine (100, 4200), SegLine (100, 200)])
      boxOutline True rect cs @?= ((100, 200), [SegLine (3100, 200), SegLine (3100, 4200), SegLine (100, 4200), SegLine (100, 200)]),
    testCase "a closed border of four sides is one closed path; of before and after, two open ones" $ do
      let rect = Rect 0 0 4000 3000
          cs = boxCorners True allSides True True (cornerRadius 500 rect)
      [closed | (_, _, closed) <- boxBorderRuns False rect cs allSides] @?= [True]
      let cs2 = boxCorners True [SideBefore, SideAfter] True True (cornerRadius 500 rect)
      [closed | (_, _, closed) <- boxBorderRuns False rect cs2 [SideBefore, SideAfter]] @?= [False, False],
    testCase "the control points of a quarter are kappa r from its ends along the tangents" $ do
      let rect = Rect 0 0 4000 3000
          cs = boxCorners False allSides True True (cornerRadius 1000 rect)
      case boxOutline False rect cs of
        (start, SegLine a : SegCurve c1 c2 e : _) -> do
          start @?= (1000, 0)
          a @?= (3000, 0)
          c1 @?= (3000 + kappa * 1000, 0)
          c2 @?= (4000, 1000 - kappa * 1000)
          e @?= (4000, 1000)
        other -> assertFailure (show other)
  ]
  where
    rect0 = Rect 1000 2000 30000 9000
    half = Sp (9000 `div` 2)
    cases =
      [ (vertical, rect0, r, part, sides, border)
      | vertical <- [False, True],
        r <- [0, 1, half - 1, half, half + 1, 40000],
        part <- [(True, True), (True, False), (False, False), (False, True)],
        sides <- [allSides, [SideStart], [SideBefore, SideAfter], [SideBefore, SideAfter, SideStart]],
        border <- [False, True]
      ]
