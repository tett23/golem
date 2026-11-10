{- | Knuth–Plass line breaking (golem-layout ADR 0001) with the
microtypography of ADR 0005. Integer arithmetic only: TeX's badness
approximation, exact rational adjustment ratios, ties broken as TeX
breaks them (ADR 0008).
-}
module Golem.Layout.KnuthPlass
  ( Sp (..),
    Item (..),
    glue,
    GlueKind (..),
    glueKindName,
    AdjustOrder (..),
    Hyphen (..),
    isPatternHyphen,
    endsWithHyphen,
    BoxContent (..),
    Leaf (..),
    noLeaf,
    MarkBox (..),
    Params (..),
    defaultParams,
    Line (..),
    lineOverfull,
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
    glueAmounts,
    reachedLimit,
  )
where

import Data.List (maximumBy, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Ord (Down (..), comparing)
import Data.Ratio ((%))
import Data.Text (Text)
import Golem.Layout.Look (BoxSource, Look)
import Golem.Length (Sp (..))

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
    bcEdgeEnd :: !Sp,
    {- | the look of each base character of a ruby box (golem-layout ADR
    0011); empty for any other box. The algorithm does not read it.
    -} bcBaseLooks :: ![Look],
    {- | the padding of inline code before and after its characters
    (golem-driver ADR 0029), inside the width: the glyphs start
    'bcPadStart' after the start of the box. The algorithm does not read it.
    -} bcPadStart :: !Sp,
    bcPadEnd :: !Sp,
    {- | the definition that decided the size of the box and where its
    characters are in the source (golem-cli ADR 0008), for golem preflight.
    The algorithm does not read it, and nothing that draws the box does.
    -} bcSource :: !BoxSource,
    {- | of the mark of a note (docs/adr/0177): the look of its place and its
    parts; Nothing for any other box. The algorithm does not read it.
    -} bcMark :: !(Maybe MarkBox),
    {- | the leaf of the structure tree of the PDF that the characters of
    the box belong to (docs/adr ADR 0183); the reading of a ruby box is
    the next leaf. The algorithm does not read it.
    -} bcLeaf :: !Leaf,
    {- | where the first character of the box is in the source, a byte
    offset in the file of the span of 'bcSource' (docs/adr ADR 0195): the
    character itself, where the span is that of the whole text; -1 for
    characters the source does not have. The algorithm does not read it,
    and nothing that draws the box does.
    -} bcAt :: !Int
  }
  deriving stock (Eq, Show)

{- | What the mark of a note keeps for its drawing (docs/adr/0177): the
look of its place, whose size and face place the mark, and its parts,
each with the kind of its box (the 'bcTag' of a box of its own), its text
and where it starts along the line from the start of the box.
-}
data MarkBox = MarkBox
  { mbPlace :: !Look,
    mbParts :: ![(Int, Text, Sp)]
  }
  deriving stock (Eq, Show)

{- | A leaf of the structure tree of the PDF (docs/adr ADR 0183): the place
of the composition, which the caller names, and the leaf in it, numbered
in the order of the inlines. A box of no place is not read: an artifact.
-}
data Leaf = Leaf
  { leafSite :: ![Int],
    leafIndex :: !Int
  }
  deriving stock (Eq, Ord, Show)

-- | The leaf of a box of no place.
noLeaf :: Leaf
noLeaf = Leaf [] 0

-- | What kind of break a penalty is (ADR 0008).
data Hyphen
  = -- | a prohibition, a break between mono ruby bases, the paragraph end
    NoHyphen
  | {- | a break found by Liang's patterns; the line ends with a hyphen
    drawn, which protrudes by the amount given (golem-layout ADR 0014)
    -}
    PatternHyphen !Sp
  | -- | the break after a hyphen or dash written in the word; nothing is added
    ExplicitHyphen
  | {- | a break inside inline code other than at a space (golem-layout ADR
    0034); the line ends with the mark given drawn, as wide as the penalty
    -}
    WrapMark !Text
  | {- | a break at a soft hyphen (U+00AD) written in the word (docs/adr
    ADR 0272); the line ends with a hyphen drawn, which protrudes by the
    amount given, as at a break of the patterns, but the first pass takes it
    -}
    SoftHyphen !Sp
  deriving stock (Eq, Show)

