-- the enumerations are built in the tests that check them, and must not
-- be floated out into values that live as long as the program: those
-- would hold every input checked (docs/adr/0208)
{-# OPTIONS_GHC -fno-full-laziness -fno-cse #-}

{- | The ranges that do not break (docs/adr ADR 0272) on every small input:
a run of parts, each in a range or not, after 'あ' set some times and
before 'い' set none or a line's worth of times, in lines of 2 to 5 em,
tier n holding the runs of n parts. I7 and I8 of the ADR are checked on
each.

The parts are Japanese characters, Latin words of no, one and two places
where the patterns break them and one with a written hyphen, a space, a
soft hyphen, a mono ruby of two bases, a run of code with a slash and a
forced break. The parts of a range are set in the character style
@no-break@, those around them as they are; a run of parts in a range or
out of one is one inline, so that a word in a range is one piece.
-}
module NoBreakEnum (noBreakTests) where

import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
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
@no-break@ setting 'lkNoBreak', @nb-off@ nothing, and @code@ code.
-}
env :: ComposeEnv
env =
  (composeEnv False plain)
    { ceRestyle = \lk -> \case
        IR.CharStyle _ "no-break" _ -> lk {lkNoBreak = True}
        IR.CharStyle _ "code" _ -> lk {lkCode = True, lkWrapMark = "⏎"}
        _ -> lk
    }

