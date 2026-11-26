{- | Paths and rectangles of the layout (root ADR 0437): a path is a list
of subpaths, each a start, lines and cubic curves, and whether it is
closed; an arc is drawn by cubic curves. Coordinates are sp, with the
origin at the lower left as in PDF. A rectangle is a closed path of a
special form ('rectPath'); the places that need speed keep it as a
rectangle.

The path data of SVG (the commands M, L, C and Z, absolute coordinates)
is read by 'parsePathData'; golem-project reads the paths of
@style.toml@ with it.
-}
module Golem.Geometry
  ( Point,
    Segment (..),
    segmentEnd,
    SubPath (..),
    Path (..),
    FillRule (..),
    LineCap (..),
    LineJoin (..),
    Stroke (..),
    solidStroke,
    Rect (..),
    rectPath,
    insideRect,
    PathDataError (..),
    parsePathData,
  )
where

import Data.Char (isDigit)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Length (Sp (..))

-- | A point: x and y in sp, the origin at the lower left.
type Point = (Sp, Sp)

-- | A part of a subpath from the end of the one before: a line, or a cubic curve (its two control points and its end).
data Segment = LineTo !Point | CurveTo !Point !Point !Point
  deriving stock (Eq, Show)

-- | Where a segment ends.
segmentEnd :: Segment -> Point
segmentEnd = \case
  LineTo p -> p
  CurveTo _ _ p -> p

-- | A subpath: its start, its segments, and whether it is closed back to its start.
data SubPath = SubPath {subStart :: !Point, subSegments :: ![Segment], subClosed :: !Bool}
  deriving stock (Eq, Show)

-- | A path: its subpaths in order.
newtype Path = Path {pathSubPaths :: [SubPath]}
  deriving stock (Eq, Show)

{- | Which points a filled path covers (ISO 32000-1 8.5.3.3): those of a
winding number not 0 (nonzero, the default) or of an odd one (even-odd).
-}
data FillRule = NonZero | EvenOdd
  deriving stock (Eq, Show)

-- | The ends of a stroked line (ISO 32000-1 8.4.3.3).
data LineCap = ButtCap | RoundCap | SquareCap
  deriving stock (Eq, Show)

-- | The corners of a stroked line (ISO 32000-1 8.4.3.4).
data LineJoin = MiterJoin | RoundJoin | BevelJoin
  deriving stock (Eq, Show)

-- | The line a path is stroked with: its width, its ends and its corners.
data Stroke = Stroke {strokeWidth :: !Sp, strokeCap :: !LineCap, strokeJoin :: !LineJoin}
  deriving stock (Eq, Show)

-- | A line of a width with the defaults of PDF: butt ends and mitred corners.
solidStroke :: Sp -> Stroke
solidStroke w = Stroke w ButtCap MiterJoin

{- | A rectangle: the lower left corner and the size, in sp, with the
origin at the lower left of the page (docs/adr ADR 0088, root ADR 0437).
-}
data Rect = Rect {rectX :: !Sp, rectY :: !Sp, rectW :: !Sp, rectH :: !Sp}
  deriving stock (Eq, Show)

-- | The rectangle as a closed path: from its lower left corner counterclockwise.
rectPath :: Rect -> Path
rectPath (Rect x y w h) = Path [SubPath (x, y) [LineTo (x + w, y), LineTo (x + w, y + h), LineTo (x, y + h)] True]

-- | Whether a point is in the rectangle, its edges included.
insideRect :: Rect -> (Rational, Rational) -> Bool
insideRect (Rect x y w h) (px, py) =
  let x0 = toRational (unSp (min x (x + w)))
      x1 = toRational (unSp (max x (x + w)))
      y0 = toRational (unSp (min y (y + h)))
      y1 = toRational (unSp (max y (y + h)))
   in x0 <= px && px <= x1 && y0 <= py && py <= y1

-- | Why path data cannot be read: the offset of the character in the text, and what is wrong there.
data PathDataError = PathDataError {pdeOffset :: !Int, pdeReason :: !Text}
  deriving stock (Eq, Show)