-- | Whether a break is one found by the patterns.
isPatternHyphen :: Hyphen -> Bool
isPatternHyphen = \case
  PatternHyphen _ -> True
  _ -> False

{- | Whether a line broken there ends with a hyphen drawn: a break of the
patterns or at a soft hyphen (docs/adr ADR 0272).
-}
endsWithHyphen :: Hyphen -> Bool
endsWithHyphen = \case
  PatternHyphen _ -> True
  SoftHyphen _ -> True
  _ -> False

data Item
  = Box {itemWidth :: !Sp, itemContent :: !BoxContent}
  | Glue
      { itemWidth :: !Sp,
        itemStretch :: !Sp,
        itemShrink :: !Sp,
        -- | the space it is made of (docs/adr/0278)
        itemKind :: !GlueKind,
        {- | the size of its characters, 1 zw (docs/adr/0278): of the aki its
        amounts are of, of the space; 0 for 'OtherGlue'
        -} itemZw :: !Sp
      }
  | Penalty {itemWidth :: !Sp, itemPenalty :: !Int, itemHyphen :: !Hyphen}
  deriving stock (Eq, Show)

-- | A glue of no kind and no size ('OtherGlue').
glue :: Sp -> Sp -> Sp -> Item
glue w y z = Glue w y z OtherGlue 0

{- | The kind of a glue, the space it is made of (docs/adr/0278): the
places of line adjustment of JLReq 3.8.3 and 3.8.4. A space between two
characters takes the first kind of the list that it is.
-}
data GlueKind
  = -- | a space between words, not in inline code nor in a range of superscript or subscript
    WordSpaceGlue
  | -- | a space before or after a middle dot
    MiddleDotGlue
  | -- | a space before an opening bracket or after a closing one
    BracketsGlue
  | -- | a space after a comma
    CommaGlue
  | -- | a space after a full stop in the line
    FullStopGlue
  | -- | the space at the start of a paragraph
    ParagraphStartGlue
  | -- | a space between a Japanese character and a Latin one
    JapaneseWesternGlue
  | -- | a space between other Japanese characters
    BetweenCharactersGlue
  | -- | any other glue: of a space of code, the end of a paragraph
    OtherGlue
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The name of a kind in shrink-order and stretch-order (docs/adr/0278); 'OtherGlue' has none.
glueKindName :: GlueKind -> Maybe Text
glueKindName = \case
  WordSpaceGlue -> Just "word-space"
  MiddleDotGlue -> Just "middle-dot"
  BracketsGlue -> Just "brackets"
  CommaGlue -> Just "comma"
  FullStopGlue -> Just "full-stop"
  ParagraphStartGlue -> Just "paragraph-start"
  JapaneseWesternGlue -> Just "japanese-western"
  BetweenCharactersGlue -> Just "between-characters"
  OtherGlue -> Nothing

{- | How the shortfall or the excess of a set line is spread over its glue
(docs/adr/0278): by one ratio over all of it, or in stages of kinds, each
used up to its limit before the next.
-}
data AdjustOrder
  = AdjustUniform
  | AdjustStaged {aoShrink :: [[GlueKind]], aoStretch :: [[GlueKind]]}
  deriving stock (Eq, Show)

{- | A hyphen break, of any kind (of the patterns, written, soft; docs/adr
ADR 0272): consecutive ones cost 'pDoubleHyphenDemerits'. A break with the
wrap mark of code is not one (golem-layout ADR 0034).
-}
itemFlagged :: Item -> Bool
itemFlagged = \case
  Penalty _ _ (PatternHyphen _) -> True
  Penalty _ _ ExplicitHyphen -> True
  Penalty _ _ (SoftHyphen _) -> True
  _ -> False