{- | The inlines of an input: each run of parts all in a range or all out
of one in the style given for a range and as they are for the rest,
consecutive text parts one text.
-}
inlinesWith :: Text -> Input -> [IR.Inline]
inlinesWith style i =
  [IR.Text sp (T.replicate (inPre i) "あ") | inPre i > 0]
    <> concatMap group (runs (inRun i))
    <> [IR.Text sp (T.replicate (inPost i) "い") | inPost i > 0]
  where
    runs = \case
      [] -> []
      (p, b) : rest -> let (same, rest') = span ((== b) . snd) rest in (b, p : map fst same) : runs rest'
    group (inRange, ps) = let xs = inlinesOf ps in if inRange then [IR.CharStyle sp style xs] else xs
    inlinesOf = \case
      [] -> []
      ps@(PText _ : _) ->
        let (ts, rest) = span isText ps
         in IR.Text sp (T.concat [t | PText t <- ts]) : inlinesOf rest
      PRuby2 : rest -> IR.Ruby sp () [IR.RubySegment [IR.Text sp "漢"] (Just "かん"), IR.RubySegment [IR.Text sp "字"] (Just "じ")] : inlinesOf rest
      PCode2 : rest -> IR.CharStyle sp "code" [IR.Text sp "a/b"] : inlinesOf rest
      PBreak : rest -> IR.LineBreak sp : inlinesOf rest
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

{- | I8: the items of an input are those of it with its ranges off, each
break whose nearest characters before and after it are both of a range
(as the boxes of the input tell) taken out: a penalty of 10000 for a
penalty, one before a glue, the widths and the stretch as they were.
-}
i8OnlyBreaks :: [Item] -> [Item] -> [Violation]
i8OnlyBreaks its off
  | length flags /= length offBoxes = [Violation "I8" ("the input has " <> show (length flags) <> " boxes, with its ranges off " <> show (length offBoxes))]
  | map key its /= map key want = [Violation "I8" ("the items are " <> show (map key its) <> ", not " <> show (map key want))]
  | otherwise = []
  where
    flags = [lkNoBreak (bcLook c) | Box _ c <- its]
    offBoxes = [() | Box {} <- off]
    -- each item of the input with its ranges off, with the flag of the range of its box
    marked = go flags off
      where
        go fl = \case
          Box w c : rest -> case fl of
            f : fl' -> (Box w c, Just (f && not (T.null (bcText c)), not (T.null (bcText c)))) : go fl' rest
            [] -> (Box w c, Nothing) : go [] rest
          x : rest -> (x, Nothing) : go fl rest
          [] -> []
    -- the nearest character of each side: whether it is in a range
    befores = scanl (\acc (_, m) -> case m of Just (f, True) -> Just f; _ -> acc) Nothing marked
    afters = drop 1 (scanr (\(_, m) acc -> case m of Just (f, True) -> Just f; _ -> acc) Nothing marked)
    afterBox = False : [isBox x | (x, _) <- marked]
    isBox = \case
      Box {} -> True
      _ -> False
    want =
      concat
        [ case x of
            Penalty w p h | p < infPenalty && p > negate infPenalty && inside -> [Penalty w infPenalty h]
            Glue {} | ab && inside -> [Penalty 0 infPenalty NoHyphen, x]
            _ -> [x]
        | ((x, _), b, a, ab) <- zip4' marked befores afters afterBox,
          let inside = b == Just True && a == Just True
        ]
    zip4' (w : ws) (x : xs) (y : ys) (z : zs) = (w, x, y, z) : zip4' ws xs ys zs
    zip4' _ _ _ _ = []
    key = \case
      Box w c -> (0 :: Int, w, 0, 0, bcText c, 0 :: Int, 0 :: Int)
      Glue w y z -> (1, w, y, z, "", 0, 0)
      Penalty w p h -> (2, w, 0, 0, "", p, hyphenKind h)
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
   in i7Breaks i its br <> i8OnlyBreaks its off

-- | The inputs of a run: every placing of it in lines of 2 to 5 em.
inputsOf :: [(Part, Bool)] -> [Input]
inputsOf run = [Input pre run post w | (pre, post, ws) <- placings 5, w <- ws]

-- | Every input, tier n holding those of the runs of n parts.
inputT :: Tiers Input
inputT = let Tiers xss = listsOf (Tiers [[(p, b) | p <- nbParts, b <- [False, True]]]) in Tiers (map (concatMap inputsOf) xss)

{- | The parts of the runs: GOLEM_ENUM_NOBREAK_DEPTH, or 2 on pull requests;
3 took 7 seconds on 8 processors, more than the budget of docs/adr/0208,
and the nightly job checks it.
-}
depthOf :: IO Int
depthOf =
  lookupEnv "GOLEM_ENUM_NOBREAK_DEPTH" >>= \case
    Nothing -> pure 2
    Just "" -> pure 2
    Just s -> case readMaybe s of
      Just n | n >= 0 -> pure n
      _ -> assertFailure ("GOLEM_ENUM_NOBREAK_DEPTH is not a whole number of 0 or more: " <> show s)

noBreakTests :: TestTree
noBreakTests =
  testGroup
    "the ranges that do not break on every small input (docs/adr ADR 0272)"
    [ testCase "I7 and I8 hold for every input up to GOLEM_ENUM_NOBREAK_DEPTH parts" $ do
        depth <- depthOf
        case checkAllPar depth inputT violations of
          Failed k i vs -> assertFailure ("the smallest input that breaks I7 or I8 has " <> show k <> " parts: " <> show i <> "\n" <> unlines [violationRule v <> ": " <> violationDetail v | v <- vs])
          Passed _ -> pure (),
      testCase "I7: a predicate test, a range broken inside is a violation" $ do
        let i = Input 0 [(PText "あ", True), (PText "漢", True)] 0 1
            (its, _) = itemsOf i
            -- a break allowed between the two characters again: the penalty before the glue between them taken out
            allowed = dropHeld its
            dropHeld = \case
              Box w c : Penalty _ p NoHyphen : g@(Glue _ y _) : rest | p >= infPenalty, y < filStretch -> Box w c : g : dropHeld rest
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
      testCase "I8: the spaces of a range stretch, unbroken: a word space of a range is a glue with a penalty of 10000 before it" $ do
        let (its, _) = itemsOf (Input 0 [(PText "a table", True)] 0 5)
        [() | Penalty _ p NoHyphen : Glue _ y _ : _ <- tailsOf its, p >= infPenalty, y > 0, y < filStretch] @?= [()],
      testCase "two ranges next to each other: no break between them" $ do
        let its = fst (composeInlines env [IR.CharStyle sp "no-break" [IR.Text sp "漢"], IR.CharStyle sp "no-break" [IR.Text sp "字"]])
        breaksIn its @?= 0,
      testCase "the edges of a range break as they did: the break between a range and the text after it stays" $ do
        let its = fst (composeInlines env [IR.CharStyle sp "no-break" [IR.Text sp "漢"], IR.Text sp "字"])
        breaksIn its @?= 1
    ]
  where
    -- the breaks but the forced one at the end: a finite penalty, a glue after a box
    breaksIn its = length [() | Penalty _ p _ <- its, p < infPenalty, p > negate infPenalty] + length [() | Box {} : Glue _ y _ : _ <- tailsOf its, y < filStretch]
    tailsOf xs = case xs of
      [] -> []
      _ : rest -> xs : tailsOf rest
