-- the enumerations are built in the tests that check them, and must not
-- be floated out into values that live as long as the program: those
-- would hold every input checked (docs/adr/0208)
{-# OPTIONS_GHC -fno-full-laziness -fno-cse #-}

{- | The ranges that do not break (docs/adr ADR 0272) on every small input:
a run of parts, each in a range or not, after 'あ' set some times and
before 'い' set none or a line's worth of times, in lines of 2 to 5 em,
tier n holding the runs of n parts. I7 of the ADR is checked on each,
and S1 and S2 of docs/adr/0305, S1 in place of I8 of ADR 0272.

The parts are Japanese characters, Latin words of no, one and two places
where the patterns break them and one with a written hyphen, a space, a
soft hyphen, a mono ruby of two bases, a run of code with a slash and a
forced break. The parts of a range are set in the character style
@no-break@, those around them as they are; a run of parts in a range or
out of one is one inline, so that a word in a range is one piece.
-}
module NoBreakEnum (noBreakTests, noBreakPrDepth) where

import Control.Applicative ((<|>))
import Data.List (mapAccumL, zip4)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.Length qualified as L
import Golem.Syntax (FileId (..), mkSpan, spanStart)
import Golem.TestSupport.Enum
import LineBreakEnum (Setting (..), composeEnv, lineText, placings)
import System.Environment (lookupEnv)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Read (readMaybe)

-- | A part of a run: text, a mono ruby of two bases, code, or a forced break.
data Part = PText !Text | PRuby2 | PCode2 | PBreak
  deriving stock (Eq, Show)

-- | The 13 parts.
nbParts :: [Part]
nbParts = map PText ["漢", "あ", "。", "「", "a", "table", "hyphenation", "lime-tree", " ", "\xAD"] <> [PRuby2, PCode2, PBreak]

-- | A paragraph: the parts with whether each is in a range, 'あ' before them, 'い' after them, and the width in em.
data Input = Input
  { inPre :: !Int,
    inRun :: ![(Part, Bool)],
    inPost :: !Int,
    inWidth :: !Int
  }
  deriving stock (Eq, Show)

-- | The settings of the paragraphs: those of the defaults.
plain :: Setting
plain = Setting True False False Nothing

{- | The composition environment: that of 'composeEnv', the character style
@no-break@ setting 'lkNoBreak', @nb-off@ nothing, and @code@ code. Each
character is at the start of the span of its text and its place in the
text, so that the 'bcAt' of a box names the part of its first character
(docs/adr/0305); the items are the same as without the places.
-}
env :: ComposeEnv
env =
  (composeEnv False plain)
    { ceRestyle = \lk -> \case
        IR.CharStyle _ "no-break" _ -> lk {lkNoBreak = True}
        IR.CharStyle _ "code" _ -> lk {lkCode = True, lkWrapMark = "⏎"}
        _ -> lk,
      ceSourceAt = \s _ k -> spanStart s + k
    }

-- | The characters of a part: a ruby of two bases has two, code three.
partLength :: Part -> Int
partLength = \case
  PText t -> T.length t
  PRuby2 -> 2
  PCode2 -> 3
  PBreak -> 1

{- | Where each part of an input starts, and where the last one ends: the
characters of the input numbered from 0, 'あ' before the parts first.
-}
partStarts :: Input -> [Int]
partStarts i = scanl (+) (inPre i) (map (partLength . fst) (inRun i))

{- | The inlines of an input: each run of parts all in a range or all out
of one in the style given for a range and as they are for the rest,
consecutive text parts one text, each text at the place of its first
character ('partStarts').
-}
inlinesWith :: Text -> Input -> [IR.Inline]
inlinesWith style i =
  [IR.Text (at 0 (inPre i)) (T.replicate (inPre i) "あ") | inPre i > 0]
    <> concatMap group (runs (zip (partStarts i) (inRun i)))
    <> [IR.Text (at (inPre i + sum (map (partLength . fst) (inRun i))) (inPost i)) (T.replicate (inPost i) "い") | inPost i > 0]
  where
    at o n = mkSpan (FileId 0) o (o + n)
    runs = \case
      [] -> []
      (o, (p, b)) : rest -> let (same, rest') = span ((== b) . snd . snd) rest in (b, (o, p) : [(o', p') | (o', (p', _)) <- same]) : runs rest'
    group (inRange, ps) = let xs = inlinesOf ps in if inRange then [IR.CharStyle sp style xs] else xs
    inlinesOf = \case
      [] -> []
      ps@((o, PText _) : _) ->
        let (ts, rest) = span (isText . snd) ps
            t = T.concat [x | (_, PText x) <- ts]
         in IR.Text (at o (T.length t)) t : inlinesOf rest
      (o, PRuby2) : rest -> IR.Ruby (at o 2) () [IR.RubySegment [IR.Text (at o 1) "漢"] (Just "かん"), IR.RubySegment [IR.Text (at (o + 1) 1) "字"] (Just "じ")] : inlinesOf rest
      (o, PCode2) : rest -> IR.CharStyle (at o 3) "code" [IR.Text (at o 3) "a/b"] : inlinesOf rest
      (o, PBreak) : rest -> IR.LineBreak (at o 1) : inlinesOf rest
    isText = \case
      PText _ -> True
      _ -> False

-- | The items of an input, with its ranges and with them all off.
itemsOf :: Input -> ([Item], [Item])
itemsOf i = (fst (composeInlines env (inlinesWith "no-break" i)), fst (composeInlines env (inlinesWith "nb-off" i)))

-- | The width of the lines of an input.
widthOf :: Input -> Sp
widthOf i = fromIntegral (inWidth i) * fs

-- | The characters of a box, nothing for a box of none.
charBox :: Item -> Maybe BoxContent
charBox = \case
  Box _ c | not (T.null (bcText c)) -> Just c
  _ -> Nothing

{- | I7: the nearest character before a break between two lines and the
nearest character after it are both of a range only where the break is a
forced one.
-}
i7Breaks :: Input -> [Item] -> Breaks -> [Violation]
i7Breaks _ its br =
  [ Violation "I7" ("lines " <> show (k + 1) <> " and " <> show (k + 2) <> " break between " <> show (bcText a) <> " and " <> show (bcText b) <> " in a range, at " <> show at)
  | (k, (l, next, pos)) <- zip [0 :: Int ..] (zip3 (brLines br) (drop 1 (brLines br)) (brPositions br)),
    Just a <- [lastChar l],
    Just b <- [firstChar next],
    lkNoBreak (bcLook a) && lkNoBreak (bcLook b),
    let at = if pos >= 0 && pos < length its then Just (its !! pos) else Nothing,
    not (forced at)
  ]
  where
    lastChar l = case reverse (mapMaybe charBox (lineItems l)) of
      c : _ -> Just c
      [] -> Nothing
    firstChar l = case mapMaybe charBox (lineItems l) of
      c : _ -> Just c
      [] -> Nothing
    forced = \case
      Just (Penalty _ p _) -> p <= negate infPenalty
      _ -> False

{- | The characters of an input, by their number ('partStarts'): whether
each is of a range, whether it is a soft hyphen, and the text inline it is
in. Consecutive text parts all in a range or all out of one are one text;
the 'あ' before the parts and the 'い' after them are texts of their own.
-}
data Chars = Chars
  { chInRange :: Int -> Bool,
    chShy :: Int -> Bool,
    chText :: Int -> Int
  }

charsOf :: Input -> Chars
charsOf i =
  Chars
    { chInRange = maybe False (snd . snd) . partAt,
      chShy = maybe False ((== PText "\xAD") . fst . snd) . partAt,
      chText = \o -> maybe (if o < inPre i then -1 else -2) fst (partAt o)
    }
  where
    starts = partStarts i
    -- each part with the number of its text inline
    parts = zip (texts (inRun i)) (inRun i)
    texts = snd . mapAccumL (\(prev, n) (p, b) -> let n' = if isText p && prev == Just b then n else n + 1 in ((if isText p then Just b else Nothing, n'), n')) (Nothing, 0 :: Int)
    isText = \case
      PText _ -> True
      _ -> False
    partAt o = case [x | (x, s, e) <- zip3 parts starts (drop 1 starts), s <= o, o < e] of
      x : _ -> Just x
      [] -> Nothing

{- | The soft hyphens right before the character numbered o, nearest
first, and the character before them; Nothing where the character before
o is not a soft hyphen.
-}
shysBefore :: Chars -> Int -> Maybe ([Int], Int)
shysBefore ch o = case takeWhile (\k -> k >= 0 && chShy ch k) [o - 1, o - 2 ..] of
  [] -> Nothing
  ss -> Just (ss, minimum ss - 1)

{- | Whether soft hyphens touch a range (docs/adr/0305): one of them is of
a range, or the character before them or the character o after them is.
-}
touchesRange :: Chars -> ([Int], Int) -> Int -> Bool
touchesRange ch (ss, before) o = any (chInRange ch) ss || (before >= 0 && chInRange ch before) || chInRange ch o

-- | The number of the first character of the nearest box.
nextBoxAt :: [Item] -> Maybe Int
nextBoxAt = \case
  Box _ c : _ -> Just (bcAt c)
  _ : rest -> nextBoxAt rest
  [] -> Nothing

isShyPenalty :: Item -> Bool
isShyPenalty = \case
  Penalty _ _ (SoftHyphen _) -> True
  _ -> False

{- | The soft hyphens of a soft hyphen penalty, those right before the
first character of the nearest box after it.
-}
shysOf :: Chars -> [Item] -> Either String (([Int], Int), Int)
shysOf ch rest = case nextBoxAt rest of
  Nothing -> Left "a soft hyphen penalty has no box after it"
  Just o -> maybe (Left ("a soft hyphen penalty is not after a soft hyphen: the box after it starts at character " <> show o)) (\s -> Right (s, o)) (shysBefore ch o)

{- | The first step of S1 (docs/adr/0305) on the items of an input with its
ranges off: the penalty of each soft hyphen touching a range taken out,
and where the soft hyphen and the characters around it are of one text,
the boxes around it one box of both texts, as wide as both and the
kerning between them (the advance of the joined text less those of the
two).
-}
dropTouching :: Chars -> [Item] -> Either String [Item]
dropTouching ch = go []
  where
    go acc = \case
      [] -> Right (reverse acc)
      x : rest
        | isShyPenalty x -> do
            (sh@(ss, before), o) <- shysOf ch rest
            if not (touchesRange ch sh o)
              then go (x : acc) rest
              else
                if all ((== chText ch o) . chText ch) (before : ss)
                  then case (acc, rest) of
                    (Box w1 c1 : acc', Box w2 c2 : rest') -> go (Box (joined w1 w2 c1 c2) c1 {bcText = bcText c1 <> bcText c2} : acc') rest'
                    _ -> Left "the boxes around a soft hyphen of one text are not next to its penalty"
                  else go acc rest
        | otherwise -> go (x : acc) rest
    joined w1 w2 c1 c2 =
      let lk = bcLook c1
          adv t = L.zwToSp (lkSize lk) (ceWordAdvance env lk t)
       in w1 + w2 + adv (bcText c1 <> bcText c2) - adv (bcText c1) - adv (bcText c2)

{- | The second step of S1: each break whose nearest characters before and
after it are both of a range taken out, a penalty of 10000 for a penalty,
one before a glue, the widths and the stretch as they were.
-}
holdInside :: Chars -> [Item] -> [Item]
holdInside ch xs =
  concat
    [ case x of
        Penalty w p h | p < infPenalty && p > negate infPenalty && inside -> [Penalty w infPenalty h]
        Glue {} | ab && inside -> [Penalty 0 infPenalty NoHyphen, x]
        _ -> [x]
    | (x, b, a, ab) <- zip4 xs befores afters afterBox,
      let inside = b == Just True && a == Just True
    ]
  where
    -- whether the characters of each box are of a range
    marks = [case x of Box _ c | not (T.null (bcText c)) -> Just (chInRange ch (bcAt c)); _ -> Nothing | x <- xs]
    befores = scanl (flip (<|>)) Nothing marks
    afters = drop 1 (scanr (<|>) Nothing marks)
    afterBox = False : [case x of Box {} -> True; _ -> False | x <- xs]

{- | S1 (docs/adr/0305, in place of I8 of docs/adr ADR 0272): the items of
an input are those of it with its ranges off, 'dropTouching' and then
'holdInside'.
-}
s1Breaks :: Input -> [Item] -> [Item] -> [Violation]
s1Breaks i its off = case dropTouching ch off of
  Left e -> [Violation "S1" ("the predicate cannot read the items: " <> e)]
  Right off' ->
    let want = holdInside ch off'
     in [Violation "S1" ("the items are " <> show (map itemKey its) <> ", not " <> show (map itemKey want)) | map itemKey its /= map itemKey want]
  where
    ch = charsOf i

-- | S2 (docs/adr/0305): no soft hyphen touching a range has a penalty.
s2Breaks :: Input -> [Item] -> [Violation]
s2Breaks i its =
  [ Violation "S2" ("a soft hyphen penalty touches a range: the box after it starts at character " <> show o)
  | x : rest <- tailsOf its,
    isShyPenalty x,
    Right (sh, o) <- [shysOf ch rest],
    touchesRange ch sh o
  ]
  where
    ch = charsOf i
    tailsOf xs = case xs of
      [] -> []
      _ : rest -> xs : tailsOf rest

-- | The values of an item that the predicates compare.
itemKey :: Item -> (Int, Sp, Sp, Sp, Text, Int, Int)
itemKey = \case
  Box w c -> (0, w, 0, 0, bcText c, 0, 0)
  Glue w y z _ _ -> (1, w, y, z, "", 0, 0)
  Penalty w p h -> (2, w, 0, 0, "", p, hyphenKind h)
  where
    hyphenKind = \case
      NoHyphen -> 0
      PatternHyphen _ -> 1
      ExplicitHyphen -> 2
      WrapMark _ -> 3
      SoftHyphen _ -> 4

-- | The violations of an input.
violations :: Input -> [Violation]
violations i =
  let (its, off) = itemsOf i
      br = breakParagraph defaultParams (const (widthOf i)) its
   in i7Breaks i its br <> s1Breaks i its off <> s2Breaks i its

-- | The inputs of a run: every placing of it in lines of 2 to 5 em.
inputsOf :: [(Part, Bool)] -> [Input]
inputsOf run = [Input pre run post w | (pre, post, ws) <- placings 5, w <- ws]

-- | Every input, tier n holding those of the runs of n parts.
inputT :: Tiers Input
inputT = let Tiers xss = listsOf (Tiers [[(p, b) | p <- nbParts, b <- [False, True]]]) in Tiers (map (concatMap inputsOf) xss)

{- | The parts of the runs: GOLEM_ENUM_NOBREAK_DEPTH, or 'noBreakPrDepth' on pull requests;
3 took 10 seconds on 8 processors, more than the budget of docs/adr/0208,
and the nightly job checks it.
-}
depthOf :: IO Int
depthOf =
  lookupEnv "GOLEM_ENUM_NOBREAK_DEPTH" >>= \case
    Nothing -> pure noBreakPrDepth
    Just "" -> pure noBreakPrDepth
    Just s -> case readMaybe s of
      Just n | n >= 0 -> pure n
      _ -> assertFailure ("GOLEM_ENUM_NOBREAK_DEPTH is not a whole number of 0 or more: " <> show s)

-- | The parts of the runs of pull requests.
noBreakPrDepth :: Int
noBreakPrDepth = 2

noBreakTests :: TestTree
noBreakTests =
  testGroup
    "the ranges that do not break on every small input (docs/adr ADR 0272, docs/adr/0305)"
    [ testCase "I7, S1 and S2 hold for every input up to GOLEM_ENUM_NOBREAK_DEPTH parts" $ do
        depth <- depthOf
        case checkAllPar depth inputT violations of
          Failed k i vs -> assertFailure ("the smallest input that breaks I7, S1 or S2 has " <> show k <> " parts: " <> show i <> "\n" <> unlines [violationRule v <> ": " <> violationDetail v | v <- vs])
          Passed _ -> pure (),
      testCase "S1: the smallest input of the nightly run 42777778394, a soft hyphen out of a range next to it, holds" $ do
        let i = Input 0 [(PText "a", False), (PText "\xAD", False), (PText "a", True)] 0 2
            (its, off) = itemsOf i
        s1Breaks i its off @?= []
        s2Breaks i its @?= [],
      testCase "S1: a soft hyphen inside a range holds: the word is one box" $ do
        let i = Input 0 [(PText "a", True), (PText "\xAD", True), (PText "a", True)] 0 2
            (its, off) = itemsOf i
        [bcText c | Box _ c <- its] @?= ["aa"]
        s1Breaks i its off @?= []
        s2Breaks i its @?= [],
      testCase "S1, S2: a predicate test, the soft hyphen penalty put back at the edge of a range is a violation" $ do
        let i = Input 0 [(PText "a", False), (PText "\xAD", False), (PText "a", True)] 0 2
            (its, off) = itemsOf i
            pens = [x | x@(Penalty _ 50 (SoftHyphen _)) <- off]
            putBack = \case
              b1@Box {} : b2@Box {} : rest -> b1 : pens <> (b2 : rest)
              x : rest -> x : putBack rest
              [] -> []
        length pens @?= 1
        map violationRule (s1Breaks i (putBack its) off) @?= ["S1"]
        map violationRule (s2Breaks i (putBack its)) @?= ["S2"],
      testCase "S1, S2: a predicate test, the word of a range cut at its soft hyphen is a violation" $ do
        let i = Input 0 [(PText "a", True), (PText "\xAD", True), (PText "a", True)] 0 2
            (its, off) = itemsOf i
            pw = foldr const 0 [w | Penalty w _ (SoftHyphen _) <- off]
            cut = \case
              Box w c : rest | bcText c == "aa" -> Box (Sp (unSp w `div` 2)) c {bcText = "a"} : Penalty pw infPenalty (SoftHyphen 0) : Box (Sp (unSp w `div` 2)) c {bcText = "a", bcAt = bcAt c + 2} : rest
              x : rest -> x : cut rest
              [] -> []
        map violationRule (s1Breaks i (cut its) off) @?= ["S1"]
        map violationRule (s2Breaks i (cut its)) @?= ["S2"],
      testCase "S1, S2: the soft hyphens before and after the words in and out of a range, on one line and in one inline or two, hold" $ do
        let sides = Nothing : [Just (PText w, b) | w <- ["a", "table", "hyphenation", "lime-tree", "。"], b <- [False, True]]
            inputs = [Input 0 (maybe [] pure pre <> [(PText "\xAD", f)] <> maybe [] pure post) 0 w | pre <- sides, f <- [False, True], post <- sides, w <- [2, 5]]
            bad = [(i, vs) | i <- inputs, let (its, off) = itemsOf i, let vs = s1Breaks i its off <> s2Breaks i its, not (null vs)]
        take 1 bad @?= [],
      testCase "I7: a predicate test, a range broken inside is a violation" $ do
        let i = Input 0 [(PText "あ", True), (PText "漢", True)] 0 1
            (its, _) = itemsOf i
            -- a break allowed between the two characters again: the penalty before the glue between them taken out
            allowed = dropHeld its
            dropHeld = \case
              Box w c : Penalty _ p NoHyphen : g@(Glue _ y _ _ _) : rest | p >= infPenalty, y < filStretch -> Box w c : g : dropHeld rest
              x : rest -> x : dropHeld rest
              [] -> []
            br = breakParagraph defaultParams (const (widthOf i)) allowed
        map lineText (brLines br) @?= ["あ", "漢"]
        map violationRule (i7Breaks i allowed br) @?= ["I7"],
      testCase "I7: a forced break inside a range breaks the line" $ do
        let i = Input 0 [(PText "あ", True), (PBreak, True), (PText "漢", True)] 0 5
            (its, _) = itemsOf i
            br = breakParagraph defaultParams (const (widthOf i)) its
        map lineText (brLines br) @?= ["あ", "漢"]
        i7Breaks i its br @?= [],
      testCase "a range of a line's worth of characters fits; one more is set past the measure, on one line" $ do
        let fits = Input 0 [(PText "漢漢", True)] 0 2
            over = Input 0 [(PText "漢漢漢", True)] 0 2
            linesOf i = let (its, _) = itemsOf i in map lineText (brLines (breakParagraph defaultParams (const (widthOf i)) its))
        linesOf fits @?= ["漢漢"]
        linesOf over @?= ["漢漢漢"],
      testCase "S1: the spaces of a range stretch, unbroken: a word space of a range is a glue with a penalty of 10000 before it" $ do
        let (its, _) = itemsOf (Input 0 [(PText "a table", True)] 0 5)
        [() | Penalty _ p NoHyphen : Glue _ y _ _ _ : _ <- tailsOf its, p >= infPenalty, y > 0, y < filStretch] @?= [()],
      testCase "two ranges next to each other: no break between them" $ do
        let its = fst (composeInlines env [IR.CharStyle sp "no-break" [IR.Text sp "漢"], IR.CharStyle sp "no-break" [IR.Text sp "字"]])
        breaksIn its @?= 0,
      testCase "the edges of a range break as they did: the break between a range and the text after it stays" $ do
        let its = fst (composeInlines env [IR.CharStyle sp "no-break" [IR.Text sp "漢"], IR.Text sp "字"])
        breaksIn its @?= 1
    ]
  where
    -- the breaks but the forced one at the end: a finite penalty, a glue after a box
    breaksIn its = length [() | Penalty _ p _ <- its, p < infPenalty, p > negate infPenalty] + length [() | Box {} : Glue _ y _ _ _ : _ <- tailsOf its, y < filStretch]
    tailsOf xs = case xs of
      [] -> []
      _ : rest -> xs : tailsOf rest