infPenalty :: Int
infPenalty = 10000

-- | The badness of a line beyond the scale, TeX's inf_bad: the cap of 'badness'.
infBad :: Int
infBad = 10000

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
    pProtrusion :: !Bool,
    {- | the stretch at the end of every line, of a paragraph whose lines are
    not justified (docs/adr/0189): 'filStretch' there, 0 otherwise. It
    counts in the badness of a line only, not in its ratio
    -} pEndStretch :: !Sp,
    {- | pull in first (docs/adr/0274): a line that shrinks to fit within
    the shrink of its glue, the compression of the glyphs left out, has the
    badness 0 and is decent; the paragraph style's line-adjustment
    -} pPullInFirst :: !Bool,
    {- | the most the glue of a set line stretches, as a ratio
    (docs/adr/0274): the paragraph style's stretch-limit in permille. It
    changes where the items of a line are placed, not the breaks
    -} pStretchLimit :: !(Maybe Rational),
    {- | the order the glue of a set line shrinks and stretches in
    (docs/adr/0278): the paragraph style's shrink-order and stretch-order.
    It changes where the items of a line are placed, not the breaks
    -} pAdjustOrder :: !AdjustOrder
  }
  deriving stock (Eq, Show)

defaultParams :: Params
defaultParams = Params 100 200 0 10 10000 10000 Nothing False 0 False Nothing AdjustUniform

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
    {- | how far the line sticks out past its target (docs/adr ADR 0210):
    its natural width, every shrink and the compression of the glyphs
    taken, less the target; 0 when it fits
    -} lineOverflow :: !Sp,
    -- | the edges of the first and the last box (golem-layout ADR 0009)
    lineEdge :: !(Sp, Sp),
    -- | the most its glue stretches, as a ratio, from 'pStretchLimit' (docs/adr/0274)
    lineStretchLimit :: !(Maybe Rational),
    -- | the order its glue shrinks and stretches in, from 'pAdjustOrder' (docs/adr/0278)
    lineAdjustOrder :: !AdjustOrder
  }
  deriving stock (Eq, Show)

-- | The natural width exceeds the target even when fully shrunk: 'lineOverflow' is positive.
lineOverfull :: Line -> Bool
lineOverfull = (> 0) . lineOverflow

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
badness (Sp t) (Sp s)
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

