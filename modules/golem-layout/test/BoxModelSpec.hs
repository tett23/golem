{- | Text set in boxes of closed paths (root ADR 0437): the boxes are made
in the tests, a circle, an ellipse, a star and concave polygons, and the
virtual bodies of the glyphs placed are checked against the shape made a
polygon in rationals (I2), with the bands skipped and the intervals
chosen (I3, I7) and the content that does not fit (I5).
-}
module BoxModelSpec (boxModelTests) where

import Data.Either (isLeft)
import Data.Text qualified as T
import Fixtures (look0)
import Golem.Geometry
import Golem.Geometry.Polygon (RPoint, flattenPath, insidePolygons)
import Golem.Layout.BoxModel
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (noBoxSource)
import Test.Tasty
import Test.Tasty.HUnit

boxModelTests :: TestTree
boxModelTests =
  testGroup
    "boxes of closed paths (root ADR 0437)"
    [ testCase "root ADR 0437 I2: the glyphs of three lines in a circle are inside it, the lines at its top and bottom shorter" $ do
        let box = textBox Horizontal (circle 0 0 (pt 50))
        placed <- flowed box [para 24]
        assertInside box placed
        case map (rectW . slotRect) (lineSlots box size pitch) of
          [top, middle, bottom] -> assertBool (show (top, middle, bottom)) (top < middle && bottom < middle)
          lens -> assertFailure ("not three lines: " <> show lens),
      testCase "root ADR 0437 I2: the glyphs in an ellipse are inside it, in horizontal and vertical writing and from either edge" $
        mapM_
          ( \(w, s) -> do
              let box = LayoutBox (ellipse 0 0 (pt 80) (pt 45)) NonZero (SetsText w s)
              placed <- flowed box [para 20, para 9]
              assertBool "some glyphs are placed" (not (null placed))
              assertInside box placed
          )
          [(w, s) | w <- [Horizontal, Vertical], s <- [UsualStart, OppositeStart]],
      testCase "root ADR 0437 I2: the vertices of a star that fall in a band do not cut into its intervals" $ do
        let box = textBox Horizontal (polygonPath star)
        placed <- flowed box [para 30]
        assertBool "some glyphs are placed" (not (null placed))
        assertInside box placed,
      testCase "root ADR 0437 I3: a band of the circle narrower than eight characters has no line, and every line is eight or wider" $ do
        let slots = lineSlots (textBox Horizontal (circle 0 0 (pt 50))) size pitch
        map slotBand slots @?= [2, 3, 4]
        assertBool (show slots) (all ((>= 8 * size) . rectW . slotRect) slots),
      testCase "root ADR 0437 I2, I3: in a concave shape whose band has two intervals of eight, only the first in the writing has text" $ do
        let box = textBox Horizontal (prongs 8 2 8)
        case lineSlots box size pitch of
          first : _ -> slotRect first @?= Rect 0 (pt 90) (pt 80) size
          [] -> assertFailure "no line"
        placed <- flowed box [para 8]
        assertInside box placed
        assertBool (show placed) (all (\(Rect x _ w _) -> x + w <= pt 80) placed),
      testCase "root ADR 0437 I7: a band of an interval of seven and one of eight has its text in the one of eight" $ do
        let box = textBox Horizontal (prongs 7 2 8)
        case lineSlots box size pitch of
          first : _ -> slotRect first @?= Rect (pt 90) (pt 90) (pt 80) size
          [] -> assertFailure "no line"
        placed <- flowed box [para 8]
        assertInside box placed
        assertBool (show placed) (all (\(Rect x _ _ _) -> x >= pt 90) placed),
      testCase "root ADR 0437 I5: content that just fits is set, one line more is an error and sets nothing" $ do
        let box = rectBox Horizontal (Rect 0 0 (pt 100) (pt 40))
        map slotBand (lineSlots box size pitch) @?= [0, 1, 2]
        fmap (map length) (flowInBox defaultParams box size pitch [para 30]) @?= Right [3]
        fmap (map length) (flowInBox defaultParams box size pitch [para 20, para 10]) @?= Right [2, 1]
        flowInBox defaultParams box size pitch [para 31] @?= Left BoxOverflow
        flowInBox defaultParams box size pitch [para 20, para 11] @?= Left BoxOverflow,
      testCase "root ADR 0437 I5: a line longer than its interval is an error" $
        let box = rectBox Horizontal (Rect 0 0 (pt 100) (pt 40))
         in flowInBox defaultParams box size pitch [[letter 0 (pt 101)] <> finish] @?= Left BoxOverflow,
      testCase "root ADR 0437 I5: content in the empty path or in a shape too narrow is an error; no content fits" $ do
        let empty = textBox Horizontal (Path [])
            narrow = rectBox Horizontal (Rect 0 0 (pt 79) (pt 40))
        lineSlots narrow size pitch @?= []
        isLeft (flowInBox defaultParams empty size pitch [para 1]) @?= True
        isLeft (flowInBox defaultParams narrow size pitch [para 1]) @?= True
        flowInBox defaultParams empty size pitch [] @?= Right []
        flowInBox defaultParams empty size pitch [[]] @?= Right [[]],
      testCase "a box that keeps text out has no line" $
        lineSlots (avoidBox (circle 0 0 (pt 50))) size pitch @?= [],
      testCase "a rectangle's lines start at its edge, one pitch apart, in vertical writing from the right" $
        map slotRect (lineSlots (rectBox Vertical (Rect 0 0 (pt 40) (pt 100))) size pitch)
          @?= [Rect (pt 30) 0 size (pt 100), Rect (pt 15) 0 size (pt 100), Rect 0 0 size (pt 100)]
    ]

