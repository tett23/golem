{- | The invariants of the line breaking (docs/adr/0209, its section
「不変条件」), as predicates over a paragraph that goes in and the lines
that come out. They read nothing of 'breakParagraph' but its input and
its 'Breaks'; the lines are read with 'placeLine' and 'glueRatio'.

The width of the lines is W. A line is one of 'brLines', the characters
of a line those of the 'bcText' of its boxes, joined. The character at
the start (end) of a line is the first (last) character of its first
(last) box, its class that of its look, a character of both scripts in
a Latin language span taking its Japanese class (docs/adr ADR 0187), as
the composition reads it.
-}
module LineBreakInvariants
  ( LineInvariant (..),
    Breach (..),
    Paragraph (..),
    bruteLimit,
    l1AllOnce,
    l2LineStart,
    l3LineEnd,
    l4Inseparable,
    l5Width,
    l6Justified,
    l7Optimal,
    l8InsideWords,
    l9Hyphens,
    l10Spaces,
    l11Aki,
    l12Expansion,
    l13Protrusion,
    t1LastLineBoxes,
    i4NoHyphensWithShy,
    lineInvariants,
    refArabicDigit,
    refNumeral,
    refPrefixed,
    refPostfixed,
    pairForbidden,
    adjacentPairs,
    forbidPairs,
    penalizePairs,
    withoutNumberUnits,
    numberUnitOf,
    breaches,
    codeInvariants,
    codeBreaches,
    paddingBreaches,
    breakItem,
    lineEnd,
    latinSpace,
  )
where

import Data.Char (chr, isDigit, isLetter)
import Data.List (mapAccumL)
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Layout.Aki (AkiPos (..), akiBetween, defaultAkiSet, noAki)
import Golem.Layout.Aki qualified as A
import Golem.Layout.CharClass (charClass, dualJapaneseClass, isDualCharacter, isExtending, spanIsJapanese)
import Golem.Layout.Hyphenation (hyphenMins)
import Golem.Layout.Hyphenation.Languages (patternsFor)
import Golem.Layout.Japanese (BoxKind (..), CharClass (..), boxKind, lineEndProhibited, lineStartProhibited, lookClass)
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..), plainLook)
import Golem.Length qualified as L
import KnuthPlassBrute (breakCandidates, bruteDemerits)

{- | The invariants of docs/adr/0209, by their numbers, L1, L8 and L9 as
I1, I2 and I3 of docs/adr ADR 0272 widen them, I4 of that ADR, B2 to B4
of golem-layout ADR 0049 (L4 widened by them too), T1 of
golem-layout ADR 0032, C1 to C8 of golem-layout ADR 0034, and J1 to J7 of golem-layout
ADR 0045, whose J3 takes the place of C3. J5 compares the items with those
before golem-layout ADR 0045, which no output tells: the tests of the
items check it. D1 to D5 of golem-layout ADR 0048 compare the items of
code with padding with those without it ('paddingBreaches').
-}
data LineInvariant = L1 | L2 | L3 | L4 | L5 | L6 | L7 | L8 | L9 | L10 | L11 | L12 | L13 | T1 | I4 | B2 | B3 | B4 | C1 | C2 | C6 | C7 | C8 | J1 | J2 | J3 | J4 | J6 | J7 | D1 | D2 | D3 | D4 | D5 | R5 | R6 | W1 | W2
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | An invariant broken, the line it is broken at (from 0; -1 for the whole paragraph), and how.
data Breach = Breach {breachOf :: !LineInvariant, breachLine :: !Int, breachWhy :: !String}
  deriving stock (Eq, Show)

{- | What a predicate reads: the characters of the paragraph, those of its
inline code, the font size, the width of its lines, the strictness of its
kinsoku, its items, the parameters of its breaking and the breaks that
came out, the advance of a character in em (Latin text or not), and the
penalty of a number and its unit (docs/adr/0275).
-}
data Paragraph = Paragraph
  { pText :: !Text,
    pCode :: !Text,
    pSize :: !Sp,
    pWidth :: !Sp,
    pStrict :: !Bool,
    pItems :: ![Item],
    pParams :: !Params,
    pBreaks :: !Breaks,
    pAdvance :: Bool -> Char -> Rational,
    pNumberUnit :: !Int
  }

-- | The breaks of a paragraph L7 brute-forces: up to 8 on pull requests (docs/adr/0209, its section 3).
bruteLimit :: Int
bruteLimit = 8

type Check = Int -> Paragraph -> [Breach]

-- * reading lines

linesOf :: Paragraph -> [Line]
linesOf = brLines . pBreaks

boxes :: Line -> [BoxContent]
boxes l = [c | Box _ c <- lineItems l]

firstBox, lastBox :: Line -> Maybe BoxContent
firstBox l = case boxes l of
  c : _ -> Just c
  [] -> Nothing
lastBox l = case reverse (boxes l) of
  c : _ -> Just c
  [] -> Nothing

-- | The text of a box without its combining characters, unless nothing else is left.
baseOf :: BoxContent -> Text
baseOf c = case T.filter (not . isExtending) (bcText c) of
  t | T.null t -> bcText c
  t -> t

-- | Whether a character of a box is one of both scripts in a Latin language span.
latinDual :: BoxContent -> Char -> Bool
latinDual c ch = isDualCharacter ch && maybe False (not . spanIsJapanese) (lkLang (bcLook c))

-- | The class of a character of a box, as the line breaking reads it.
classOf :: BoxContent -> Char -> CharClass
classOf c ch = if latinDual c ch then dualJapaneseClass ch else lookClass (bcLook c) ch

startClass, endClass :: BoxContent -> Maybe CharClass
startClass c = classOf c . fst <$> T.uncons (baseOf c)
endClass c = classOf c . snd <$> T.unsnoc (baseOf c)

-- | The text of a line.
textOf :: Line -> Text
textOf l = T.concat (map bcText (boxes l))

-- | Where the last item of a line, as 'placeLine' places it, ends.
lineEnd :: Line -> Sp
lineEnd l = case reverse (placeLine l) of
  [] -> fst (lineEdge l) - fst (lineProtrusion l)
  (it, off) : _ ->
    let ex = toRational (lineExpansion l) / 1000
        g = glueRatio l
        w = case it of
          Box bw c -> toRational (unSp bw) * (if bcExpandable c then 1 + ex else 1)
          Glue gw y z -> toRational (unSp gw) + (if g >= 0 then toRational (unSp y) else toRational (unSp z)) * g
          Penalty pw _ _ -> toRational (unSp pw)
     in Sp (unSp off + round w)

-- | The protrusion at the end of a line.
endProtrusion :: Line -> Sp
endProtrusion = snd . lineProtrusion