data Eval = Eval !Int !Fitness !Integer !Bool !Bool !Bool -- badness, fitness, demerits, feasible, fits (not overfull), alive

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
            {- the last pass takes any line of finite badness; a line beyond
            the scale (TeX's inf_bad) is made only by pushing out what does
            not fit ('pushOut'): its demerits are capped, so they cannot tell
            a line of a few spaced-out characters from a nearly full one -}
            4 -> infBad - 1
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
      Glue w' y' z' _ _ -> Totals (w + w') (y + y') (z + z') e
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
                feasible = [(a, fit, d) | (a, Eval _ fit d True _ _) <- evals]
                forced = case at b of
                  Penalty _ p _ -> p <= negate infPenalty
                  _ -> False
                -- a node whose line is already overfull, but the width of the penalty at b, can never be used again (golem-layout ADR 0036)
                survivors = if forced then [] else [a | (a, Eval _ _ _ _ _ alive) <- evals, alive]
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
             in survivors <> newNodes
          -- nothing is left at b when every line from the actives overflows there, or b is a forced break no feasible line reaches
          go actives = \case
            [] -> actives
            b : rest -> case step actives b of
              []
                | allowOverfull -> case pushOut actives b of
                    Just node -> go [node] [c | c <- candidates, c > nPos node]
                    Nothing -> go (overfullRescue actives b) rest
              next -> go next rest
          {- what does not fit goes to the next line (JLReq 追い出し): from
          the active whose line can end latest before b without overflowing,
          the line ends there, however loose; the breaking starts over after it -}
          pushOut actives b =
            let options =
                  [ (Down p, nDem a + d, Down (nPos a), Node p (nLine a + 1) fit (flaggedAt p) (nDem a + d) (Just a))
                  | a <- actives,
                    -- the line holds a box at least, and does not overflow
                    (p, Eval _ fit d _ _ _) <- take 1 [(p, ev) | p <- reverse (takeWhile (< b) candidates), p > after (nPos a), ev@(Eval _ _ _ _ True _) <- [evaluate tol emergency a p]]
                  ]
             in case sortOn (\(k1, k2, k3, _) -> (k1, k2, k3)) options of
                  (_, _, _, node) : _ -> Just node
                  [] -> Nothing
          overfullRescue actives b =
            case sortOn (overflow b) actives of
              (a : _) -> [Node b (nLine a + 1) 3 (flaggedAt b) (nDem a + overfullDemerits) (Just a)]
              [] -> []
          overflow b a = tW (sumsTo b) - tW (sumsTo (after (nPos a))) - lineWidth (nLine a)
          finalActives = go [start] candidates
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
          stretch = tY tw - tY ts + emergency + ey + pEndStretch ps
          glueShrink = tZ tw - tZ ts
          shrink = glueShrink + ez
          shortfall = lineWidth (nLine a) - natural
          (bad, shrinking, overfull)
            | shortfall > 0 = (badness shortfall stretch, False, False)
            | shortfall == 0 = (0, False, False)
            | negate shortfall > shrink = (10000, True, True)
            {- pulling in first (docs/adr/0274): a line that shrinks within
            the shrink of its glue, the compression of the glyphs left out,
            has the badness 0, and is decent -}
            | pPullInFirst ps && negate shortfall <= glueShrink = (0, True, False)
            | otherwise = (badness (negate shortfall) shrink, True, False)
          fit = fitnessOf shrinking bad
          pen = case at b of
            Penalty _ p _ -> p
            _ -> 0
          d =
            lineDemerits ps bad pen
              + (if nFlagged a && flaggedAt b then toInteger (pDoubleHyphenDemerits ps) else 0)
              + (if abs (fit - nFit a) > 1 then toInteger (pAdjDemerits ps) else 0)
          {- the node lives on while the line to b, but the width of the
          penalty at b, does not overflow (golem-layout ADR 0036): a line that
          ends at a later break does not hold that width, the wrap mark of
          code (golem-layout ADR 0034) as wide as the text after it -}
          alive = negate (shortfall + penW) <= shrink
       in Eval bad fit d (not overfull && bad <= tol) (not overfull) alive
    flaggedAt i = itemFlagged (at i)
    patternAt i = case at i of
      Penalty _ _ (PatternHyphen _) -> True
      _ -> False
    protrusionOf s b
      | not (pProtrusion ps) = (0, 0)
      | otherwise =
          let firstBox = listToMaybe [c | j <- [s .. b - 1], Box _ c <- [at j]]
              lastBox = listToMaybe [c | j <- [b - 1, b - 2 .. s], Box _ c <- [at j]]
              -- a line ending at a pattern hyphen or a soft hyphen protrudes by the hyphen (golem-layout ADR 0014, docs/adr ADR 0272)
              end = case at b of
                Penalty _ _ (PatternHyphen q) -> q
                Penalty _ _ (SoftHyphen q) -> q
                _ -> maybe 0 bcProtrudeEnd lastBox
           in (maybe 0 bcProtrudeStart firstBox, end)
    -- the edges of the first and last boxes count whether or not protrusion is on
    edgesOf s b =
      let firstBox = listToMaybe [c | j <- [s .. b - 1], Box _ c <- [at j]]
          lastBox = listToMaybe [c | j <- [b - 1, b - 2 .. s], Box _ c <- [at j]]
       in (maybe 0 bcEdgeStart firstBox, maybe 0 bcEdgeEnd lastBox)
    -- the limit the steps reach (golem-layout ADR 0029)
    expansionOf e = case pExpansion ps of
      Just (limit, stp) -> let m = toInteger (reachedLimit limit stp) in (Sp (unSp e * m `div` 1000), Sp (unSp e * m `div` 1000))
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
            | shortfall > 0 && stretch > 0 = unSp shortfall % unSp stretch
            | shortfall < 0 && shrink > 0 = max (-1) (unSp shortfall % unSp shrink)
            | otherwise = 0
          overflow = max 0 (natural - shrink - target)
          expansion = case pExpansion ps of
            Just (limit, stp) | e > 0 -> expansionStep limit stp ratio
            _ -> 0
       in Line its ratio target expansion (protS, protE) overflow edges (pStretchLimit ps) (pAdjustOrder ps)