{- | Reads path data (SVG 2, 9.3): the commands M, L, C and Z with
absolute coordinates, the numbers separated by white space or a comma. A
command's numbers may repeat (after M, they are lines); a command other
than M after Z starts at the start of the closed subpath. The numbers
are exact decimals, each turned into sp by the function (of the unit of
the coordinates). Empty data is the empty path.
-}
parsePathData :: (Rational -> Sp) -> Text -> Either PathDataError Path
parsePathData toUnit src = go Nothing [] (tokens 0 (T.unpack src))
  where
    -- the subpath being read (its start, its segments reversed), and the subpaths done (reversed)
    go cur done = \case
      Left e -> Left e
      Right [] -> Right (Path (reverse (finish cur done)))
      Right ((at, TCmd c) : rest) -> case c of
        'M' ->
          pairs at 1 rest >>= \(ps, rest') -> case ps of
            [p] : more -> go (Just (p, reverse [LineTo q | [q] <- more], False)) (finish cur done) (Right rest')
            _ -> Left (PathDataError at "M には座標が要る")
        'L' -> draw at cur done rest 1 (\ps -> [LineTo q | [q] <- ps])
        'C' -> draw at cur done rest 3 (\ps -> [CurveTo a b e | [a, b, e] <- ps])
        'Z' -> withCurrent at cur $ \(s, segs, _) -> go (Just (s, segs, True)) done (Right rest)
        _ -> Left (PathDataError at ("知らないコマンド " <> T.singleton c))
      Right ((at, TNum _) : _) -> Left (PathDataError at "数の前にコマンドが要る")
    -- the segments of a drawing command; after Z, they start a subpath at the start of the closed one
    draw at cur done rest n mk = withCurrent at cur $ \(s, segs, closed) ->
      pairs at n rest >>= \(ps, rest') ->
        let (segs', done') = if closed then ([], finish cur done) else (segs, done)
         in go (Just (s, reverse (mk ps) <> segs', False)) done' (Right rest')
    withCurrent at cur k = case cur of
      Just c -> k c
      Nothing -> Left (PathDataError at "パスは M で始める")
    finish cur done = case cur of
      Just (s, segs, closed) -> SubPath s (reverse segs) closed : done
      Nothing -> done
    -- the numbers after a command in groups of n points, at least one group
    pairs at n ts =
      let (nums, rest) = span isNum ts
          vals = [v | (_, TNum v) <- nums]
          k = 2 * n
       in if null vals || length vals `mod` k /= 0
            then Left (PathDataError at ("座標の数が " <> T.pack (show k) <> " の倍数でない"))
            else Right (groups n (points vals), rest)
    isNum = \case
      (_, TNum _) -> True
      _ -> False
    points = \case
      x : y : more -> (toUnit x, toUnit y) : points more
      _ -> []
    groups n xs = case splitAt n xs of
      ([], _) -> []
      (g, more) -> g : groups n more

data Token = TCmd !Char | TNum !Rational

-- | The commands and the numbers of path data, each with its offset.
tokens :: Int -> String -> Either PathDataError [(Int, Token)]
tokens at = \case
  [] -> Right []
  c : rest
    | c `elem` (" \t\n\r\f," :: String) -> tokens (at + 1) rest
    | c `elem` ("MLCZ" :: String) -> ((at, TCmd c) :) <$> tokens (at + 1) rest
    | isDigit c || c `elem` ("+-." :: String) -> case number (c : rest) of
        Just (v, n, rest') -> ((at, TNum v) :) <$> tokens (at + n) rest'
        Nothing -> Left (PathDataError at "数として読めない")
    | otherwise -> Left (PathDataError at ("知らないコマンド " <> T.singleton c))

-- | A decimal number (an optional sign, digits, an optional fraction), its exact value and its length.
number :: String -> Maybe (Rational, Int, String)
number s0 =
  let (sign, s1) = case s0 of
        '-' : more -> (-1, more)
        '+' : more -> (1, more)
        _ -> (1, s0)
      signLen = length s0 - length s1
      (whole, s2) = span isDigit s1
      (frac, s3) = case s2 of
        '.' : more -> span isDigit more
        _ -> ("", s2)
      dot = if take 1 s2 == "." then 1 else 0
      digits = whole <> frac
   in if null digits
        then Nothing
        else
          let v = fromInteger (read digits) / (10 ^ length frac)
           in Just (sign * v, signLen + length whole + dot + length frac, s3)
