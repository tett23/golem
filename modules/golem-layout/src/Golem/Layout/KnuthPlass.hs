{- | Knuth–Plass line breaking (golem-layout ADR 0001) with the
microtypography of ADR 0005. Integer arithmetic only: TeX's badness
approximation, exact rational adjustment ratios, ties broken as TeX
breaks them (ADR 0008).
-}
module Golem.Layout.KnuthPlass
  ( Sp,
    Item (..),
    Hyphen (..),
    itemFlagged,
    BoxContent (..),
    Params (..),
    defaultParams,
    Line (..),
    Breaks (..),
    breakParagraph,
    badness,
    infPenalty,
    filStretch,
    lineDemerits,
    Fitness,
    fitnessOf,
    placeLine,
    glueRatio,
    expansionStep,
  )
where

import Data.List (maximumBy, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Ord (Down (..), comparing)
import Data.Ratio ((%))
import Data.Text (Text)
import Golem.Layout.Look (Look)

type Sp = Integer

{- | What a box shows. Golem's composition fills these in; the algorithm
only reads the microtypography fields.
-}
data BoxContent = BoxContent
  { bcText :: !Text,
    -- | glyph widths may be expanded or compressed (Latin glyphs, ADR 0005)
    bcExpandable :: !Bool,
    -- | how far the box may stick out at the start or end of a line (ADR 0005)
    bcProtrudeStart :: !Sp,
    bcProtrudeEnd :: !Sp,
    -- | opaque data for later stages (ruby, rotation…)
    bcTag :: !Int,
    -- | the look of the box; the algorithm does not read it (golem-driver ADR 0004)
    bcLook :: !Look,
    -- | at the line start (end), the space added inside the line: a ruby's overhang taken back (golem-layout ADR 0009)
    bcEdgeStart :: !Sp,
    bcEdgeEnd :: !Sp
  }
  deriving stock (Eq, Show)

-- | What kind of break a penalty is (ADR 0008).
data Hyphen
  = -- | a prohibition, a break between mono ruby bases, the paragraph end
    NoHyphen
  | -- | a break found by Liang's patterns; the line ends with a hyphen drawn
    PatternHyphen
  | -- | the break after a hyphen or dash written in the word; nothing is added
    ExplicitHyphen
  deriving stock (Eq, Show)

data Item
  = Box {itemWidth :: !Sp, itemContent :: !BoxContent}
  | Glue {itemWidth :: !Sp, itemStretch :: !Sp, itemShrink :: !Sp}
  | Penalty {itemWidth :: !Sp, itemPenalty :: !Int, itemHyphen :: !Hyphen}
  deriving stock (Eq, Show)

-- | A hyphen break, of either kind: consecutive ones cost 'pDoubleHyphenDemerits'.
itemFlagged :: Item -> Bool
itemFlagged = \case
  Penalty _ _ h -> h /= NoHyphen
  _ -> False

infPenalty :: Int
infPenalty = 10000

{- | The stretch of the glue that ends a paragraph: large enough that the
last line always has badness 0, standing in for TeX's fil.
-}
filStretch :: Sp
filStretch = 2 ^ (50 :: Int)

data Params = Params
  { pPretolerance :: !Int,
    pTolerance :: !Int,
    pEmergencyStretch :: !Sp,
    pLinePenalty :: !Int,
    pDoubleHyphenDemerits :: !Int,
    pAdjDemerits :: !Int,
    -- | glyph expansion: (limit, step) in permille (ADR 0005)
    pExpansion :: !(Maybe (Int, Int)),
    pProtrusion :: !Bool
  }
  deriving stock (Eq, Show)

defaultParams :: Params
defaultParams = Params 100 200 0 10 10000 10000 Nothing False

data Line = Line
  { -- | the items of the line, discardable items after the break removed
    lineItems :: ![Item],
    -- | the adjustment ratio (negative when shrinking)
    lineRatio :: !Rational,
    -- | the target width
    lineTarget :: !Sp,
    -- | the expansion of the glyphs in permille, a multiple of the step
    lineExpansion :: !Int,
    -- | protrusion at the start and the end
    lineProtrusion :: !(Sp, Sp),
    -- | the natural width exceeds the target even when fully shrunk
    lineOverfull :: !Bool,
    -- | the edges of the first and the last box (golem-layout ADR 0009)
    lineEdge :: !(Sp, Sp)
  }
  deriving stock (Eq, Show)

data Breaks = Breaks
  { brLines :: ![Line],
    -- | the break positions (indices into the items)
    brPositions :: ![Int],
    brDemerits :: !Integer,
    -- | which pass succeeded: 1 pretolerance, 2 tolerance, 3 emergency, 4 overfull allowed
    brPass :: !Int
  }
  deriving stock (Eq, Show)

-- ------------------------------------------------------------------ TeX arithmetic

-- | TeX's badness: approximately 100 (t/s)^3, capped at 10000.
badness :: Sp -> Sp -> Int
badness t s
  | t == 0 = 0
  | s <= 0 = 10000
  | otherwise =
      let r
            | t <= 7230584 = (t * 297) `div` s
            | s >= 1663497 = t `div` (s `div` 297)
            | otherwise = t
       in if r > 1290 then 10000 else fromInteger ((r * r * r + 0x20000) `div` 0x40000)

-- | 0 very loose, 1 loose, 2 decent, 3 tight.
type Fitness = Int

fitnessOf :: Bool -> Int -> Fitness
fitnessOf shrinking b
  | shrinking = if b > 12 then 3 else 2
  | b >= 100 = 0
  | b > 12 = 1
  | otherwise = 2

lineDemerits :: Params -> Int -> Int -> Integer
lineDemerits ps b p =
  let l = toInteger (pLinePenalty ps + b)
      -- TeX caps the line's part (ADR 0008)
      base = if abs l >= 10000 then 100000000 else l * l
      pen = toInteger p
   in if p >= 0
        then base + pen * pen
        else if p > negate infPenalty then base - pen * pen else base

-- ------------------------------------------------------------------ the algorithm

data Totals = Totals {tW :: !Sp, tY :: !Sp, tZ :: !Sp, tE :: !Sp}

data Eval = Eval !Int !Fitness !Integer !Bool !Bool -- badness, fitness, demerits, feasible, alive

-- | Demerits of a line forced through in the last pass.
overfullDemerits :: Integer
overfullDemerits = 10 ^ (8 :: Int)

data Node = Node
  { nPos :: !Int, -- the break position; -1 for the start
    nLine :: !Int, -- lines before this break
    nFit :: !Fitness,
    nFlagged :: !Bool,
    nDem :: !Integer,
    nPrev :: !(Maybe Node)
  }

{- | Breaks a paragraph. @lineWidth i@ is the target length of line i
(from 0), so lines can differ in length (L*(i), ADR 0001 and 0004).
-}
breakParagraph :: Params -> (Int -> Sp) -> [Item] -> Breaks
breakParagraph ps lineWidth items =
  case firstJust [attempt pass | pass <- passes] of
    Just r -> r
    Nothing -> error "breakParagraph: the overfull pass always succeeds"
  where
    passes = [1 | pPretolerance ps >= 0] <> [2, 3, 4]
    attempt pass =
      let tol = case pass of
            1 -> pPretolerance ps
            4 -> 10000
            _ -> pTolerance ps
          emergency = if pass >= 3 then pEmergencyStretch ps else 0
          -- the first pass, like TeX's, uses explicit hyphens but no pattern hyphens (ADR 0008)
          usePatterns = pass /= 1
       in if pass == 3 && pEmergencyStretch ps <= 0
            then Nothing
            else fmap (\r -> r {brPass = pass}) (run tol emergency usePatterns (pass == 4))
    firstJust = listToMaybe . concatMap (maybe [] pure)
    arr = Map.fromList (zip [0 ..] items)
    n = length items
    at i = arr Map.! i
    -- prefix sums of width, stretch, shrink, expandable box width
    prefix = scanl add (Totals 0 0 0 0) items
    add (Totals w y z e) = \case
      Box w' c -> Totals (w + w') y z (if bcExpandable c then e + w' else e)
      Glue w' y' z' -> Totals (w + w') (y + y') (z + z') e
      Penalty {} -> Totals w y z e
    pre = Map.fromList (zip [0 ..] prefix)
    sumsTo i = pre Map.! i -- totals of items [0, i)
    isBreak i = case at i of
      Penalty _ p _ -> p < infPenalty
      Glue {} -> i > 0 && isBox (at (i - 1))
      Box {} -> False
    isBox = \case
      Box {} -> True
      _ -> False
    -- where the line after a break at i starts: discardable items are skipped
    after i
      | i < 0 = 0
      | otherwise = skip (i + 1)
      where
        skip j
          | j >= n = j
          | otherwise = case at j of
              Box {} -> j
              Penalty _ p _ | p <= negate infPenalty -> j
              _ -> skip (j + 1)
    run tol emergency usePatterns allowOverfull =
      let candidates = [i | i <- [0 .. n - 1], isBreak i, usePatterns || not (patternAt i)]
          start = Node (-1) 0 2 False 0 Nothing
          step actives b =
            let evals = [(a, evaluate tol emergency a b) | a <- actives]
                feasible = [(a, fit, d) | (a, Eval _ fit d True _) <- evals]
                forced = case at b of
                  Penalty _ p _ -> p <= negate infPenalty
                  _ -> False
                -- a node whose line is already overfull can never be used again
                survivors = if forced then [] else [a | (a, Eval _ _ _ _ alive) <- evals, alive]
                newNodes =
                  Map.elems $
                    foldl'
                      ( \m (a, fit, d) ->
                          let node' = Node b (nLine a + 1) fit (flaggedAt b) (nDem a + d) (Just a)
                           in -- equal demerits keep the later predecessor, as TeX does (ADR 0008):
                              -- the actives are in the order of their positions, then fitness
                              Map.insertWith (\new old -> if nDem new <= nDem old then new else old) (nLine a + 1, fit) node' m
                      )
                      Map.empty
                      feasible
                next = survivors <> newNodes
             in if null next && allowOverfull then overfullRescue actives b else next
          overfullRescue actives b =
            case sortOn (overflow b) actives of
              (a : _) -> [Node b (nLine a + 1) 3 (flaggedAt b) (nDem a + overfullDemerits) (Just a)]
              [] -> []
          overflow b a = tW (sumsTo b) - tW (sumsTo (after (nPos a))) - lineWidth (nLine a)
          finalActives = foldl' step [start] candidates
          ends = [a | a <- finalActives, nPos a == n - 1]
          -- of the least demerits, the path whose last line is loosest (TeX's
          -- strict < at the end), then whose (position, fitness) from the
          -- second-to-last break is greatest: the one TeX keeps, merging line
          -- counts (ADR 0008, ADR 0010)
          key a = case walk a of
            x : rest -> (Down (nFit x), [(nPos y, nFit y) | y <- rest])
            [] -> (Down 0, [])
       in case ends of
            [] -> Nothing
            _ ->
              let least = minimum (map nDem ends)
               in Just (assemble (maximumBy (comparing key) [a | a <- ends, nDem a == least]))
    evaluate tol emergency a b =
      let s = after (nPos a)
          tw = sumsTo b
          ts = sumsTo s
          penW = case at b of
            Penalty w _ _ -> w
            _ -> 0
          (protS, protE) = protrusionOf s b
          (edgeS, edgeE) = edgesOf s b
          natural = tW tw - tW ts + penW - protS - protE + edgeS + edgeE
          (ey, ez) = expansionOf (tE tw - tE ts)
          stretch = tY tw - tY ts + emergency + ey
          shrink = tZ tw - tZ ts + ez
          shortfall = lineWidth (nLine a) - natural
          (bad, shrinking, overfull)
            | shortfall > 0 = (badness shortfall stretch, False, False)
            | shortfall == 0 = (0, False, False)
            | negate shortfall > shrink = (10000, True, True)
            | otherwise = (badness (negate shortfall) shrink, True, False)
          fit = fitnessOf shrinking bad
          pen = case at b of
            Penalty _ p _ -> p
            _ -> 0
          d =
            lineDemerits ps bad pen
              + (if nFlagged a && flaggedAt b then toInteger (pDoubleHyphenDemerits ps) else 0)
              + (if abs (fit - nFit a) > 1 then toInteger (pAdjDemerits ps) else 0)
       in Eval bad fit d (not overfull && bad <= tol) (not overfull)
    flaggedAt i = itemFlagged (at i)
    patternAt i = case at i of
      Penalty _ _ PatternHyphen -> True
      _ -> False
    protrusionOf s b
      | not (pProtrusion ps) = (0, 0)
      | otherwise =
          let firstBox = listToMaybe [c | j <- [s .. b - 1], Box _ c <- [at j]]
              lastBox = listToMaybe [c | j <- [b - 1, b - 2 .. s], Box _ c <- [at j]]
           in (maybe 0 bcProtrudeStart firstBox, maybe 0 bcProtrudeEnd lastBox)
    -- the edges of the first and last boxes count whether or not protrusion is on
    edgesOf s b =
      let firstBox = listToMaybe [c | j <- [s .. b - 1], Box _ c <- [at j]]
          lastBox = listToMaybe [c | j <- [b - 1, b - 2 .. s], Box _ c <- [at j]]
       in (maybe 0 bcEdgeStart firstBox, maybe 0 bcEdgeEnd lastBox)
    expansionOf e = case pExpansion ps of
      Just (limit, _) -> (e * toInteger limit `div` 1000, e * toInteger limit `div` 1000)
      Nothing -> (0, 0)
    walk nd = case nPrev nd of
      Nothing -> []
      Just p -> nd : walk p
    assemble best =
      let chain = reverse (walk best)
          positions = map nPos chain
          starts = 0 : map after (init positions)
          ls = [mkLine i s b | (i, s, b) <- zip3 [0 ..] starts positions]
       in Breaks ls positions (nDem best) 0
    mkLine i s b =
      let its = [at j | j <- [s .. b - 1]] <> [Penalty w p f | Penalty w p f <- [at b], w > 0]
          tw = sumsTo b
          ts = sumsTo s
          penW = case at b of
            Penalty w _ _ -> w
            _ -> 0
          (protS, protE) = protrusionOf s b
          edges@(edgeS, edgeE) = edgesOf s b
          natural = tW tw - tW ts + penW - protS - protE + edgeS + edgeE
          target = lineWidth i
          e = tE tw - tE ts
          (ey, ez) = expansionOf e
          stretch = tY tw - tY ts + ey
          shrink = tZ tw - tZ ts + ez
          shortfall = target - natural
          ratio
            | shortfall > 0 && stretch > 0 = shortfall % stretch
            | shortfall < 0 && shrink > 0 = max (-1) (shortfall % shrink)
            | otherwise = 0
          overfull = shortfall < 0 && negate shortfall > shrink
          expansion = case pExpansion ps of
            Just (limit, stp) | e > 0 -> expansionStep limit stp ratio
            _ -> 0
       in Line its ratio target expansion (protS, protE) overfull edges