{- | The expansion of a line in permille (golem-layout ADR 0029): the
ratio times the limit the steps reach, rounded to a multiple of the
step, towards zero for a line that stretches and away from it for one
that shrinks, so that the glue of a line that shrinks shrinks by no more
than the ratio; with integer arithmetic.
-}
expansionStep :: Int -> Int -> Rational -> Int
expansionStep limit stp ratio
  | m <= 0 = 0
  | otherwise =
      let raw = ratio * toRational m
          clamped = max (negate (toRational m)) (min (toRational m) raw)
          q = clamped / toRational stp
          steps = (if clamped < 0 then floor q else truncate q) :: Integer
       in fromInteger steps * stp
  where
    m = reachedLimit limit stp

{- | The limit of the glyph expansion the steps reach (golem-layout ADR
0029): the limit rounded down to a multiple of the step; 0 when the step
is not positive, is larger than the limit, or the limit is negative.
-}
reachedLimit :: Int -> Int -> Int
reachedLimit limit stp
  | stp <= 0 || limit <= 0 = 0
  | otherwise = limit `div` stp * stp

{- | The start offsets of the items of a set line. Expansion (a multiple
of the step) scales the expandable boxes; the glue takes up the rest, each
glue by its amount ('glueAmounts'). Offsets are rounded once from exact
rationals, so rounding never accumulates along the line.
-}
placeLine :: Line -> [(Item, Sp)]
placeLine l =
  let its = lineItems l
      (protS, _) = lineProtrusion l
      (edgeS, _) = lineEdge l
      ex = toRational (lineExpansion l) / 1000
      lastIx = length its - 1
      -- a penalty's width (a hyphen) counts only where the line breaks
      widths _ [] = []
      widths as ((i, it) : more) = case it of
        Box w c -> toRational (unSp w) * (if bcExpandable c then 1 + ex else 1) : widths as more
        Glue {itemWidth = w} -> case as of
          a : as' -> toRational (unSp w) + a : widths as' more
          [] -> toRational (unSp w) : widths [] more
        Penalty w _ _ -> (if i == lastIx then toRational (unSp w) else 0) : widths as more
      offsets = scanl (+) (toRational (unSp (edgeS - protS))) (widths (glueAmounts l) (zip [0 :: Int ..] its))
   in zip its (map (Sp . round) offsets)

{- | What a set line has to take up by its glue (docs/adr/0274): its
target less its natural width and the share of the glyph expansion;
negative when the glue shrinks.
-}
lineRest :: Line -> Rational
lineRest l =
  let its = lineItems l
      (protS, protE) = lineProtrusion l
      (edgeS, edgeE) = lineEdge l
      ex = toRational (lineExpansion l) / 1000
      lastIx = length its - 1
      natural = toRational (unSp (sum [itemWidth it | (i, it) <- zip [0 :: Int ..] its, not (isPenalty it) || i == lastIx] - protS - protE + edgeS + edgeE))
      isPenalty = \case
        Penalty {} -> True
        _ -> False
      expandable = toRational (unSp (sum [w | Box w c <- its, bcExpandable c]))
   in toRational (unSp (lineTarget l)) - natural - expandable * ex