-- | The glue of a space between Latin words (golem-layout's Japanese composition): its width, half of it to stretch, a third to shrink.
latinSpace :: Paragraph -> Item
latinSpace p =
  let sw = L.zwToSp (pSize p) (pAdvance p True ' ')
   in Glue sw (Sp (unSp sw `div` 2)) (Sp (unSp sw `div` 3))

{- | The glue of a space of inline code (golem-layout ADR 0017): the
advance of a space in the font of code, neither stretching nor shrinking.
The paragraphs of the predicates have no tracking, and their code is set
in the advances of the paragraph.
-}
codeSpace :: Paragraph -> Item
codeSpace p = Glue (L.zwToSp (pSize p) (pAdvance p True ' ')) 0 0

-- | The lines but the last, each with the next.
pairs :: Paragraph -> [(Int, Line, Line)]
pairs p = let ls = linesOf p in zip3 [0 ..] ls (drop 1 ls)

-- | Whether a line is wider than W: the exception of L5.
wide :: Paragraph -> Line -> Bool
wide p l = lineEnd l > pWidth p + endProtrusion l + 1

-- * the invariants

{- | L1, as I1 of docs/adr ADR 0272 widens it: no box of a line holds a
soft hyphen (U+00AD), and the characters of the lines, joined, are those
of the paragraph, the soft hyphens and the spaces between Latin words
left out.
-}
l1AllOnce :: Check
l1AllOnce _ p =
  let got = T.concat (map textOf (linesOf p))
      want = T.filter (\c -> c /= ' ' && c /= shy) (pText p)
   in [Breach L1 i ("line " <> show (i + 1) <> " has a box of a soft hyphen: " <> show (bcText c)) | (i, l) <- zip [0 ..] (linesOf p), c <- boxes l, T.any (== shy) (bcText c)]
        <> [Breach L1 (-1) ("the lines hold " <> show got <> ", not " <> show want) | got /= want]

-- | The soft hyphen (docs/adr ADR 0272).
shy :: Char
shy = '\xAD'

-- | L2: no line after the first starts with a character of line-start prohibition, but a line wider than W.
l2LineStart :: Check
l2LineStart _ p =
  [ Breach L2 (i + 1) ("line " <> show (i + 2) <> " starts with " <> show (textOf next))
  | (i, _, next) <- pairs p,
    Just c <- [firstBox next],
    Just k <- [startClass c],
    lineStartProhibited (pStrict p) k,
    not (wide p next)
  ]

-- | L3: no line but the last ends with an opening bracket, but a line wider than W.
l3LineEnd :: Check
l3LineEnd _ p =
  [ Breach L3 i ("line " <> show (i + 1) <> " ends with " <> show (textOf l))
  | (i, l, _) <- pairs p,
    Just c <- [lastBox l],
    Just k <- [endClass c],
    lineEndProhibited k,
    not (wide p l)
  ]

{- | L4: no line breaks between two inseparable characters next to each
other, a break after a hyphen or a dash written in a word among them; a
line may break at a space between two (golem-layout ADR 0028, its
section 4), a space of inline code too (golem-layout ADR 0038, its
section 2). Nor between the boxes of a pair of golem-layout ADR 0049
that may not be broken (in horizontal writing), but a line wider than W
(the exception of L5).
-}
l4Inseparable :: Check
l4Inseparable _ p =
  [ Breach L4 i ("lines " <> show (i + 1) <> " and " <> show (i + 2) <> " break between " <> show (textOf l) <> " and " <> show (textOf next))
  | (i, l, next) <- pairs p,
    Just a <- [lastBox l],
    endClass a == Just Inseparable,
    Just b <- [firstBox next],
    startClass b == Just Inseparable,
    breakItem p i `notElem` map Just [latinSpace p, codeSpace p]
  ]
    <> [ Breach L4 i ("lines " <> show (i + 1) <> " and " <> show (i + 2) <> " break between " <> show x <> " and " <> show y <> ", a pair that may not be broken")
       | (i, l, _) <- pairs p,
         Just at <- [breakIndex p i],
         (i1, i2, x, y) <- kept,
         i1 < at,
         at < i2,
         not (wide p l)
       ]
  where
    -- the pairs of golem-layout ADR 0049, and of docs/adr/0275 when its penalty is 10000, once for the paragraph
    kept = [q | q@(_, _, x, y) <- adjacentPairs (pText p) (pItems p), pairForbidden False x y || (pNumberUnit p >= infPenalty && isJust (numberUnitOf x y))]

{- | L5: no line ends past W and its protrusion at the end, with 1 sp of
rounding, but a line that is overfull and has no break where it would
fit: ending it at any break of its own, it is still wider than W.
-}
l5Width :: Check
l5Width _ p =
  concat
    [ [Breach L5 i ("line " <> show (i + 1) <> " ends at " <> show (lineEnd l) <> ", past " <> show (pWidth p) <> ", and is not overfull") | not (lineOverfull l)]
        <> [Breach L5 i ("line " <> show (i + 1) <> " is overfull, but would fit if it ended after " <> show (T.concat [bcText c | Box _ c <- take j (lineItems l)])) | lineOverfull l, j <- take 1 (fittingBreaks p l)]
    | (i, l) <- zip [0 :: Int ..] (linesOf p),
      wide p l
    ]

{- | The breaks of a line, by the index of the item, where the line would
end within W: the natural width of the items before them, with the
hyphen of a break at a penalty, less all they can shrink, is W or less.
-}
fittingBreaks :: Paragraph -> Line -> [Int]
fittingBreaks p l =
  [ j
  | j <- breakCandidates 2 its,
    j > 0,
    j < length its,
    any isBox (take j its),
    fits j
  ]
  where
    its = lineItems l
    ps = pParams p
    isBox = \case
      Box {} -> True
      _ -> False
    fits j =
      let before = take j its
          penW = case its !! j of
            Penalty w _ _ -> w
            _ -> 0
          bs = [c | Box _ c <- before]
          firstB = take 1 bs
          lastB = take 1 (reverse bs)
          protS = if pProtrusion ps then sum (map bcProtrudeStart firstB) else 0
          protE
            | not (pProtrusion ps) = 0
            | otherwise = case its !! j of
                Penalty _ _ (PatternHyphen q) -> q
                Penalty _ _ (SoftHyphen q) -> q
                _ -> sum (map bcProtrudeEnd lastB)
          natural = sum [w | Box w _ <- before] + sum [w | Glue w _ _ <- before] + penW - protS - protE + sum (map bcEdgeStart firstB) + sum (map bcEdgeEnd lastB)
          expandable = sum [w | Box w c <- before, bcExpandable c]
          shrinkE = case pExpansion ps of
            -- the limit the steps reach (golem-layout ADR 0029)
            Just (limit, stp) -> Sp (unSp expandable * toInteger (reachedLimit limit stp) `div` 1000)
            Nothing -> 0
          shrink = sum [z | Glue _ _ z <- before] + shrinkE
       in natural - shrink <= pWidth p

{- | L6: every line but the last that is not overfull ends at W and its
protrusion at the end, with 1 sp of rounding. A line without glue that
stretches may end before it (docs/adr/0222, D1): the specification
spaces out a line pushed out as far as its stretch allows; but where it
has boxes that take the glyph expansion and the expansion is short of
its limit, it is short by less than a step of the expansion (golem-layout
ADR 0029, E6).
-}
l6Justified :: Check
l6Justified _ p =
  [ Breach L6 i ("line " <> show (i + 1) <> " " <> show (textOf l) <> " ends at " <> show (lineEnd l) <> ", not at " <> show target)
  | (i, l, _) <- pairs p,
    not (lineOverfull l),
    let target = pWidth p + endProtrusion l,
    abs (lineEnd l - target) > 1,
    not (lineEnd l < target && noStretch l && shortByLessThanAStep l (target - lineEnd l)),
    -- a line whose stretch the limit caps ends before W (docs/adr/0274, R6)
    not (capped l)
  ]
  where
    noStretch l = all (<= 0) [y | Glue _ y _ <- lineItems l]
    -- short by less than a step of the expansion where it has not reached its limit
    shortByLessThanAStep l short = case pExpansion (pParams p) of
      Just (limit, stp)
        | x > 0,
          abs (lineExpansion l) < reachedLimit limit stp ->
            toInteger (unSp short) < unSp x * toInteger stp `div` 1000 + 1
      _ -> True
      where
        x = sum [w | Box w c <- lineItems l, bcExpandable c]

{- | Whether the stretch limit of a line (docs/adr/0274) caps its glue:
the ratio without the limit is more than it.
-}
capped :: Line -> Bool
capped l = case lineStretchLimit l of
  Just m -> glueRatio l {lineStretchLimit = Nothing} > m
  Nothing -> False

{- | R5 of docs/adr/0274: no line that is not overfull stretches its glue
by a ratio more than the stretch limit of the paragraph.
-}
r5Limit :: Check
r5Limit _ p = case pStretchLimit (pParams p) of
  Nothing -> []
  Just m ->
    [ Breach R5 i ("line " <> show (i + 1) <> " " <> show (textOf l) <> " stretches by " <> show (glueRatio l) <> ", past " <> show m)
    | (i, l) <- zip [0 ..] (linesOf p),
      not (lineOverfull l),
      glueRatio l > m || lineStretchLimit l /= Just m
    ]

{- | R6 of docs/adr/0274: a line that the limit caps stretches its glue by
the limit and ends where its natural width and its stretch times the
limit end from the line start (with 1 sp of rounding), before W; its first
item is where it was without the limit.
-}
r6Capped :: Check
r6Capped _ p =
  [ Breach R6 i ("line " <> show (i + 1) <> " " <> show (textOf l) <> " capped ends at " <> show (lineEnd l) <> ", not at " <> show want <> ", or past W")
  | (i, l) <- zip [0 ..] (linesOf p),
    not (lineOverfull l),
    capped l,
    Just m <- [lineStretchLimit l],
    let unlimited = l {lineStretchLimit = Nothing}
        want = Sp (round (toRational (unSp (lineEnd unlimited)) - (glueRatio unlimited - m) * toRational (unSp (sum [y | Glue _ y _ <- lineItems l])))),
    abs (lineEnd l - want) > 1
      || lineEnd l >= pWidth p + endProtrusion l
      || map snd (take 1 (placeLine l)) /= map snd (take 1 (placeLine unlimited))
  ]

{- | L7: in the first two passes, without glyph expansion and protrusion,
and with no more breaks than the limit given, the demerits are the least
of every way to break the paragraph in the tolerance of that pass.
-}
l7Optimal :: Check
l7Optimal limit p
  | brPass br `notElem` [1, 2] || isJust (pExpansion ps) || pProtrusion ps = []
  | length (breakCandidates (brPass br) (pItems p)) > limit = []
  | otherwise = case bruteDemerits ps (pWidth p) (brPass br) (pItems p) of
      Just least | least == brDemerits br -> []
      found -> [Breach L7 (-1) ("pass " <> show (brPass br) <> ": the demerits are " <> show (brDemerits br) <> ", the least of every way is " <> maybe "none" show found)]
  where
    br = pBreaks p
    ps = pParams p

{- | L8, as I2 of docs/adr ADR 0272 widens it: a line breaks between two
boxes of Latin text (two that take the glyph expansion) only at a hyphen
of the patterns, after a hyphen or a dash written in the word, at a soft
hyphen, or at a space.
-}
l8InsideWords :: Check
l8InsideWords _ p =
  [ Breach L8 i ("lines " <> show (i + 1) <> " and " <> show (i + 2) <> " break inside " <> show (bcText a <> bcText b) <> " at " <> show at)
  | (i, l, next) <- pairs p,
    Just a <- [lastBox l],
    Just b <- [firstBox next],
    bcExpandable a && bcExpandable b,
    let at = breakItem p i,
    not (allowed at)
  ]
  where
    allowed = \case
      Just (Glue {}) -> True
      Just (Penalty _ _ h) -> h /= NoHyphen
      _ -> False

-- | The index of the item a line breaks at.
breakIndex :: Paragraph -> Int -> Maybe Int
breakIndex p i = case drop i (brPositions (pBreaks p)) of
  b : _ | b >= 0 && b < length (pItems p) -> Just b
  _ -> Nothing

-- | The item a line breaks at.
breakItem :: Paragraph -> Int -> Maybe Item
breakItem p i = (pItems p !!) <$> breakIndex p i

{- | L9: a line broken at a hyphen of the patterns ends with the width of
a hyphen, at least two characters of its element before the break and at
least three after it (read as the letters kept before and after a break
of the language of the word, docs/adr ADR 0276); a line broken after a hyphen or dash written in
the word ends with it and adds no hyphen; the first pass breaks at no
hyphen of the patterns, nor does a word of a language span without
patterns. As I3 of docs/adr ADR 0272 widens it: there is a penalty of a
soft hyphen at each run of soft hyphens of the paragraph between two Latin
letters, and at nothing else, of the width of a hyphen and a penalty of
50; a line broken at one ends with that width, a letter of its element on
either side, and may be of the first pass.
-}
l9Hyphens :: Check
l9Hyphens _ p =
  [ Breach L9 (-1) ("the items have " <> show (length softs) <> " breaks at soft hyphens, the paragraph " <> show wanted)
  | length softs /= wanted
  ]
    <> [Breach L9 (-1) ("a break at a soft hyphen is of width " <> show w <> " and penalty " <> show pen) | (w, pen) <- softs, w /= hyphen || pen /= 50]
    <> concat
      [ case breakItem p i of
          Just (Penalty _ _ (SoftHyphen _)) ->
            [Breach L9 i ("line " <> show (i + 1) <> " breaks at a soft hyphen but does not end with the width of a hyphen") | lastItemWidth line /= Just hyphen]
              <> [Breach L9 i ("line " <> show (i + 1) <> " breaks at a soft hyphen after " <> show before0 <> ", not a letter") | not (endsWithLetter before0)]
              <> [Breach L9 (i + 1) ("line " <> show (i + 2) <> " starts at a soft hyphen with " <> show after0 <> ", not a letter") | not (maybe False (isLetter . fst) (T.uncons after0))]
            where
              (before0, after0) = maybe ("", "") (elementAround (pItems p)) (breakIndex p i)
          _ -> []
      | (i, line, _) <- pairs p
      ]
    <> concat
      [ case breakItem p i of
          Just (Penalty w _ (PatternHyphen _)) ->
            [Breach L9 i ("line " <> show (i + 1) <> " breaks at a hyphen of the patterns in the first pass") | brPass (pBreaks p) == 1]
              <> [Breach L9 i ("line " <> show (i + 1) <> " breaks at a hyphen of the patterns in a span of " <> show l) | Just c <- [lastBox line], Just l <- [lkLang (bcLook c)], spanIsJapanese l]
              <> [Breach L9 i ("line " <> show (i + 1) <> " does not end with the width of a hyphen") | lastItemWidth line /= Just hyphen || w /= hyphen]
              <> [Breach L9 i ("line " <> show (i + 1) <> " breaks after " <> show before <> ", fewer than " <> show leftMin <> " letters of its element") | T.length before < leftMin]
              <> [Breach L9 (i + 1) ("line " <> show (i + 2) <> " starts with " <> show after <> ", fewer than " <> show rightMin <> " letters of its element") | T.length after < rightMin]
            where
              (before0, after0) = maybe ("", "") (elementAround (pItems p)) (breakIndex p i)
              -- the letters kept before and after a break are those of the language of the word (docs/adr ADR 0276)
              (leftMin, rightMin) = maybe (2, 3) hyphenMins (patternsFor (lastBox line >>= lkLang . bcLook))
              -- the letters the patterns see (docs/adr/0222, D4)
              before = T.filter isLetter before0
              after = T.filter isLetter after0
          Just (Penalty _ _ ExplicitHyphen) ->
            [ Breach L9 i ("line " <> show (i + 1) <> " breaks after a written hyphen but ends with " <> show (textOf line))
            | not (maybe False (maybe False ((`elem` ("-‐–—" :: String)) . snd) . T.unsnoc . bcText) (lastBox line))
            ]
              <> [Breach L9 i ("line " <> show (i + 1) <> " adds a hyphen after a written one") | any isPenalty (take 1 (reverse (lineItems line)))]
          _ -> []
      | (i, line, _) <- pairs p
      ]
  where
    hyphen = L.zwToSp (pSize p) (pAdvance p True '-')
    lastItemWidth l = case reverse (lineItems l) of
      Penalty w _ _ : _ -> Just w
      _ -> Nothing
    isPenalty = \case
      Penalty {} -> True
      _ -> False
    softs = [(w, pen) | Penalty w pen (SoftHyphen _) <- pItems p]
    wanted = softHyphenBreaks (pText p)
    endsWithLetter t = maybe False isLetter (T.find (not . isExtending) (T.reverse t))

{- | The runs of soft hyphens of a text between two Latin letters (docs/adr
ADR 0272): where the paragraphs of the enumeration break at one.
-}
softHyphenBreaks :: Text -> Int
softHyphenBreaks t = length [() | (a, run, b) <- runs (T.unpack t), not (null run), latinLetter a, latinLetter b]
  where
    runs = \case
      a : rest
        | a /= shy ->
            let (r, rest') = span (== shy) rest
             in case rest' of
                  b : _ -> (a, r, b) : runs rest'
                  [] -> []
      _ : rest -> runs rest
      [] -> []
    latinLetter c = isLetter c && charClassOf c == Western
    charClassOf = lookClass bcLookPlain
    bcLookPlain = plainLook "body" 0

{- | The characters of the element of a word on either side of a break,
by the index of the break in the items: the boxes of Latin text before
(after) it, through the other hyphens of the patterns, up to a break
after a written hyphen, a space or anything else.
-}
elementAround :: [Item] -> Int -> (Text, Text)
elementAround its b = (T.concat (reverse (go (reverse (take b its)))), T.concat (go (drop (b + 1) its)))
  where
    go = \case
      Penalty _ _ (PatternHyphen _) : rest -> go rest
      Penalty _ _ (SoftHyphen _) : rest -> go rest
      Box _ c : rest | bcExpandable c -> bcText c : go rest
      _ -> []

{- | L10: no line after the first starts with the glue of a space between
Latin words, and no line ends with one: the space a line breaks at
counts in neither line.
-}
l10Spaces :: Check
l10Spaces _ p =
  [ Breach L10 i ("line " <> show (i + 1) <> " " <> where_ <> " with a space")
  | (i, l) <- zip [0 :: Int ..] (linesOf p),
    (where_, edge) <- [("starts", take 1 (lineItems l)) | i > 0] <> [("ends", take 1 (reverse (lineItems l)))],
    latinSpace p `elem` edge
  ]

{- | L11: where a Japanese character (kana, an ideograph) and a Latin word
are next to each other in a line, there is exactly one glue between them,
the space between Japanese and Latin text of the default aki set; none
beside a character of both scripts in a Latin span. With a space written
between them, the glue of the space is the only glue between them, and
the space between Japanese and Latin text is not added (docs/adr/0222,
D2). No line starts or ends with the space between Japanese and Latin
text.
-}
l11Aki :: Check
l11Aki _ p =
  concat
    [ [ Breach L11 i ("line " <> show (i + 1) <> ": " <> show (bcText a <> bcText b) <> " has " <> show between <> " between them, not " <> show want)
      | -- a line without a Latin word has no pair to judge
        any bcExpandable (boxes l),
        (a, glues, b) <- neighbours (lineItems l),
        -- with a space written between them, the space alone (docs/adr/0222, D2)
        let spaced = latinSpace p `elem` glues
            between = if spaced then glues else filter (`elem` akiGlues) glues,
        Just want <- [if spaced then [latinSpace p] <$ expected a b else expected a b],
        between /= want
      ]
        <> [Breach L11 i ("line " <> show (i + 1) <> " starts or ends with the space between Japanese and Latin text") | any (`elem` akiGlues) (take 1 (lineItems l) <> take 1 (reverse (lineItems l)))]
    | (i, l) <- zip [0 :: Int ..] (linesOf p)
    ]
  where
    aki = akiBetween defaultAkiSet (AkiChar Ideograph) (AkiChar Western)
    akiGlue a = let z = L.zwToSp (pSize p) in Glue (z (A.akiOptimum a)) (z (A.akiMaximum a) - z (A.akiOptimum a)) (z (A.akiOptimum a) - z (A.akiMinimum a))
    akiGlues = [akiGlue aki | aki /= noAki]
    japanese c = not (bcExpandable c) && all (`elem` [Kana, Ideograph]) (catMaybes [startClass c, endClass c])
    -- what is between two boxes next to each other: the glue, when the pair is of a Japanese character and a Latin word
    expected a b
      | japanese a && bcExpandable b = Just (if maybe False (latinDual b . fst) (T.uncons (baseOf b)) then [] else akiGlues)
      | bcExpandable a && japanese b = Just (if maybe False (latinDual a . snd) (T.unsnoc (baseOf a)) then [] else akiGlues)
      | otherwise = Nothing
    neighbours its = case its of
      Box _ a : rest ->
        let (mid, after) = break isBoxItem rest
         in case after of
              Box _ b : _ -> (a, [g | g@(Glue {}) <- mid], b) : neighbours after
              _ -> []
      _ : rest -> neighbours rest
      [] -> []
    isBoxItem = \case
      Box {} -> True
      _ -> False

{- | L12: the expansion of a line is a multiple of 5 from −20 to 20, and 0
without glyph expansion or in a line without a box that takes it.
-}
l12Expansion :: Check
l12Expansion _ p =
  [ Breach L12 i ("line " <> show (i + 1) <> " is expanded by " <> show e)
  | (i, l) <- zip [0 :: Int ..] (linesOf p),
    let e = lineExpansion l,
    e < -20 || e > 20 || e `mod` 5 /= 0 || (e /= 0 && (isNothing (pExpansion (pParams p)) || not (any bcExpandable (boxes l))))
  ]

{- | L13: without protrusion, no line protrudes; with it, a line protrudes
at its start by the amount of its first box, at its end by that of its
last box, or of the hyphen where it breaks at a hyphen of the patterns,
and by no more than the advance of that character: the advance of the
character alone, as golem-layout ADR 0014 takes it ('ceAdvance'), and
for a box of a Latin word that of the character alone in the font of the
word ('ceWordCharAdvance', docs/adr/0222, D3), Latin text in the advances
of the tests.
-}
l13Protrusion :: Check
l13Protrusion _ p =
  concat
    [ if not (pProtrusion (pParams p))
        then [Breach L13 i ("line " <> show (i + 1) <> " protrudes by " <> show (lineProtrusion l) <> " without protrusion") | lineProtrusion l /= (0, 0)]
        else
          [Breach L13 i ("line " <> show (i + 1) <> " protrudes at its start by " <> show s <> ", not " <> show wantS) | s /= wantS]
            <> [Breach L13 i ("line " <> show (i + 1) <> " protrudes at its end by " <> show e <> ", not " <> show wantE) | e /= wantE]
            <> [Breach L13 i ("line " <> show (i + 1) <> " protrudes by more than the advance of its character") | s > capS || e > capE]
    | (i, l) <- zip [0 :: Int ..] (linesOf p),
      let (s, e) = lineProtrusion l
          hyphenEnd = case breakItem p i of
            Just (Penalty _ _ (PatternHyphen q)) | i < length (linesOf p) - 1 -> Just q
            -- a soft hyphen protrudes as one of the patterns (docs/adr ADR 0272)
            Just (Penalty _ _ (SoftHyphen q)) | i < length (linesOf p) - 1 -> Just q
            _ -> Nothing
          wantS = maybe 0 bcProtrudeStart (firstBox l)
          wantE = fromMaybe (maybe 0 bcProtrudeEnd (lastBox l)) hyphenEnd
          -- the advance of the character, as the composition reads it for the protrusion (golem-layout ADR 0014)
          adv c ch = L.zwToSp (pSize p) (pAdvance p (bcExpandable c || lookClass (bcLook c) ch == Western) ch)
          capS = maybe 0 (\c -> maybe 0 (adv c . fst) (T.uncons (baseOf c))) (firstBox l)
          capE = case hyphenEnd of
            Just _ -> L.zwToSp (pSize p) (pAdvance p True '-')
            Nothing -> maybe 0 (\c -> maybe 0 (adv c . snd) (T.unsnoc (baseOf c))) (lastBox l)
    ]

{- | T1 (golem-layout ADR 0032): the last line, and a line that ends at a
forced break, holds a box, but where no box comes since the start of the
paragraph or the forced break before it.
-}
t1LastLineBoxes :: Check
t1LastLineBoxes _ p =
  [ Breach T1 i ("line " <> show (i + 1) <> " ends the paragraph or a forced break and holds no box")
  | (i, l) <- zip [0 :: Int ..] ls,
    i == length ls - 1 || forced i,
    null (boxes l),
    any isBox (take (end i - start i) (drop (start i) (pItems p)))
  ]
  where
    ls = linesOf p
    forced i = case breakItem p i of
      Just (Penalty _ q _) -> q <= negate infPenalty && i < length ls - 1
      _ -> False
    -- the items since the forced break before a line, and up to its end
    end i = maybe (length (pItems p)) (+ 1) (breakIndex p i)
    start i = case [b + 1 | j <- [0 .. i - 1], forced j, Just b <- [breakIndex p j]] of
      [] -> 0
      bs -> last bs
    isBox = \case
      Box {} -> True
      _ -> False

{- | I4 of docs/adr ADR 0272: an element of a word with a soft hyphen has
no hyphen of the patterns. The elements are read from the items: the
boxes of Latin text joined by the hyphens of the patterns and the soft
hyphens; a soft hyphen of the paragraph is in one where it is before one
of its characters, or right after its last when nothing written follows
(a soft hyphen right after a written hyphen is in the element after it).
-}
i4NoHyphensWithShy :: Check
i4NoHyphensWithShy _ p =
  [ Breach I4 (-1) ("the element " <> show (T.concat [t | (_, _, t) <- el]) <> " has a soft hyphen and a hyphen of the patterns")
  | (el, True, explicitAfter) <- elements,
    let (_, e0, _) = last el,
    (s0, _, _) : _ <- [el],
    any (\q -> (q >= s0 && q < e0) || (q == e0 && not explicitAfter)) shyAt
  ]
  where
    stripped = T.filter (/= shy) (pText p)
    shyAt = [n | (n, c) <- snd (mapAccumL (\n c -> if c == shy then (n, (n, c)) else (n + 1, (n, c))) 0 (T.unpack (pText p))), c == shy]
    -- each box with where its characters are in the text without soft hyphens; spaces are in no box
    placed = snd (mapAccumL place 0 (pItems p))
    place pos = \case
      Box _ c
        | not (T.null (bcText c)) ->
            let start = pos + T.length (T.takeWhile (== ' ') (T.drop pos stripped))
             in (start + T.length (bcText c), Just (start, start + T.length (bcText c), c))
      _ -> (pos, Nothing)
    -- the elements: their boxes, whether a hyphen of the patterns is between two of them, whether a written hyphen's break follows
    elements = go [] False (zip (pItems p) placed)
    go cur hy = \case
      (Box _ c, Just (a, b, _)) : rest
        | bcExpandable c -> case cur of
            [] -> go [(a, b, bcText c)] False rest
            _ | joined cur -> go (cur <> [(a, b, bcText c)]) hy rest
            _ -> close cur hy False <> go [(a, b, bcText c)] False rest
      (Penalty _ _ (PatternHyphen _), _) : rest | not (null cur) -> go (cur <> [joint]) True rest
      (Penalty _ _ (SoftHyphen _), _) : rest | not (null cur) -> go (cur <> [joint]) hy rest
      (Penalty _ _ ExplicitHyphen, _) : rest -> close cur hy True <> go [] False rest
      _ : rest -> close cur hy False <> go [] False rest
      [] -> close cur hy False
    -- a marker that the next box is of the same element
    joint = (-1, -1, "")
    joined cur = case reverse cur of
      (-1, -1, _) : _ -> True
      _ -> False
    close cur hy ex = [([x | x@(a, _, _) <- cur, a >= 0], hy, ex) | any (\(a, _, _) -> a >= 0) cur]

-- * the unbreakable pairs of JLReq (golem-layout ADR 0049)

{- | The invariant of the pair of a last and a first character that may
not be broken, vertical or not: B2 two Arabic digits (horizontal only),
B3 a prefixed abbreviation and a numeral, B4 a numeral and a postfixed
abbreviation.
-}
pairKind :: Bool -> Char -> Char -> Maybe LineInvariant
pairKind vertical a b
  | not vertical && refArabicDigit a && refArabicDigit b = Just B2
  | refPrefixed a && refNumeral b = Just B3
  | refNumeral a && refPostfixed b = Just B4
  | otherwise = Nothing

-- | Whether the pair of a last and a first character may not be broken (B2 to B4), vertical or not.
pairForbidden :: Bool -> Char -> Char -> Bool
pairForbidden vertical a b = isJust (pairKind vertical a b)

{- | The pairs of boxes next to each other (golem-layout ADR 0049, its
「不変条件」), by the indices of the two boxes among the items, with the
last character of the first and the first of the second: boxes of text
whose characters follow one another in the text of the paragraph, no
space between them, and no box between them among the items; not two
boxes of code or of a URL, nor a box of ruby.
-}
adjacentPairs :: Text -> [Item] -> [(Int, Int, Char, Char)]
adjacentPairs text its =
  [ (i1, i2, a, b)
  | ((i1, _, e1, c1), (i2, s2, _, c2)) <- zip placed (drop 1 placed),
    e1 == s2,
    not (any isBox (take (i2 - i1 - 1) (drop (i1 + 1) its))),
    not (codeOrUrl c1 && codeOrUrl c2),
    Just a <- [lastOf c1],
    Just b <- [firstOf c2]
  ]
  where
    stripped = T.filter (/= '\xAD') text
    -- the boxes of text, by the index of the item, with where their characters start and end in the text
    placed = go 0 (zip [0 :: Int ..] its)
      where
        go pos = \case
          (i, Box _ c) : rest
            | not (T.null (bcText c)) ->
                let start = pos + T.length (T.takeWhile (== ' ') (T.drop pos stripped))
                    end = start + T.length (bcText c)
                 in (i, start, end, c) : go end rest
          _ : rest -> go pos rest
          [] -> []
    isBox = \case
      Box {} -> True
      _ -> False
    codeOrUrl c = lkCode (bcLook c) || lkUrl (bcLook c)
    isRuby c = boxKind c `elem` [KindRuby, KindGroupRuby]
    lastOf c = if isRuby c then Nothing else snd <$> T.unsnoc (baseText (bcText c))
    firstOf c = if isRuby c then Nothing else fst <$> T.uncons (baseText (bcText c))
    -- the text without the combining characters at its end, unless nothing else is left (baseText of Golem.Layout.Japanese)
    baseText t = case T.dropWhileEnd isExtending t of
      x | T.null x -> t
      x -> x

{- | The items as golem-layout ADR 0049 allows them to differ from those
before it (B6): between the boxes of each pair of 'adjacentPairs' that
may not be broken, every penalty under the infinite one made infinite,
and an infinite penalty put before a glue that the first box comes right
before.
-}
forbidPairs :: Bool -> Text -> [Item] -> [Item]
forbidPairs vertical = penalizePairs (\a b -> if pairForbidden vertical a b then Just infPenalty else Nothing)

{- | The items with the penalty given to the pairs of 'adjacentPairs' it
gives one: between their boxes, every penalty under the infinite one made
that penalty, and that penalty put before a glue that the first box comes
right before, so that the glue is no break (golem-layout ADR 0049, B6;
docs/adr/0275, W2 and W3). A pair whose break was infinite stays so.
-}
penalizePairs :: (Char -> Char -> Maybe Int) -> Text -> [Item] -> [Item]
penalizePairs penaltyOf text its = concat (zipWith change [0 ..] its)
  where
    kept = [(i1, i2, n) | (i1, i2, a, b) <- adjacentPairs text its, Just n <- [penaltyOf a b]]
    change k it = case [(i1, n) | (i1, i2, n) <- kept, k > i1, k < i2] of
      (i1, n) : _ -> case it of
        Penalty w p h | p < infPenalty -> [Penalty w n h]
        Glue {} | k == i1 + 1 -> [Penalty 0 n NoHyphen, it]
        _ -> [it]
      [] -> [it]

{- | B2 to B4 (golem-layout ADR 0049), in horizontal writing: no break
between the boxes of a pair of 'adjacentPairs' that may not be broken,
neither a penalty under the infinite one nor a glue the first box comes
right before.
-}
b2to4Pairs :: Check
b2to4Pairs _ p =
  [ Breach k (-1) ("a break between " <> show a <> " and " <> show b)
  | (i1, i2, a, b) <- adjacentPairs (pText p) (pItems p),
    any (candidateAt i1) [i1 + 1 .. i2 - 1],
    Just k <- [pairKind False a b]
  ]
  where
    its = pItems p
    candidateAt i1 k = case its !! k of
      Penalty _ n _ -> n < infPenalty
      Glue {} -> k == i1 + 1
      Box {} -> False

-- ** the characters of the pairs (golem-layout ADR 0049, its section 2), as the ADR lists them

-- | The Arabic digits: U+0030 to U+0039 and U+FF10 to U+FF19.
refArabicDigit :: Char -> Bool
refArabicDigit c = isDigit c || (c >= '\xFF10' && c <= '\xFF19')

-- | The numerals: the Arabic digits and the kanji numerals.
refNumeral :: Char -> Bool
refNumeral c = refArabicDigit c || c `elem` ("〇一二三四五六七八九十百千万億兆" :: String)

-- | The prefixed abbreviations of JLReq (cl-12) and their full-width forms.
refPrefixed :: Char -> Bool
refPrefixed c = c `elem` map chr [0x00A5, 0x0024, 0x00A3, 0x0023, 0x20AC, 0x2116, 0xFFE5, 0xFF04, 0xFFE1, 0xFF03]

-- | The postfixed abbreviations of JLReq (cl-13) and their full-width forms.
refPostfixed :: Char -> Bool
refPostfixed c =
  c
    `elem` map
      chr
      [ 0x00B0,
        0x2032,
        0x2033,
        0x2103,
        0x00A2,
        0x0025,
        0x2030,
        0x33CB,
        0x2113,
        0x3303,
        0x330D,
        0x3314,
        0x3318,
        0x3322,
        0x3323,
        0x3326,
        0x3327,
        0x332B,
        0x3336,
        0x333B,
        0x3349,
        0x334A,
        0x334D,
        0x3351,
        0x3357,
        0x338E,
        0x338F,
        0x339C,
        0x339D,
        0x339E,
        0x33A1,
        0x33C4,
        0xFF05,
        0xFFE0
      ]

-- * numbers and their units (docs/adr/0275)

-- | Whether the pair of a last and a first character is a number and its unit: an Arabic digit, and a kana or a kanji.
numberUnitOf :: Char -> Char -> Maybe ()
numberUnitOf a b
  | refArabicDigit a && charClass b `elem` [Kana, Ideograph] = Just ()
  | otherwise = Nothing

{- | W1 and W2 of docs/adr/0275, in horizontal writing: between the boxes of
a number and its unit that golem-layout ADR 0049 does not keep together,
no break when the penalty is 10000; otherwise one break, a penalty of the
penalty, of no width and no hyphen, and no glue the first box comes right
before.
-}
w1w2NumberUnit :: Check
w1w2NumberUnit _ p =
  [ Breach (if pNumberUnit p >= infPenalty then W1 else W2) (-1) ("the breaks between " <> show a <> " and " <> show b <> " are " <> show cs)
  | (i1, i2, a, b) <- adjacentPairs (pText p) (pItems p),
    isJust (numberUnitOf a b),
    not (pairForbidden False a b),
    let mid = take (i2 - i1 - 1) (drop (i1 + 1) (pItems p))
        cs = [it | (k, it) <- zip [i1 + 1 ..] mid, candidate i1 k it],
    if pNumberUnit p >= infPenalty then not (null cs) else cs /= [Penalty 0 (pNumberUnit p) NoHyphen]
  ]
  where
    candidate i1 k = \case
      Penalty _ n _ -> n < infPenalty
      Glue {} -> k == i1 + 1
      Box {} -> False

{- | The items as they were before docs/adr/0275, vertical or not: between
the boxes of a number and its unit that golem-layout ADR 0049 does not keep
together, the penalty the ADR put before the glue taken out, and the
penalty in place of a break of 0 made 0 again. The tests of golem-layout
ADR 0049 and docs/adr/0274 compare these with what they recorded before
docs/adr/0275.
-}
withoutNumberUnits :: Bool -> Text -> [Item] -> [Item]
withoutNumberUnits vertical text its = concat (zipWith change [0 ..] its)
  where
    pairsAt = [(i1, i2) | (i1, i2, a, b) <- adjacentPairs text its, isJust (numberUnitOf a b), not (pairForbidden vertical a b)]
    change k it = case [i1 | (i1, i2) <- pairsAt, k > i1, k < i2] of
      i1 : _ -> case (it, drop (k + 1) its) of
        (Penalty _ _ NoHyphen, Glue {} : _) | k == i1 + 1 -> []
        (Penalty w _ NoHyphen, _) -> [Penalty w 0 NoHyphen]
        _ -> [it]
      [] -> [it]

-- | Every invariant, with its check.
lineInvariants :: [(LineInvariant, Check)]
lineInvariants =
  [ (L1, l1AllOnce),
    (L2, l2LineStart),
    (L3, l3LineEnd),
    (L4, l4Inseparable),
    (L5, l5Width),
    (L6, l6Justified),
    (L7, l7Optimal),
    (L8, l8InsideWords),
    (L9, l9Hyphens),
    (L10, l10Spaces),
    (L11, l11Aki),
    (L12, l12Expansion),
    (L13, l13Protrusion),
    (T1, t1LastLineBoxes),
    (I4, i4NoHyphensWithShy),
    -- B3 and B4 of golem-layout ADR 0049 too
    (B2, b2to4Pairs),
    (W1, w1w2NumberUnit),
    (R5, r5Limit),
    (R6, r6Capped)
  ]

-- | The breaches of a paragraph, L7 brute-forcing up to the number of breaks given.
breaches :: Int -> Paragraph -> [Breach]
breaches limit p = concat [check limit p | (_, check) <- lineInvariants]

-- * the invariants of inline code (golem-layout ADR 0034)

{- | Two boxes of code next to each other in the items, by the index of
the first, with the items between them: no space of code between them
(a glue), which the invariants of code do not judge.
-}
codePairs :: [Item] -> [(Int, BoxContent, [(Int, Item)], BoxContent)]
codePairs its = go (zip [0 ..] its)
  where
    go = \case
      (i, Box _ a) : rest
        | isCode a ->
            let (mid, after) = break (isBox . snd) rest
             in case after of
                  (_, Box _ b) : _ | isCode b, not (any (isGlue . snd) mid) -> (i, a, mid, b) : go after
                  _ -> go after
      _ : rest -> go rest
      [] -> []
    isBox = \case
      Box {} -> True
      _ -> False
    isGlue = \case
      Glue {} -> True
      _ -> False

isCode :: BoxContent -> Bool
isCode c = lkCode (bcLook c) && not (lkUrl (bcLook c))

-- | Whether a character of a box of code is Japanese: its class in the look of the box is not Latin.
japaneseIn :: BoxContent -> Char -> Bool
japaneseIn c ch = lookClass (bcLook c) ch /= Western

-- | The base characters of a box: its characters without the combining ones.
basesOf :: BoxContent -> String
basesOf = T.unpack . baseOf

-- | The breaks among the items between two boxes: the penalties less than infinite.
candidates :: [(Int, Item)] -> [(Int, Item)]
candidates mid = [(j, it) | (j, it@(Penalty _ p _)) <- mid, p < infPenalty]

-- | Whether a prohibition applies between the last character of a box and the first of the next.
prohibited :: Paragraph -> BoxContent -> BoxContent -> Bool
prohibited p a b =
  let pk = endClass a
      ck = startClass b
   in maybe False (lineStartProhibited (pStrict p)) ck
        || maybe False lineEndProhibited pk
        || (pk == Just Inseparable && ck == Just Inseparable)

-- | The last and the first characters of two boxes, and whether either is Japanese.
borderOf :: BoxContent -> BoxContent -> Maybe (Char, Char, Bool)
borderOf a b = case (reverse (basesOf a), basesOf b) of
  (x : _, y : _) -> Just (x, y, japaneseIn a x || japaneseIn b y)
  _ -> Nothing

{- | C1: between two characters of code next to each other, neither a
space, one of them Japanese, there is exactly one break, but where a
prohibition applies, where there is none; a box of code holds no two
characters one of which is Japanese.
-}
c1Japanese :: Check
c1Japanese _ p =
  [ Breach C1 (-1) (show (bcText a <> bcText b) <> " has " <> show (length cs) <> " breaks between them" <> (if pro then ", where a prohibition applies" else ""))
  | (_, a, mid, b) <- codePairs (pItems p),
    let cs = candidates mid
        pro = prohibited p a b,
    if pro then not (null cs) else length cs /= 1,
    Just (_, _, True) <- [borderOf a b]
  ]
    <> [ Breach C1 (-1) ("the box of code " <> show (bcText c) <> " holds a Japanese character and another")
       | Box _ c <- pItems p,
         isCode c,
         let bs = basesOf c,
         length bs > 1,
         any (japaneseIn c) bs
       ]

-- | C2: the break of C1 is of 100 after a low line and of 0 otherwise.
c2Penalty :: Check
c2Penalty _ p =
  [ Breach C2 (-1) ("the break between " <> show (bcText a) <> " and " <> show (bcText b) <> " is of " <> show n)
  | (_, a, mid, b) <- codePairs (pItems p),
    Just (x, _, True) <- [borderOf a b],
    (_, Penalty _ n _) <- candidates mid,
    n /= (if x == '_' then 100 else 0)
  ]

-- | C6: no break between two boxes of code draws a hyphen.
c6NoHyphen :: Check
c6NoHyphen _ p =
  [ Breach C6 (-1) ("the break between " <> show (bcText a) <> " and " <> show (bcText b) <> " draws a hyphen")
  | (_, a, mid, b) <- codePairs (pItems p),
    (_, Penalty _ _ h) <- candidates mid,
    case h of
      PatternHyphen _ -> True
      ExplicitHyphen -> True
      SoftHyphen _ -> True
      _ -> False
  ]

{- | C7: the box of a Japanese character of code is as wide as its
advance and its padding (no tracking in the runs; the padding of
golem-layout ADR 0048 in those that have it); there is no glue
between two boxes of code but a space of code, which neither stretches
nor shrinks.
-}
c7Widths :: Check
c7Widths _ p =
  [ Breach C7 (-1) ("the box of code " <> show (bcText c) <> " is " <> show w <> " wide, not " <> show want)
  | Box w c <- pItems p,
    isCode c,
    any (japaneseIn c) (basesOf c),
    let want = L.zwToSp (pSize p) (sum [pAdvance p (not (japaneseIn c ch)) ch | ch <- T.unpack (bcText c)]) + bcPadStart c + bcPadEnd c,
    w /= want
  ]
    <> [ Breach C7 (-1) ("glue that stretches or shrinks inside code, after " <> show (bcText a))
       | (Box _ a, Glue _ y z, Box _ b) <- zip3 (pItems p) (drop 1 (pItems p)) (drop 2 (pItems p)),
         isCode a && isCode b,
         y /= 0 || z /= 0
       ]

{- | C8: a line broken at a break of code other than a space ends with the
wrap mark, once: the penalty it breaks at, as wide as the mark in the look
of the box before it (3/5 of its size, golem-layout ADR 0042). No other line ends with a mark.
-}
c8WrapMark :: Text -> Check
c8WrapMark m _ p =
  [ Breach C8 i ("line " <> show (i + 1) <> " " <> show (textOf l) <> (if atCode then " breaks inside code but does not end with the mark" else " ends with a mark but does not break inside code"))
  | (i, l, _) <- pairs p,
    let atCode = maybe False (`elem` codeBreaks) (breakIndex p i)
        marked = case reverse (lineItems l) of
          Penalty w _ (WrapMark m') : _ -> m' == m && Just w == (markWidthAfter p m <$> lastBox l)
          _ -> False
        anyMark = case reverse (lineItems l) of
          Penalty _ _ (WrapMark _) : _ -> True
          _ -> False,
    if atCode then not marked else anyMark
  ]
  where
    codeBreaks = [j | (_, _, mid, _) <- codePairs (pItems p), (j, _) <- candidates mid]

{- | The width of the wrap mark given after a box of code: the default mark
is a shape 3/5 of the size wide; another is its text at 3/5 of the size
(golem-layout ADR 0042, W3).
-}
markWidthAfter :: Paragraph -> Text -> BoxContent -> Sp
markWidthAfter p m c
  | m == "\x23CE" = markSize
  | otherwise = L.zwToSp markSize (sum [pAdvance p (lookClass (bcLook c) ch == Western) ch | ch <- T.unpack m])
  where
    markSize = Sp ((unSp (pSize p) * 3) `div` 5)

-- * the invariants of the breaks of code after hyphen-minus signs and full stops (golem-layout ADR 0045)

-- | The characters of the runs of golem-layout ADR 0045: the hyphen-minus sign and the full stop.
isStop :: Char -> Bool
isStop ch = ch == '-' || ch == '.'

{- | The runs of code of the items: the boxes of code next to one another
with no space of code between them, each with the items between it and
the next box of the run (none after the last).
-}
codeRuns :: [Item] -> [[(BoxContent, Maybe [(Int, Item)])]]
codeRuns its = go (zip [0 ..] its)
  where
    go xs = case dropWhile (not . codeBox . snd) xs of
      (_, Box _ a) : rest -> let (run, rest') = follow a rest in run : go rest'
      _ -> []
    follow a rest =
      let (mid, after) = break (isBox . snd) rest
       in case after of
            (_, Box _ b) : more
              | isCode b,
                not (any (isGlue . snd) mid) ->
                  let (run, rest') = follow b more in ((a, Just mid) : run, rest')
            _ -> ([(a, Nothing)], after)
    codeBox = \case
      Box _ c -> isCode c
      _ -> False
    isBox = \case
      Box {} -> True
      _ -> False
    isGlue = \case
      Glue {} -> True
      _ -> False

{- | The places of J1 in the base characters of a run of code, each a
character and whether it is Latin: the indices right after a run of
hyphen-minus signs and full stops with a character p before it and one y
after it, both Latin, neither a slash nor a low line, not both digits.
-}
j1Places :: [(Char, Bool)] -> [Int]
j1Places cs =
  [ k
  | k <- [1 .. length cs - 1],
    let (y, yLatin) = cs !! k
        stops = takeWhile (isStop . fst) (reverse (take k cs))
        s = k - length stops,
    not (null stops),
    not (isStop y),
    s > 0,
    let (x, xLatin) = cs !! (s - 1),
    xLatin && yLatin,
    x `notElem` ("/_" :: String) && y `notElem` ("/_" :: String),
    not (isDigit x && isDigit y)
  ]

{- | Each border between two boxes of a run of code: the box before it,
the items between them, the box after it, the index of the border in the
base characters of the run, and whether it is a place of J1; and the
places of J1 inside a box.
-}
codeBorders :: [(BoxContent, Maybe [(Int, Item)])] -> ([(BoxContent, [(Int, Item)], BoxContent, Int, Bool)], [Int])
codeBorders run =
  let chars = concat [[(ch, not (japaneseIn c ch)) | ch <- basesOf c] | (c, _) <- run]
      ends = drop 1 (scanl (+) 0 [length (basesOf c) | (c, _) <- run])
      places = j1Places chars
      borders = [(a, mid, b, e, e `elem` places) | ((a, Just mid), (b, _), e) <- zip3 run (drop 1 run) ends]
   in (borders, [k | k <- places, k `notElem` [e | (_, _, _, e, _) <- borders]])

-- | The borders of the runs of code of a paragraph, and the places of J1 inside a box.
codeBordersOf :: Paragraph -> ([(BoxContent, [(Int, Item)], BoxContent, Int, Bool)], [Int])
codeBordersOf p = let bs = map codeBorders (codeRuns (pItems p)) in (concatMap fst bs, concatMap snd bs)

-- | The indices of the items of the breaks at the places of J1.
j1Breaks :: Paragraph -> [Int]
j1Breaks p = [j | (_, mid, _, _, True) <- fst (codeBordersOf p), (j, _) <- candidates mid]

-- | J1: at each place of J1 there is exactly one break.
j1Stops :: Check
j1Stops _ p =
  [ Breach J1 (-1) (show (bcText a <> bcText b) <> " has " <> show (length (candidates mid)) <> " breaks between them")
  | (a, mid, b, _, True) <- borders,
    length (candidates mid) /= 1
  ]
    <> [Breach J1 (-1) ("no break at the place " <> show k <> " of J1, inside a box of code") | k <- inside]
  where
    (borders, inside) = codeBordersOf p

{- | J2: the break at a place of J1 is of 100, of the wrap mark given as
wide as the mark after the box before it, or of no width and no hyphen
where the mark is empty.
-}
j2Penalty :: Text -> Check
j2Penalty m _ p =
  [ Breach J2 (-1) ("the break between " <> show (bcText a) <> " and " <> show (bcText b) <> " is " <> show it)
  | (a, mid, b, _, True) <- fst (codeBordersOf p),
    (_, it@(Penalty w n h)) <- candidates mid,
    n /= 100 || (if T.null m then h /= NoHyphen || w /= 0 else h /= WrapMark m || w /= markWidthAfter p m a)
  ]

{- | J3: between two Latin characters of code next to each other, the only
breaks are one after a slash, one after a run of low lines, and one at a
place of J1. It takes the place of C3 of golem-layout ADR 0034.
-}
j3Latin :: Check
j3Latin _ p =
  [ Breach J3 (-1) (show (bcText a <> bcText b) <> " breaks between them")
  | (a, mid, b, _, j1) <- fst (codeBordersOf p),
    let cs = candidates mid,
    Just (x, y, False) <- [borderOf a b],
    length cs > 1 || (not (null cs) && not (x == '/' || (x == '_' && y /= '_') || j1))
  ]

{- | J4: after a run of hyphen-minus signs and full stops, before a
Japanese character, there is at most one break, of 0: that of C1 and C2
of golem-layout ADR 0034.
-}
j4Japanese :: Check
j4Japanese _ p =
  [ Breach J4 (-1) ("the breaks between " <> show (bcText a) <> " and " <> show (bcText b) <> " are " <> show (map snd cs))
  | (a, mid, b, _, _) <- fst (codeBordersOf p),
    Just (x, y, _) <- [borderOf a b],
    isStop x && japaneseIn b y,
    let cs = candidates mid,
    length cs > 1 || any (\case (_, Penalty _ n _) -> n /= 0; _ -> False) cs
  ]

{- | J6: the boxes of code, their characters joined, are the characters of
the code without its spaces; a line broken at a place of J1 ends with the
wrap mark given, once, draws no hyphen, and fits.
-}
j6Characters :: Text -> Check
j6Characters m _ p =
  [ Breach J6 (-1) ("the boxes of code hold " <> show got <> ", not " <> show want)
  | let got = T.concat [bcText c | Box _ c <- pItems p, isCode c]
        want = T.filter (/= ' ') (pCode p),
    got /= want
  ]
    <> [ Breach J6 i ("line " <> show (i + 1) <> " " <> show (textOf l) <> " breaks at a place of J1 but ends with " <> show (take 1 (reverse (lineItems l))) <> ", " <> show (lineOverflow l) <> " too wide")
       | (i, l, _) <- pairs p,
         maybe False (`elem` atJ1) (breakIndex p i),
         let marks = [() | Penalty _ _ (WrapMark _) <- lineItems l]
             ends = case reverse (lineItems l) of
               Penalty _ _ (WrapMark m') : _ -> T.null m || m' == m
               Penalty 0 _ NoHyphen : _ -> T.null m
               _ -> False,
         not ends || length marks > 1 || lineOverflow l /= 0
       ]
  where
    atJ1 = j1Breaks p

{- | J7: with the breaks at the places of J1 made infinite (the breaks
before golem-layout ADR 0045), the pass is no earlier; where both passes
are among the first two, the demerits are no fewer.
-}
j7NoWorse :: Check
j7NoWorse _ p
  | null atJ1 = []
  | otherwise =
      [ Breach J7 (-1) ("pass " <> show (brPass br) <> " and demerits " <> show (brDemerits br) <> ", without the breaks of J1 pass " <> show (brPass before) <> " and demerits " <> show (brDemerits before))
      | brPass br > brPass before || (brPass br <= 2 && brPass before <= 2 && brDemerits br > brDemerits before)
      ]
  where
    atJ1 = j1Breaks p
    br = pBreaks p
    its = [if j `elem` atJ1 then Penalty w infPenalty h else it | (j, it) <- zip [0 ..] (pItems p), let (w, h) = case it of Penalty w' _ h' -> (w', h'); _ -> (0, NoHyphen)]
    before = breakParagraph (pParams p) (const (pWidth p)) its

-- | The invariants of code of golem-layout ADR 0034 and 0045, the wrap mark given, with their checks.
codeInvariants :: Text -> [(LineInvariant, Check)]
codeInvariants m =
  [ (C1, c1Japanese),
    (C2, c2Penalty),
    (C6, c6NoHyphen),
    (C7, c7Widths),
    (C8, c8WrapMark m),
    (J1, j1Stops),
    (J2, j2Penalty m),
    (J3, j3Latin),
    (J4, j4Japanese),
    (J6, j6Characters m),
    (J7, j7NoWorse)
  ]

-- | The breaches of a paragraph of code: those of 'breaches' and of 'codeInvariants'.
codeBreaches :: Text -> Int -> Paragraph -> [Breach]
codeBreaches m limit p = breaches limit p <> concat [check limit p | (_, check) <- codeInvariants m]

{- | D1 to D5 of golem-layout ADR 0048 on the items of a paragraph of one
run of code with the padding given, against the items of the same
paragraph without padding, and whether the run has a space at an end:
the items but the boxes are the same (D5); the first box of code has the
padding before it and the last the padding after it, no other box has any
(D1, D2), and a box is wider by its padding only; without a box of code no
box has padding (D3); a run without a space at its ends breaks D4 with
any of D1 and D2, the padding of such a run being on its first and last
box before golem-layout ADR 0048 too.
-}
paddingBreaches :: Sp -> Bool -> [Item] -> [Item] -> [Breach]
paddingBreaches pad edgeSpace bare padded
  | others bare /= others padded = [Breach D5 (-1) ("the items but the boxes differ: " <> show (others bare) <> " and " <> show (others padded))]
  | length bareBoxes /= length paddedBoxes = [Breach D5 (-1) "the number of boxes differs"]
  | null codeIx = [Breach D3 (-1) ("box " <> show (bcText c) <> " has padding in a run without a box of code") | (_, c) <- paddedBoxes, bcPadStart c /= 0 || bcPadEnd c /= 0]
  | otherwise = ds <> [Breach D4 (-1) "a run of code without a space at its ends is not padded as before" | not edgeSpace, not (null ds)]
  where
    others = filter (\case Box {} -> False; _ -> True)
    bareBoxes = [(w, c) | Box w c <- bare]
    paddedBoxes = [(w, c) | Box w c <- padded]
    codeIx = [i | (i, (_, c)) <- zip [0 :: Int ..] paddedBoxes, isCode c]
    (firstIx, lastIx) = case codeIx of
      i : is -> (i, last (i : is))
      [] -> (-1, -1)
    ds =
      concat
        [ [Breach D1 (-1) ("box " <> show (bcText c) <> " has " <> show (bcPadStart c) <> " before it, not " <> show wantS) | bcPadStart c /= wantS]
            <> [Breach D2 (-1) ("box " <> show (bcText c) <> " has " <> show (bcPadEnd c) <> " after it, not " <> show wantE) | bcPadEnd c /= wantE]
            <> [Breach (if i == firstIx then D1 else D2) (-1) ("box " <> show (bcText c) <> " is " <> show w <> " wide, not " <> show (w0 + wantS + wantE)) | w /= w0 + wantS + wantE]
        | (i, ((w0, _), (w, c))) <- zip [0 ..] (zip bareBoxes paddedBoxes),
          let wantS = if i == firstIx then pad else 0
              wantE = if i == lastIx then pad else 0
        ]