{- | The expansion of a line in permille: the ratio times the limit,
rounded towards zero to a multiple of the step, with integer arithmetic.
-}
expansionStep :: Int -> Int -> Rational -> Int
expansionStep limit stp ratio
  | stp <= 0 = 0
  | otherwise =
      let raw = ratio * toRational limit
          clamped = max (negate (toRational limit)) (min (toRational limit) raw)
          steps = truncate (clamped / toRational stp) :: Integer
       in fromInteger steps * stp

{- | The start offsets of the items of a set line. Expansion (a multiple
of the step) scales the expandable boxes; the glue takes up the rest.
Offsets are rounded once from exact rationals, so rounding never
accumulates along the line.
-}
placeLine :: Line -> [(Item, Sp)]
placeLine l =
  let its = lineItems l
      (protS, _) = lineProtrusion l
      (edgeS, _) = lineEdge l
      ex = toRational (lineExpansion l) / 1000
      g = glueRatio l
      lastIx = length its - 1
      -- a penalty's width (a hyphen) counts only where the line breaks
      width (i, it) = case it of
        Box w c -> toRational w * (if bcExpandable c then 1 + ex else 1)
        Glue w y z -> toRational w + (if g >= 0 then toRational y else toRational z) * g
        Penalty w _ _ -> if i == lastIx then toRational w else 0
      offsets = scanl (+) (toRational (edgeS - protS)) (zipWith (curry width) [0 ..] its)
   in zip its (map round offsets)

{- | The ratio by which the glue of a set line is stretched or shrunk,
after the glyph expansion has taken its share.
-}
glueRatio :: Line -> Rational
glueRatio l =
  let its = lineItems l
      (protS, protE) = lineProtrusion l
      (edgeS, edgeE) = lineEdge l
      ex = toRational (lineExpansion l) / 1000
      lastIx = length its - 1
      natural = toRational (sum [itemWidth it | (i, it) <- zip [0 :: Int ..] its, not (isPenalty it) || i == lastIx] - protS - protE + edgeS + edgeE)
      isPenalty = \case
        Penalty {} -> True
        _ -> False
      expandable = toRational (sum [w | Box w c <- its, bcExpandable c])
      rest = toRational (lineTarget l) - natural - expandable * ex
      ys = toRational (sum [y | Glue _ y _ <- its])
      zs = toRational (sum [z | Glue _ _ z <- its])
   in if rest > 0 && ys > 0
        then rest / ys
        else if rest < 0 && zs > 0 then max (-1) (rest / zs) else 0