{- | The ratio by which the glue of a set line is stretched or shrunk,
after the glyph expansion has taken its share; a line that stretches no
more than its stretch limit (docs/adr/0274), what is left of the line
left after its last item. It places the glue of a line of 'AdjustUniform'.
-}
glueRatio :: Line -> Rational
glueRatio l =
  let its = lineItems l
      rest = lineRest l
      ys = toRational (unSp (sum [itemStretch g | g@Glue {} <- its]))
      zs = toRational (unSp (sum [itemShrink g | g@Glue {} <- its]))
   in if rest > 0 && ys > 0
        then maybe id min (lineStretchLimit l) (rest / ys)
        else if rest < 0 && zs > 0 then max (-1) (rest / zs) else 0

{- | What each glue of a set line adds to its width, in the order of the
glue (docs/adr/0278); negative where it shrinks. A line of 'AdjustUniform'
takes 'glueRatio' of each. A line of 'AdjustStaged' takes its stages in
order, the kinds of no stage last: each stage up to the shrink or the
stretch of its glue, its glue in proportion to it. What stretching is
left past every stage goes to the glue that stretches, in proportion to
its size, so that each widens by as many em; in proportion to its
stretch where none has a size. A line with the glue of the end of a
paragraph, which takes every stretch, stretches as one of
'AdjustUniform'. The stretch limit (docs/adr/0274) caps what the line
stretches by before the stages share it.
-}
glueAmounts :: Line -> [Rational]
glueAmounts l = case lineAdjustOrder l of
  AdjustStaged shrinkOrder stretchOrder
    | rest < 0 -> staged shrinkOrder itemShrink (negate rest) negate (\_ -> [])
    | rest > 0, not (any ((>= filStretch) . itemStretch) gs) -> staged stretchOrder itemStretch capped id spread
  _ -> uniform
  where
    gs = [g | g@Glue {} <- lineItems l]
    rest = lineRest l
    num = toRational . unSp
    uniform =
      let r = glueRatio l
       in [num (if r >= 0 then itemStretch g else itemShrink g) * r | g <- gs]
    ys = sum (map (num . itemStretch) gs)
    capped = maybe rest (\m -> min rest (m * ys)) (lineStretchLimit l)
    -- the stage of a kind: the first that has it, after every stage for one in none
    stageOf order k = case [i | (i, ks) <- zip [0 :: Int ..] order, k `elem` ks] of
      i : _ -> i
      [] -> length order
    {- each stage up to its limit, in order, its glue in proportion to its
    limit; what is left past the last stage to 'extra' -}
    staged order limitOf amount sign extra =
      let limits = map (num . limitOf) gs
          kinds = map (stageOf order . itemKind) gs
          go _ [] = []
          go remaining (k : ks) =
            let cap = sum [lim | (lim, k') <- zip limits kinds, k' == k]
                took = min remaining cap
             in (k, if cap > 0 then took / cap else 0) : go (remaining - took) ks
          shares = go amount [0 .. length order]
          base = [sign (lim * fromMaybe 0 (lookup k shares)) | (lim, k) <- zip limits kinds]
          left = amount - sum limits
       in if left > 0 then zipWith (+) base (extra left <> repeat 0) else base
    -- what is left past every stage, by size, or by stretch where no glue that stretches has a size
    spread left =
      let stretching = [num (itemStretch g) > 0 | g <- gs]
          sizes = [if st then num (itemZw g) else 0 | (g, st) <- zip gs stretching]
          total = sum sizes
          stretches = [if st then num (itemStretch g) else 0 | (g, st) <- zip gs stretching]
       in if total > 0
            then [left * z / total | z <- sizes]
            else if ys > 0 then [left * y / ys | y <- stretches] else map (const 0) gs