size, pitch :: Sp
size = pt 10
pitch = pt 15

pt :: Rational -> Sp
pt r = Sp (round (r * 65536))

-- | The rectangles of the virtual bodies of the glyphs placed in a box.
flowed :: LayoutBox -> [[Item]] -> IO [Rect]
flowed box paras = case flowInBox defaultParams box size pitch paras of
  Left e -> assertFailure (show e) >> pure []
  Right ps -> pure [glyph slot off w | (slot, l) <- concat ps, (Box w _, off) <- placeLine l]
  where
    glyph (LineSlot _ (Rect x y w h)) off len = case boxRole box of
      SetsText Vertical _ -> Rect x (y + h - off - len) w len
      _ -> Rect (x + off) y len h

-- | Each rectangle is in the polygon of the shape: its corners inside, and no edge through its inside.
assertInside :: LayoutBox -> [Rect] -> IO ()
assertInside box rs =
  let polys = flattenPath (boxShape box)
      edges = [(a, b) | poly@(_ : rest) <- polys, (a, b) <- zip poly (rest <> take 1 poly)]
      corners (Rect x y w h) = [(r x, r y), (r (x + w), r y), (r x, r (y + h)), (r (x + w), r (y + h))]
      r (Sp v) = toRational v
      bad = [rect | rect <- rs, not (all (insidePolygons (boxFillRule box) polys) (corners rect)) || any (crossesInside rect) edges]
   in take 1 bad @?= []

-- | Whether a segment passes through the open inside of a rectangle.
crossesInside :: Rect -> (RPoint, RPoint) -> Bool
crossesInside (Rect (Sp x) (Sp y) (Sp w) (Sp h)) ((ax, ay), (bx, by))
  | max ax bx <= toRational x || min ax bx >= toRational (x + w) || max ay by <= toRational y || min ay by >= toRational (y + h) = False
  | otherwise =
      let range a d lo hi
            | d == 0 = if toRational lo < a && a < toRational hi then Just (0, 1) else Nothing
            | otherwise =
                let t0 = (toRational lo - a) / d
                    t1 = (toRational hi - a) / d
                 in Just (min t0 t1, max t0 t1)
       in case (range ax (bx - ax) x (x + w), range ay (by - ay) y (y + h)) of
            (Just (p0, p1), Just (q0, q1)) -> max 0 (max p0 q0) < min 1 (min p1 q1)
            _ -> False

-- | A paragraph of n glyphs of the size, with stretchable glue between them.
para :: Int -> [Item]
para n = concat [letter i size : [glue 0 (size `divSp'` 4) 0 | i < n - 1] | i <- [0 .. n - 1]] <> finish
  where
    divSp' (Sp a) b = Sp (a `div` b)

letter :: Int -> Sp -> Item
letter t w = Box w (BoxContent (T.pack (show t)) False 0 0 0 look0 0 0 [] 0 0 noBoxSource Nothing noLeaf 0 Nothing)

finish :: [Item]
finish = [Penalty 0 infPenalty NoHyphen, glue 0 filStretch 0, Penalty 0 (negate infPenalty) NoHyphen]

-- | A circle of four cubic curves, counterclockwise from the right.
circle :: Rational -> Rational -> Sp -> Path
circle cx cy (Sp r) = ellipse cx cy (Sp r) (Sp r)

ellipse :: Rational -> Rational -> Sp -> Sp -> Path
ellipse cx cy (Sp rx) (Sp ry) =
  let k = 5522847498 / 10000000000 :: Rational
      p (x, y) = (Sp (round (cx + x)), Sp (round (cy + y)))
      a = toRational rx
      b = toRational ry
   in Path
        [ SubPath
            (p (a, 0))
            [ CurveTo (p (a, k * b)) (p (k * a, b)) (p (0, b)),
              CurveTo (p (negate (k * a), b)) (p (negate a, k * b)) (p (negate a, 0)),
              CurveTo (p (negate a, negate (k * b))) (p (negate (k * a), negate b)) (p (0, negate b)),
              CurveTo (p (k * a, negate b)) (p (a, negate (k * b))) (p (a, 0))
            ]
            True
        ]

polygonPath :: [(Rational, Rational)] -> Path
polygonPath = \case
  [] -> Path []
  q : qs -> Path [SubPath (at q) (map (LineTo . at) qs) True]
  where
    at (x, y) = (pt x, pt y)

-- | A star of five points, 200pt across, its vertices in pt.
star :: [(Rational, Rational)]
star = [(100, 200), (124, 130), (200, 130), (140, 80), (162, 0), (100, 50), (38, 0), (60, 80), (0, 130), (76, 130)]

{- | Two prongs on a base, 100pt high: the left one l characters of 10pt
wide, a gap of g, the right one r wide; the base 20pt high.
-}
prongs :: Rational -> Rational -> Rational -> Path
prongs l g r =
  let w = (l + g + r) * 10
   in polygonPath [(0, 0), (w, 0), (w, 100), ((l + g) * 10, 100), ((l + g) * 10, 20), (l * 10, 20), (l * 10, 100), (0, 100)]
