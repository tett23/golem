-- the enumerations are built in the tests that check them, and must not
-- be floated out into values that live as long as the program: those
-- would hold every input checked (docs/adr/0208)
{-# OPTIONS_GHC -fno-full-laziness -fno-cse #-}

{- | The invariants of the line breaking checked on every small input
(docs/adr/0209): the enumeration of the paragraphs and its normal form,
the predicates L1 to L13 on outputs made by hand, the naive search of
L7, the regressions, and every input up to @GOLEM_ENUM_LINES_DEPTH@
parts with @GOLEM_ENUM_LINES_SAMPLES@ inputs drawn one part past it,
the known bugs excluded by an explicit list whose inputs are counted.
-}
module LineBreakInvariantsSpec
  ( lineInvariantTests,
    linesPrDepth,
    LineBug (..),
    lineBugs,
    Adjust (..),
    LineSetting,
    lineSettingsAt,
    lineChecksAt,
    lineLimitsAt,
  )
where

import Control.Monad (when)
import Data.Bits (xor)
import Data.ByteString.Lazy qualified as BL
import Data.Char (ord)
import Data.List (intercalate, nub)
import Data.Map.Strict qualified as Map
import Data.Ratio ((%))
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word64)
import Fixtures (fs)
import Golem.Layout.Japanese (ComposeEnv (..), composeInlines)
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.TestSupport.Enum
import KnuthPlassBrute
import LineBreakEnum
import LineBreakInvariants
import Numeric (showHex)
import System.Environment (lookupEnv)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Read (readMaybe)

lineInvariantTests :: TestTree
lineInvariantTests =
  testGroup
    "line breaking invariants on every small input (docs/adr/0209)"
    [ testGroup "the enumeration of the inputs" enumerationTests,
      testGroup "the predicates" predicateTests,
      testGroup "the naive search" bruteTests,
      testGroup "the regressions" regressionTests,
      testGroup "every input" exhaustiveTests,
      testGroup "inline code (golem-layout ADR 0034)" codeTests
    ]

{- | The parts of the runs of pull requests (docs/adr/0209, the decision 8
of the maintainer). The nightly job raises it with GOLEM_ENUM_LINES_DEPTH.
-}
linesPrDepth :: Int
linesPrDepth = 2

{- | The widest line of pull requests, in em: 4, not the 5 of the
enumeration, which made the line breaking tests take more than 10
seconds on the x86-64 runner of CI (docs/adr/0209, its section 5). Past
'linesPrDepth', as the nightly job checks, lines up to 5 em.
-}
linesPrWidth :: Int
linesPrWidth = 4

{- | The parts up to which the normal form and vertical writing are
checked: 2, as docs/adr/0209 asks, past 'linesPrDepth' (the nightly job);
1 on pull requests, where checking every setting the normal form leaves
out up to 2 parts took more than the 10 seconds of the area alone on the
x86-64 runner of CI (docs/adr/0208, its section 4).
-}
formDepth :: Int -> Int
formDepth depth = if depth > linesPrDepth then 2 else 1

-- | The widest line at a depth.
maxWidthAt :: Int -> Int
maxWidthAt depth = if depth > linesPrDepth then 5 else linesPrWidth

{- | The groups of a run the enumeration checks at a depth: those of the
normal form, the span of fr included on pull requests too. docs/adr ADR
0276 moved the span of fr to the nightly job; timed as docs/adr ADR 0286
asks (the test executable alone with -p, the median of four jobs on the
x86-64 runner, run 42761004416), it is back on pull requests with the
area at 5.43 to 5.46 seconds and the sum at 23.37 to 23.47 (docs/adr ADR
0281, its section 7).
-}
groupsAt :: Int -> [Text] -> [Group]
groupsAt depth = normalGroups (maxWidthAt depth)

{- | The parts up to which R1 of docs/adr/0274 is checked: 2, on pull
requests too. docs/adr/0282 kept it to the nightly job; timed as docs/adr
ADR 0286 asks (the median of four jobs, run 42761004416), R1 back on pull
requests after the span of fr keeps the area at 8.53 seconds and the sum
at 26.54 to 26.55 (docs/adr ADR 0281, its section 7).
-}
r1Depth :: Int -> Int
r1Depth _ = 2

{- | A run whose normal form keeps every setting: a prolonged sound mark
(loose kinsoku), a full stop (hanging), a Latin word (protrusion, the
spans and the expansion) and a digit (the penalty of a number and its
unit).
-}
coveringRun :: [Text]
coveringRun = ["ー", "。", "table", "１"]

{- | A setting the enumeration of the line breaking combines an input with
(docs/adr ADR 0281, its section 1): the composition, the expansion, the
width of the lines in em, and the adjustment.
-}
type LineSetting = (Setting, Bool, Int, Adjust)

{- | The settings the enumeration checks at a depth: those of the groups
of 'groupsAt' and the adjustments of 'adjustsAt', on a run whose normal
form keeps every setting.
-}
lineSettingsAt :: Int -> Set LineSetting
lineSettingsAt depth = Set.fromList [(gSetting g, e, w, a) | g <- groupsAt depth coveringRun, (w, e) <- gCases g, a <- adjustsAt depth coveringRun]

{- | The checks of the line breaking at a depth, and the parts each checks
every run up to (0: not checked).
-}
lineChecksAt :: Int -> [(String, Int)]
lineChecksAt depth =
  [ ("L1 to L13, T1, I4, B2 to B4, R2, R5, R6 on every input", depth),
    ("L1 to L13, T1, C1, C2, C4, C6 to C8, J1 to J7, D1 to D5 on every input of code", depth),
    ("R1", r1Depth depth),
    ("R7", formDepth depth),
    ("the normal form", formDepth depth),
    ("the normal form of code", formDepth depth),
    ("vertical writing", formDepth depth),
    ("vertical writing of code", formDepth depth)
  ]

-- | The limits of the line breaking at a depth: the widest line in em, and the breaks L7 brute-forces.
lineLimitsAt :: Int -> [(String, Int)]
lineLimitsAt depth = [("the widest line", maxWidthAt depth), ("the breaks of the naive search", bruteLimitAt depth)]

-- | The depth: GOLEM_ENUM_LINES_DEPTH, or 'linesPrDepth'.
linesDepth :: IO Int
linesDepth = wholeNumber "GOLEM_ENUM_LINES_DEPTH" linesPrDepth

-- | The inputs drawn one part past the depth: GOLEM_ENUM_LINES_SAMPLES, or none.
linesSamples :: IO Int
linesSamples = wholeNumber "GOLEM_ENUM_LINES_SAMPLES" 0

{- | The breaks L7 brute-forces: up to 8 on pull requests, up to 16 past
their depth, as the nightly job checks (docs/adr/0209, its section 3).
-}
bruteLimitAt :: Int -> Int
bruteLimitAt depth = if depth > linesPrDepth then 16 else bruteLimit

-- | The seed of the inputs drawn: the same inputs on every run of a commit.
sampleSeed :: Word64
sampleSeed = 0x0209

-- | A variable that holds a whole number of 0 or more, or the default when it is unset or empty.
wholeNumber :: String -> Int -> IO Int
wholeNumber name def =
  lookupEnv name >>= \case
    Nothing -> pure def
    Just "" -> pure def
    Just s -> case readMaybe s of
      Just n | n >= 0 -> pure n
      _ -> assertFailure (name <> " is not a whole number of 0 or more: " <> show s)

-- * the enumeration

-- | What 'breakParagraph' reads of an item: the boxes without their looks and kinds.
type Key = (Integer, [(Int, Integer, Integer, Integer, Text, Bool, Integer, Integer, Integer, Integer, Int)], Maybe (Int, Int), Bool)

keyOf :: Sp -> Params -> [Item] -> Key
keyOf w ps its = (unSp w, map item its, pExpansion ps, pProtrusion ps)
  where
    item = \case
      Box (Sp bw) c -> (0, bw, 0, 0, bcText c, bcExpandable c, unSp (bcProtrudeStart c), unSp (bcProtrudeEnd c), unSp (bcEdgeStart c), unSp (bcEdgeEnd c), 0)
      Glue (Sp gw) (Sp y) (Sp z) _ _ -> (1, gw, y, z, "", False, 0, 0, 0, 0, 0)
      Penalty (Sp pw) p h -> (2, pw, case h of NoHyphen -> 0; ExplicitHyphen -> 1; PatternHyphen _ -> 2; WrapMark _ -> 3; SoftHyphen _ -> 4, 0, "", False, case h of PatternHyphen (Sp q) -> q; SoftHyphen (Sp q) -> q; _ -> 0, 0, 0, 0, p)

{- | The values 'breakParagraph' is given for the inputs of a group in
vertical writing, with no break between two digits, as in horizontal
writing (golem-layout ADR 0049, B2).
-}
keysOfDigitsKept :: Group -> [Key]
keysOfDigitsKept g =
  let its = forbidPairs False (T.replicate (gPre g) "あ" <> T.concat (gRun g) <> T.replicate (gPost g) "い") (itemsOf True (gSetting g) (gPre g) (gRun g) (gPost g))
   in [keyOf (fromIntegral w * fs) (paramsOf (gSetting g) e its) its | (w, e) <- gCases g]

-- | The values 'breakParagraph' is given for the inputs of a group, vertical or not.
keysOf :: Bool -> Group -> [Key]
keysOf vertical g =
  let its = itemsOf vertical (gSetting g) (gPre g) (gRun g) (gPost g)
   in [keyOf (fromIntegral w * fs) (paramsOf (gSetting g) e its) its | (w, e) <- gCases g]

{- | The settings the normal form leaves out that give 'breakParagraph'
another value than the setting of the normal form for them, in lines up
to the width given.
-}
normalFormMisses :: Int -> [Text] -> [Violation]
normalFormMisses maxWidth run =
  [ Violation "normal form" (show (gSetting g, gPre g, gPost g, w, e) <> " gives another value than " <> show normal)
  | (g, normal) <- rawGroups maxWidth run,
    let its = itemsOf False (gSetting g) (gPre g) run (gPost g),
    (w, e) <- gCases g,
    let width = fromIntegral w * fs
        e' = e && hasLatin run,
    case Map.lookup (normal, gPre g, gPost g) composed of
      Nothing -> True
      Just nits -> keyOf width (paramsOf (gSetting g) e its) its /= keyOf width (paramsOf normal e' nits) nits
  ]
  where
    composed = Map.fromList [((gSetting g, gPre g, gPost g), itemsOf False (gSetting g) (gPre g) run (gPost g)) | g <- normalGroups maxWidth run]

-- | Every run up to a tier, each in its own value: the tests compare the keys of each run.
runsT :: Tiers [Text]
runsT = listsOf (Tiers [parts])

enumerationTests :: [TestTree]
enumerationTests =
  [ testCase "there are 28 parts: 15 Japanese characters, 4 Latin words, 4 Latin signs, the soft hyphen (docs/adr ADR 0272), a digit and two abbreviations (golem-layout ADR 0049), and a unit (docs/adr/0275)" $ do
      length jaParts @?= 15
      length latinParts @?= 9
      length pairParts @?= 3
      length unitParts @?= 1
      length (nub parts) @?= 28,
    testCase "in lines of 2 em, the inputs of up to 1 part are as many as the parts and the settings allow" $ do
      let made = [i | t <- upTo 1 (groupT (normalGroups 5)), g <- t, i <- groupInputs g, inWidth i == 2]
          -- before the run 0 or 1 'あ', after it none or 2 'い'
          placed = 2 * 2
          -- the empty run; 9 Japanese parts of one setting (漢あ「」〜！・ゝ and the
          -- ideographic space); the soft hyphen, of one setting too (docs/adr
          -- ADR 0272); the 3 parts of the pairs, of one setting too
          -- (golem-layout ADR 0049) and the unit 円 (docs/adr/0275); ー and ぁ, strict and loose; 。 and 、,
          -- with and without hanging; 10 parts of Latin text or of both
          -- scripts (… — and the 8 other Latin parts), with and without
          -- protrusion, in no span, en, fr (docs/adr ADR 0276) and ja, with and
          -- without the expansion
          runs = 1 + 9 + 1 + 3 + 1 + 2 * 2 + 2 * 2 + 10 * (2 * 4 * 2)
      length made @?= placed * runs,
    testCase "the normal form: up to 2 parts (1 on pull requests), the inputs it leaves out give 'breakParagraph' no value it is not given" $ do
      -- the values (items, width, expansion and protrusion) of every
      -- setting are those of the normal form, run by run
      depth <- linesDepth
      let d = formDepth depth
      checkAllPar d runsT (normalFormMisses (maxWidthAt depth))
        @?= Passed (length (concat (upTo d runsT))),
    testCase "vertical writing: up to 2 parts (1 on pull requests), it gives 'breakParagraph' the same values, but between two digits (golem-layout ADR 0049, B2)" $ do
      depth <- linesDepth
      let d = formDepth depth
      checkAllPar d runsT (\run -> [Violation "vertical" (show g) | g <- normalGroups (maxWidthAt depth) run, keysOfDigitsKept g /= keysOf False g])
        @?= Passed (length (concat (upTo d runsT))),
    testCase "the advances: table, hyphenation and lime-tree are broken where the patterns and the hyphen allow" $ do
      let s = Setting True False False Nothing
          shape = \case
            Box _ c -> T.unpack (bcText c)
            Glue {} -> "_"
            Penalty _ p h -> case h of
              PatternHyphen _ -> "|P"
              ExplicitHyphen -> "|E"
              WrapMark _ -> "|W"
              SoftHyphen _ -> "|S"
              NoHyphen -> if p >= infPenalty then "|X" else "|" <> show p
          shapes run = map shape (itemsOf False s 0 run 0)
      -- each, then the paragraph end: no break, the fil glue, the forced break
      shapes ["table"] @?= ["ta", "|P", "ble", "|X", "_", "|-10000"]
      shapes ["hyphenation"] @?= ["hy", "|P", "phen", "|P", "ation", "|X", "_", "|-10000"]
      shapes ["lime-tree"] @?= ["lime-", "|E", "tree", "|X", "_", "|-10000"]
      -- a soft hyphen between two letters, and one before the first (docs/adr ADR 0272)
      shapes ["table", "\xAD", "a"] @?= ["table", "|S", "a", "|X", "_", "|-10000"]
      shapes ["\xAD", "hyphenation"] @?= ["hyphenation", "|X", "_", "|-10000"]
      -- 漢 and a, with the space between Japanese and Latin text
      shapes ["漢", "a"] @?= ["漢", "_", "a", "|X", "_", "|-10000"],
    testCase "D4, D5 (docs/adr/0222): the patterns see the letters of a word only, without the characters before and after them" $ do
      let s = Setting True False False Nothing
          cuts run = [T.unpack (bcText c) | Box _ c <- itemsOf False s 0 run 0]
          hyphens run = length [() | Penalty _ _ (PatternHyphen _) <- itemsOf False s 0 run 0]
      cuts ["table", "."] @?= ["ta", "ble."]
      cuts ["“", "table", "”"] @?= ["“ta", "ble”"]
      cuts ["table,"] @?= ["ta", "ble,"]
      cuts ["hyphenation", "."] @?= ["hy", "phen", "ation."]
      cuts ["hyphenation"] @?= ["hy", "phen", "ation"]
      cuts ["I’ll"] @?= ["I’ll"]
      map hyphens [["table", "."], ["“", "table", "”"], ["table,"]] @?= [1, 1, 1],
    testCase "the advances: a quarter, a half and three quarters of an em for Latin text, an em for Japanese text" $ do
      let s = Setting True False False Nothing
          widths run = [unSp w | Box w _ <- itemsOf False s 0 run 0]
          em = unSp fs
      widths ["a"] @?= [em `div` 2]
      widths ["table"] @?= [em `div` 4 + em `div` 2, em `div` 2 + em `div` 4 + em `div` 2]
      widths ["漢"] @?= [em]
      widths ["m", " ", "w"] @?= [em * 3 `div` 4, em * 3 `div` 4]
      widths ["“", "a", "”"] @?= [em `div` 2 * 3]
  ]

-- * the predicates on outputs made by hand

-- | The setting of the defaults: strict kinsoku, no hanging, no protrusion, no span.
plain :: Setting
plain = Setting True False False Nothing

-- | The paragraph of a run without 'あ' before it nor 'い' after it, in the setting, the expansion and the width given.
paragraphIn :: Setting -> Bool -> Int -> [Text] -> Paragraph
paragraphIn s e w run = paragraphOf (Input s e w 0 run 0)

-- | The paragraph broken again after its items are changed: what the predicates read of it changes with them.
rebroken :: ([Item] -> [Item]) -> Paragraph -> Paragraph
rebroken f p =
  let its = f (pItems p)
   in p {pItems = its, pBreaks = breakParagraph (pParams p) (const (pWidth p)) its}

{- | The items with a break allowed before each box of the text given
where a prohibition kept it: in place of the infinite penalty, or
between two boxes with nothing between them.
-}
allowBefore :: Text -> [Item] -> [Item]
allowBefore t = \case
  Penalty _ p _ : rest@(Box _ c : _) | p >= infPenalty && bcText c == t -> Penalty 0 0 NoHyphen : allowBefore t rest
  b@(Box {}) : rest@(Box _ c : _) | bcText c == t -> b : Penalty 0 0 NoHyphen : allowBefore t rest
  x : rest -> x : allowBefore t rest
  [] -> []

-- | The items with a break allowed after each box of the text given where a prohibition kept it.
allowAfter :: Text -> [Item] -> [Item]
allowAfter t = \case
  b@(Box _ c) : Penalty _ p _ : rest | p >= infPenalty && bcText c == t -> b : Penalty 0 0 NoHyphen : allowAfter t rest
  b@(Box _ c) : rest@(Box {} : _) | bcText c == t -> b : Penalty 0 0 NoHyphen : allowAfter t rest
  x : rest -> x : allowAfter t rest
  [] -> []

-- | The items with a break after a written hyphen put after each box of the text given that a box follows.
explicitAfter :: Text -> [Item] -> [Item]
explicitAfter t = \case
  b@(Box _ c) : rest@(Box {} : _) | bcText c == t -> b : Penalty 0 50 ExplicitHyphen : explicitAfter t rest
  x : rest -> x : explicitAfter t rest
  [] -> []

-- | The lines of a paragraph changed.
withLines :: ([Line] -> [Line]) -> Paragraph -> Paragraph
withLines f p = p {pBreaks = (pBreaks p) {brLines = f (brLines (pBreaks p))}}

-- | The line k changed.
atLine :: Int -> (Line -> Line) -> [Line] -> [Line]
atLine k f ls = [if i == k then f l else l | (i, l) <- zip [0 ..] ls]

-- | The invariants a paragraph breaks, L7 not brute-forced.
broken :: Paragraph -> [LineInvariant]
broken = map breachOf . breaches 0

-- | The invariants a paragraph breaks, L7 brute-forced.
brokenAll :: Paragraph -> [LineInvariant]
brokenAll = map breachOf . breaches bruteLimit

-- | The paragraph a predicate test starts from, and that it breaks no invariant.
sound :: Paragraph -> Assertion
sound p = brokenAll p @?= []

predicateTests :: [TestTree]
predicateTests =
  [ testCase "L1: two characters of a line swapped" $ do
      let p = paragraphIn plain False 2 ["あ", "い", "う", "え"]
          swap l =
            l
              { lineItems = case lineItems l of
                  Box w a : g : Box w' b : rest -> Box w' b : g : Box w a : rest
                  its -> its
              }
      sound p
      broken (withLines (atLine 0 swap) p) @?= [L1],
    testCase "L2: a line that starts with a full stop" $ do
      let p = paragraphIn plain False 2 ["あ", "あ", "。"]
      sound p
      broken (rebroken (allowBefore "。") p) @?= [L2],
    testCase "L2: a line that starts with a prolonged sound mark breaks strict kinsoku only" $ do
      let strict = paragraphIn plain False 2 ["あ", "あ", "ー"]
          loose = paragraphIn plain {sStrict = False} False 2 ["あ", "あ", "ー"]
      sound strict
      broken (rebroken (allowBefore "ー") strict) @?= [L2]
      broken loose @?= []
      map lineText (brLines (pBreaks loose)) @?= ["ああ", "ー"],
    testCase "L3: a line that ends with an opening bracket" $ do
      -- あ, the space before 「 and 「 fill 2 em
      let p = paragraphIn plain False 2 ["あ", "「", "あ"]
      sound p
      broken (rebroken (allowAfter "「") p) @?= [L3],
    testCase "L4: a line that breaks between two ellipses" $ do
      let p = paragraphIn plain False 2 ["あ", "…", "…"]
      sound p
      broken (rebroken (allowBefore "…") p) @?= [L4],
    testCase "L4, B2, B3, B4 (golem-layout ADR 0049): a line that breaks between two digits, after a yen sign before a digit, or between a digit and a percent sign" $ do
      let digits = paragraphIn plain False 2 ["あ", "１", "１"]
          yen = paragraphIn plain False 2 ["あ", "￥", "１"]
          percent = paragraphIn plain False 2 ["あ", "１", "％"]
      mapM_ sound [digits, yen, percent]
      map lineText (brLines (pBreaks digits)) @?= ["あ", "１１"]
      broken (rebroken (allowAfter "１") digits) @?= [L4, B2]
      broken (rebroken (allowAfter "￥") yen) @?= [L4, B3]
      broken (rebroken (allowAfter "１") percent) @?= [L4, B4],
    testCase "L4, B2 (golem-layout ADR 0049): a line of two digits wider than W, with no break where it fits, is not broken" $ do
      let p = paragraphIn plain False 2 ["１", "１", "１"]
      map lineText (brLines (pBreaks p)) @?= ["１１１"]
      brokenAll p @?= [],
    testCase "L4: a line that breaks at a space between two ellipses is not broken (golem-layout ADR 0028, K4)" $ do
      let p = paragraphIn plain False 2 ["…", " ", "…"]
      map lineText (brLines (pBreaks p)) @?= ["…", "…"]
      brokenAll p @?= [],
    testCase "L4: a line that breaks after a dash written in a word between two ellipses (golem-layout ADR 0028, K3)" $ do
      let p = paragraphOf (Input plain {sLang = Just "en"} False 2 1 ["…", "—", "…"] 0)
      sound p
      broken (rebroken (explicitAfter "…—") p) @?= [L4],
    testCase "L5: a line past W that is not overfull" $ do
      -- the last line, set an em wider than W: its glue stretches to the end
      let p = paragraphIn plain False 2 ["漢", "漢", "漢"]
      sound p
      broken (withLines (atLine 1 (\l -> l {lineTarget = lineTarget l + fs})) p) @?= [L5],
    testCase "L5: a line made overfull, with a break where it fits" $ do
      let p = paragraphIn plain False 2 ["あ", "い", "う", "え"]
          joined ls = [Line (concatMap lineItems ls) 0 (pWidth p) 0 (0, 0) 1 (0, 0) Nothing AdjustUniform]
      broken (withLines joined p) @?= [L5],
    testCase "L5, D6 (docs/adr/0222): an overfull line with no break where it fits is not broken, and is not broken inside the run of line-start prohibitions" $ do
      let p = paragraphIn plain False 2 ["」", "」", "」", "」", "」"]
      map lineOverfull (brLines (pBreaks p)) @?= [True]
      broken p @?= [],
    testCase "L6: a line but the last that does not reach W" $ do
      -- the space stretches the first line to the target, an eighth of an em short of W
      let p = paragraphIn plain False 3 ["a", " ", "table", " ", "a", " ", "table"]
      sound p
      map lineText (brLines (pBreaks p)) @?= ["atable", "atable"]
      broken (withLines (atLine 0 (\l -> l {lineTarget = lineTarget l - Sp (unSp fs `div` 8)})) p) @?= [L6],
    testCase "L6, D1 (docs/adr/0222): a line of one Japanese character without glue that stretches, short of W, is not broken" $ do
      let p = paragraphIn plain False 2 ["「", "あ", "あ"]
      broken p @?= [],
    testCase "L6, D1 (docs/adr/0222): a line of one word without glue that stretches, short of W by a step or more while the expansion is short of its limit" $ do
      -- 10000 in 10120: 12 permille to stretch, rounded down to 10, 20 sp short; a step is 50 sp
      let its = [boxOf 10000, glue 0 0 0, boxOf 10000] <> paragraphEnd
          ps = defaultParams {pExpansion = Just (20, 5)}
          p = (handParagraph 10120 its) {pParams = ps, pBreaks = breakParagraph ps (const 10120) its}
      map lineExpansion (brLines (pBreaks p)) @?= [10, 0]
      sound p
      broken (withLines (atLine 0 (\l -> l {lineExpansion = 0})) p) @?= [L6]
      -- at the limit, the line may be short by more
      let wide = (handParagraph 10400 its) {pParams = ps, pBreaks = breakParagraph ps (const 10400) its}
      map lineExpansion (brLines (pBreaks wide)) @?= [20, 0]
      broken wide @?= [],
    testCase "L7: demerits more than the least" $ do
      let p = paragraphIn plain False 2 ["あ", "い", "う", "え"]
      sound p
      brokenAll p {pBreaks = (pBreaks p) {brDemerits = brDemerits (pBreaks p) + 1}} @?= [L7],
    testCase "L8: a break between two boxes of a word, not at a hyphen" $ do
      let p = paragraphIn plain False 4 ["a", " ", "hyphenation"]
          unhyphen = map (\case Penalty w q (PatternHyphen _) -> Penalty w q NoHyphen; it -> it)
      sound p
      broken p {pItems = unhyphen (pItems p)} @?= [L8],
    testCase "L9: a break at a hyphen of the patterns in the first pass" $ do
      let p = paragraphIn plain False 4 ["a", " ", "hyphenation"]
      sound p
      brPass (pBreaks p) @?= 2
      broken p {pBreaks = (pBreaks p) {brPass = 1}} @?= [L9],
    testCase "L9: a break at a hyphen of the patterns in a span of ja" $ do
      let p = paragraphIn plain False 4 ["a", " ", "hyphenation"]
          ja c = c {bcLook = (bcLook c) {lkLang = Just "ja"}}
          inJa = map (\case Box w c -> Box w (ja c); it -> it)
      sound p
      broken (withLines (atLine 0 (\l -> l {lineItems = inJa (lineItems l)})) p) @?= [L9],
    testCase "L10: a line that starts with a space" $ do
      let p = paragraphIn plain False 2 ["a", " ", "table"]
          lastLine = length (brLines (pBreaks p)) - 1
      sound p
      broken (withLines (atLine lastLine (\l -> l {lineItems = latinSpace p : lineItems l})) p) @?= [L10],
    testCase "L11: no space between a Japanese character and a Latin word" $ do
      let p = paragraphIn plain False 3 ["漢", "a"]
          noGlue = filter (\case Glue _ y _ _ _ -> y >= filStretch; _ -> True)
      sound p
      broken (withLines (atLine 0 (\l -> l {lineItems = noGlue (lineItems l)})) p) @?= [L11],
    testCase "L11, D2 (docs/adr/0222): the space between Japanese and Latin text added to a space written between them" $ do
      let p = paragraphIn plain False 3 ["漢", " ", "a"]
          aki = case [g | g@(Glue {}) <- pItems (paragraphIn plain False 3 ["漢", "a"])] of
            g : _ -> g
            [] -> error "no glue"
          addAki = \case
            g : rest | g == latinSpace p -> g : aki : rest
            x : rest -> x : addAki rest
            [] -> []
      sound p
      broken (withLines (atLine 0 (\l -> l {lineItems = addAki (lineItems l)})) p) @?= [L11],
    testCase "L11: no space between a Japanese character and a character of both scripts in a Latin span" $ do
      let p = paragraphIn plain {sLang = Just "en"} False 3 ["あ", "“", "a"]
      broken p @?= [],
    testCase "L12: an expansion without the glyph expansion" $ do
      let p = paragraphIn plain False 2 ["あ", "い", "う", "え"]
      sound p
      broken (withLines (atLine 0 (\l -> l {lineExpansion = 5})) p) @?= [L12],
    testCase "L12: an expansion of no multiple of 5" $ do
      -- one line, the last: its glue takes up what the expansion changes
      let p = paragraphIn plain True 3 ["table", " ", "a"]
      sound p
      pExpansion (pParams p) @?= Just (20, 5)
      broken (withLines (atLine 0 (\l -> l {lineExpansion = 3})) p) @?= [L12],
    testCase "L13: a protrusion without protrusion" $ do
      let p = paragraphIn plain False 3 ["漢", "a"]
      sound p
      broken (withLines (atLine 0 (\l -> l {lineProtrusion = (0, 100)})) p) @?= [L13],
    testCase "L13: a full stop hung at the line end is not broken" $ do
      let p = paragraphIn plain {sHanging = True} False 2 ["あ", "あ", "。", "あ"]
      map lineText (brLines (pBreaks p)) @?= ["ああ。", "あ"]
      brokenAll p @?= [],
    testCase "L13, D3 (docs/adr/0222): a character of both scripts at the end of a word protrudes by its advance in the font of the word" $ do
      -- seven tenths of the half em of ” in a Latin word, not of the em of ” alone
      let p = paragraphIn plain {sProtrusion = True} False 3 ["a", "”"]
      map (snd . lineProtrusion) (brLines (pBreaks p)) @?= [Sp (unSp fs * 7 `div` 20)]
      brokenAll p @?= [],
    testCase "L13: a hyphen of the patterns protruding at the line end is not broken" $ do
      -- seven tenths of the quarter em of the hyphen
      let p = paragraphIn plain {sProtrusion = True} False 3 ["table", " ", "table"]
      map (snd . lineProtrusion) (brLines (pBreaks p)) @?= [Sp (unSp fs * 7 `div` 40), 0]
      brokenAll p @?= []
  ]

-- * the naive search

-- | A box of a width in sp, for the paragraphs made by hand.
boxOf :: Integer -> Item
boxOf w = Box (Sp w) content
  where
    content = case [c | Box _ c <- itemsOf False plain 0 ["a"] 0] of
      c : _ -> c
      [] -> error "no box"

-- | The end of a paragraph, as the composition makes it: no break, the glue that fills the last line, the forced break.
paragraphEnd :: [Item]
paragraphEnd = [Penalty 0 infPenalty NoHyphen, glue 0 filStretch 0, Penalty 0 (negate infPenalty) NoHyphen]

-- | Words of the widths given, with glue of 5, stretching 10 and shrinking 2 between them, and the end of a paragraph.
wordsOf :: [Integer] -> [Item]
wordsOf ws = concat (zipWith (\i w -> [glue 5 10 2 | i > (0 :: Int)] <> [boxOf w]) [0 ..] ws) <> paragraphEnd

bruteTests :: [TestTree]
bruteTests =
  [ testCase "L7: items with no break have no way to be broken" $ do
      feasiblePaths defaultParams 100 2 [boxOf 30] @?= []
      bruteDemerits defaultParams 100 2 [boxOf 30] @?= Nothing,
    testCase "L7: one item, the forced break, makes a line of nothing, which is not feasible" $
      bruteDemerits defaultParams 100 2 [Penalty 0 (negate infPenalty) NoHyphen] @?= Nothing,
    testCase "L7: one box makes one line of badness 0: (10 + 0) squared" $ do
      bruteDemerits defaultParams 100 1 (boxOf 30 : paragraphEnd) @?= Just 100
      brDemerits (breakParagraph defaultParams (const 100) (boxOf 30 : paragraphEnd)) @?= 100,
    testCase "L7: a paragraph of three lines, its demerits counted by hand" $ do
      -- lines of 100: "30 30 25" is 95 wide with a stretch of 20, badness
      -- (5 * 297 div 20)^3 + 2^17, divided by 2^18, is 2, demerits (10 +
      -- 2)^2 = 144; twice, then the last line of badness 0, 100; no line
      -- of two words is within the tolerance (badness 4279) and no line of
      -- four fits (124 when shrunk)
      let its = wordsOf [30, 30, 25, 30, 30, 25, 10]
      map pathDemerits (feasiblePaths defaultParams 100 1 its) @?= [388]
      bruteDemerits defaultParams 100 1 its @?= Just 388
      let br = breakParagraph defaultParams (const 100) its
      (brPass br, brDemerits br) @?= (1, 388),
    testCase "L7: breaks whose demerits leave out the formulas, or are not the least, are broken" $ do
      -- as a breakParagraph that added 0 for lineDemerits would report its
      -- path, and as one that chose the worst feasible path would: six
      -- words of 30 in lines of 100, with glue that stretches 60, break
      -- three and three, two, two and two, and other ways in the first pass
      let its = concat (zipWith (\i w -> [glue 5 60 2 | i > (0 :: Int)] <> [boxOf w]) [0 ..] (replicate 6 30)) <> paragraphEnd
          p = handParagraph 100 its
          br = pBreaks p
          ds = map pathDemerits (feasiblePaths (pParams p) (pWidth p) (brPass br) its)
      sound p
      assertBool ("more than one way: " <> show ds) (length (nub ds) > 1)
      brDemerits br @?= minimum ds
      brokenAll p {pBreaks = br {brDemerits = 0}} @?= [L7]
      brokenAll p {pBreaks = br {brDemerits = maximum ds}} @?= [L7]
  ]

-- | A paragraph of items made by hand, of boxes of "a", in lines of the width given.
handParagraph :: Sp -> [Item] -> Paragraph
handParagraph w its =
  Paragraph
    { pText = T.concat [bcText c | Box _ c <- its],
      pCode = "",
      pSize = fs,
      pWidth = w,
      pStrict = True,
      pItems = its,
      pParams = defaultParams,
      pBreaks = breakParagraph defaultParams (const w) its,
      pAdvance = advance,
      pNumberUnit = infPenalty
    }

-- * the regressions

-- | The items of a line with the break after the box of the text given put back as the break after a written hyphen.
restoreAfter :: Text -> [Item] -> [Item]
restoreAfter t = \case
  b@(Box _ c) : Penalty _ p NoHyphen : rest | p >= infPenalty && bcText c == t -> b : Penalty 0 50 ExplicitHyphen : rest
  x : rest -> x : restoreAfter t rest
  [] -> []

regressionTests :: [TestTree]
regressionTests =
  [ testCase "docs/adr ADR 0272: the output before it, a box of the soft hyphen of と\xADいう, is broken by L1 (I1)" $ do
      let p = paragraphIn plain False 5 ["と", "\xAD", "い", "う"]
          withShyBox = \case
            b@(Box _ c) : rest | bcText c == "と" -> b : Box 0 c {bcText = "\xAD"} : rest
            x : rest -> x : withShyBox rest
            [] -> []
      sound p
      assertBool "L1" (L1 `elem` broken (rebroken withShyBox p)),
    testCase "docs/adr ADR 0272: the output before it, in\xAD\&com\xADpre\xADhen\xADsi\xAD\&bil\xADity one box, is broken by L1 (I1) and L9 (I3)" $ do
      let word = "in\xAD\&com\xADpre\xADhen\xADsi\xAD\&bil\xADity"
          p = paragraphIn plain False 20 [word]
          oneBox its = case [c | Box _ c <- its] of
            c : _ -> Box (sum [w | Box w _ <- its]) c {bcText = word} : drop (length (takeWhile notEnd its)) its
            [] -> its
          notEnd = \case
            Penalty _ p' NoHyphen -> p' < infPenalty
            _ -> True
      sound p
      let bs = broken (rebroken oneBox p)
      assertBool ("L1 and L9 in " <> show bs) (L1 `elem` bs && L9 `elem` bs),
    testCase "docs/adr ADR 0272 I4: a soft hyphen right after a dash is in the element after it, though the dash and the ellipsis after it make no break: [lang en] hyphenation\x2014\xAD\x2026 is hyphenated by the patterns" $ do
      -- the nightly enumeration drew it (2026-11-10): the predicate read the
      -- elements from the breaks after written hyphens, and the dash and
      -- the ellipsis after it, inseparable, have none between them
      let p = paragraphIn plain {sLang = Just "en"} False 4 ["hyphenation", "\x2014", "\xAD", "\x2026"]
      assertBool "no break after the dash" (null [() | Penalty _ q ExplicitHyphen <- pItems p, q < infPenalty])
      assertBool "the patterns hyphenate hyphenation\x2014" (not (null [() | Penalty _ _ (PatternHyphen _) <- pItems p]))
      sound p,
    testCase "docs/adr ADR 0272 I4: a hyphen of the patterns in the element of a soft hyphen before a dash is broken by I4" $ do
      let p = paragraphIn plain {sLang = Just "en"} False 4 ["hyphenation", "\xAD", "\x2014", "\x2026"]
          half w = Sp (unSp w `div` 2)
          hyphenated = concatMap $ \case
            Box w c | bcText c == "hyphenation\x2014" -> [Box (half w) c {bcText = "hyphen"}, Penalty 0 50 (PatternHyphen 0), Box (w - half w) c {bcText = "ation\x2014"}]
            it -> [it]
      sound p
      assertBool "I4" (I4 `elem` broken (rebroken hyphenated p)),
    testCase "golem-layout ADR 0016: the output before it, a full stop apart from the ellipsis before it, is broken by L2" $ do
      -- the test design of docs/adr/0209 names L4 for it, but a full stop
      -- is not inseparable: it is the line-start prohibition that it breaks
      let p = paragraphIn plain False 2 ["あ", "…", "。"]
      sound p
      broken (rebroken (allowBefore "。") p) @?= [L2],
    testCase "golem-layout ADR 0016: an output that breaks between two ellipses is broken by L4" $ do
      let p = paragraphIn plain False 2 ["あ", "…", "…", "。"]
      sound p
      broken (rebroken (allowBefore "…") p) @?= [L4],
    testCase "the output before what does not fit was pushed out in the last pass, a line past W where a break fits, is broken by L5" $ do
      let p = paragraphIn plain False 2 ["あ", "い", "う", "え", "お"]
          joined ls = [Line (concatMap lineItems ls) 0 (pWidth p) 0 (0, 0) 1 (0, 0) Nothing AdjustUniform]
      sound p
      broken (withLines joined p) @?= [L5],
    testCase "golem-layout ADR 0008: the output before it, a word with a hyphen sent whole to the next line past W, is broken by L5" $ do
      let p = paragraphIn plain False 2 ["lime-tree"]
          noExplicit = map (\case Penalty w _ ExplicitHyphen -> Penalty w infPenalty NoHyphen; it -> it)
          before = rebroken noExplicit p
      sound p
      map lineText (brLines (pBreaks p)) @?= ["lime-", "tree"]
      map lineText (brLines (pBreaks before)) @?= ["lime-tree"]
      broken (withLines (map (\l -> l {lineItems = restoreAfter "lime-" (lineItems l)})) before {pItems = pItems p}) @?= [L5],
    testCase "golem-layout ADR 0036 N2: [code: 漢/…] in a span of en, in lines of 2, is the one line the naive search finds least" $ do
      -- the wrap mark after "/" makes the line to it 2.5 em; a node that
      -- dies there, as in TeX, misses the line "漢/…" of 2 em (demerits 200, not 100)
      let i = Input (Setting True False False (Just "en")) False 2 0 ["漢", "/", "…"] 0
          (its, ps, br) = breakCodeInput i
      map lineText (brLines br) @?= ["漢/…"]
      Just (brDemerits br) @?= bruteDemerits ps (lineWidth i) (brPass br) its
      brDemerits br @?= 100
  ]

-- * every input

-- | The paragraph of an input, for the predicates.
paragraphOf :: Input -> Paragraph
paragraphOf i = paragraphWith (itemsOf False (inSetting i) (inPre i) (inRun i) (inPost i)) i

{- | The paragraph of an input whose items are given: those of its group,
composed once for every width and expansion of it.
-}
paragraphWith :: [Item] -> Input -> Paragraph
paragraphWith = paragraphAdjusted balancedAdjust

{- | The line adjustment of an input (docs/adr/0274): pulling in first or
balanced, and the stretch limit in permille, or none; and the penalty of a
number and its unit (docs/adr/0275), which the items are composed with.
-}
data Adjust = Adjust {aPullIn :: !Bool, aLimit :: !(Maybe Int), aNumberUnit :: !Int}
  deriving stock (Eq, Ord, Show)

-- | The adjustment of 'defaultParams' and 'defaultComposeEnv': balanced, no limit, numbers kept with their units.
balancedAdjust :: Adjust
balancedAdjust = Adjust False Nothing 10000

{- | The adjustments of the inputs at a depth (docs/adr/0274, its test
design). Past 'linesPrDepth', as the nightly job checks: both values of
line-adjustment, each with no limit and the limits 0 and 2500. On pull
requests, the default composition alone, pulling in first with no limit
(docs/adr/0282, docs/adr ADR 0281, its section 3). Timed as docs/adr ADR
0281 asks, the six back on pull requests take the area past its 10
seconds (18.74 to 18.81). Timed again as docs/adr ADR 0286 asks (the
median of four jobs, run 42761004416), balanced without a limit added to
the span of fr and R1 takes the area past its 10 seconds (11.21 to
11.38), so the values of line-adjustment stay on the nightly job (docs/adr
ADR 0281, its section 7). The limits are checked on pull requests on the
paragraphs made by hand and by R7.
-}
adjustsAt :: Int -> [Text] -> [Adjust]
adjustsAt depth run =
  [ Adjust p l n
  | (p, l) <- if depth > linesPrDepth then [(p, l) | p <- [False, True], l <- [Nothing, Just 0, Just 2500]] else [(True, Nothing)],
    -- the penalty 50 of a number and its unit only where the run has a digit (docs/adr/0275, its test design)
    n <- 10000 : [50 | "１" `elem` run]
  ]

-- | The items of an input in an adjustment: composed with its penalty of a number and its unit.
itemsAdjusted :: Adjust -> Setting -> Int -> [Text] -> Int -> [Item]
itemsAdjusted a s pre run post = fst (composeInlines ((composeEnv False s) {ceNumberUnitPenalty = aNumberUnit a}) (inlinesOf s pre run post))

-- | The parameters with an adjustment.
withAdjust :: Adjust -> Params -> Params
withAdjust a ps = ps {pPullInFirst = aPullIn a, pStretchLimit = (\m -> toInteger m % 1000) <$> aLimit a}

-- | 'paragraphWith' with an adjustment.
paragraphAdjusted :: Adjust -> [Item] -> Input -> Paragraph
paragraphAdjusted a its i =
  let ps = withAdjust a (paramsOf (inSetting i) (inExpansion i) its)
      br = breakParagraph ps (const (lineWidth i)) its
   in Paragraph
        { pText = T.replicate (inPre i) "あ" <> T.concat (inRun i) <> T.replicate (inPost i) "い",
          pCode = "",
          pSize = fs,
          pWidth = lineWidth i,
          pStrict = sStrict (inSetting i),
          pItems = its,
          pParams = ps,
          pBreaks = br,
          pAdvance = advance,
          pNumberUnit = aNumberUnit a
        }

{- | A known bug: its item in 「既知の不具合」 of the specification, the
shape of the inputs it is excused in, the breaches it excuses there, and
how many inputs up to each depth have them. The item goes when the ADR
that fixes the bug is in.
-}
data LineBug = LineBug
  { lbItem :: String,
    lbShape :: Input -> Bool,
    lbExcuses :: Input -> Breach -> Bool,
    lbCounts :: [(Int, Int)]
  }

-- | The known bugs, in the order of 「既知の不具合」: none since golem-layout ADR 0032.
lineBugs :: [LineBug]
lineBugs = []

-- | The breaches of an input no known bug excuses, and whether each known bug excuses one.
judged :: Int -> (Input, Adjust) -> ([Breach], [Bool])
judged limit (i, a) = judgedAs limit i (paragraphAdjusted a (itemsAdjusted a (inSetting i) (inPre i) (inRun i) (inPost i)) i)

-- | 'judged' of the paragraph given for the input.
judgedAs :: Int -> Input -> Paragraph -> ([Breach], [Bool])
judgedAs limit i p =
  let bs = breaches limit p
      excuses b br = lbShape b i && lbExcuses b i br
   in ([br | br <- bs, not (any (`excuses` br) lineBugs)], [lbShape b i && any (lbExcuses b i) bs | b <- lineBugs])

-- | The inputs each known bug excuses. Strict, so that the count of millions of inputs is a list of numbers.
newtype Excused = Excused [Int]
  deriving stock (Eq, Show)

instance Semigroup Excused where
  Excused as <> Excused bs = let cs = add as bs in foldr seq () cs `seq` Excused cs
    where
      add (x : xs) (y : ys) = x + y : add xs ys
      add xs [] = xs
      add [] ys = ys

instance Monoid Excused where
  mempty = Excused []

-- | The violations of the first input of a group that has some, and the known bugs that excuse its inputs.
judgeGroup :: Int -> Int -> Group -> ([Violation], Excused)
judgeGroup depth limit g =
  let itsOf n = itemsAdjusted balancedAdjust {aNumberUnit = n} (gSetting g) (gPre g) (gRun g) (gPost g)
      composed = [(n, itsOf n) | n <- [10000, 50]]
      results = [((i, a), judgedAs limit i (paragraphAdjusted a its i)) | i <- groupInputs g, a <- adjustsAt depth (gRun g), Just its <- [lookup (aNumberUnit a) composed]]
      excused = Excused (foldr (zipWith (+) . map fromEnum . snd . snd) (map (const 0) lineBugs) results)
   in case [(i, bs) | (i, (bs, _)) <- results, not (null bs)] of
        (i, bs) : _ -> ([Violation (show (breachOf b)) (breachWhy b) | b <- bs] <> [Violation "input" (show i)], excused)
        [] -> ([], excused)

-- | The first input of a group that breaks an invariant no known bug excuses.
firstBroken :: Int -> Int -> Group -> Maybe (Input, Adjust)
firstBroken depth limit g = case [ia | i <- groupInputs g, a <- adjustsAt depth (gRun g), let ia = (i, a), not (null (fst (judged limit ia)))] of
  i : _ -> Just i
  [] -> Nothing

{- | An input of n parts drawn from the enumeration: its run, a setting of
its normal form, a placing, one of its widths and an expansion, and an
adjustment.
-}
drawInput :: Int -> Int -> SplitMix -> ((Input, Adjust), SplitMix)
drawInput maxWidth n g0 =
  let go 0 g = ([], g)
      go m g = let (x, g') = oneOf parts g; (xs, g'') = go (m - 1 :: Int) g' in (x : xs, g'')
      (run, g1) = go n g0
      (s, g2) = oneOf (normalSettings run) g1
      (placing, g3) = oneOf (placings maxWidth) g2
      (pre, post, ws) = placing
      (w, g4) = oneOf ws g3
      (e, g5) = if hasLatin run then oneOf [False, True] g4 else (False, g4)
      (a, g6) = oneOf (adjustsAt maxBound run) g5
   in ((Input s e w pre run post, a), g6)

-- | The input with parts of its run taken out as long as it still breaks an invariant no known bug excuses.
shrinkInput :: Int -> (Input, Adjust) -> (Input, Adjust)
shrinkInput limit (i, a) = (i {inRun = shrinkList (\run -> not (null (fst (judged limit (i {inRun = run}, a))))) (inRun i)}, a)

report :: Int -> String -> (Input, Adjust) -> String
report limit what (input, a) =
  intercalate
    "\n"
    ( (what <> ":")
        : ["  " <> show (breachOf b) <> ": " <> breachWhy b | b <- bs]
          <> ["", "In the adjustment " <> show a <> " (docs/adr/0274); as a case of LineBreakingSpec:", "", renderCase name input]
    )
  where
    bs = fst (judged limit (input, a))
    name = case bs of
      b : _ -> show (breachOf b) <> ": " <> breachWhy b
      [] -> "no violation"

{- | What R1 of docs/adr/0274 compares of a paragraph: its breaks, demerits
and pass, and where each item of each line is placed, by its kind and
widths.
-}
placedKey :: Paragraph -> String
placedKey p =
  let br = pBreaks p
      item = \case
        Box w c -> "B" <> show (unSp w) <> T.unpack (bcText c)
        Glue w y z _ _ -> "G" <> show (unSp w, unSp y, unSp z)
        Penalty w n _ -> "P" <> show (unSp w, n)
   in show (brPositions br, brDemerits br, brPass br, [[(item it, unSp off) | (it, off) <- placeLine l] | l <- brLines br])

-- | FNV-1a, 64 bits, over the code points of a string.
fnv :: String -> Word64
fnv = foldl (\h c -> (h `xor` fromIntegral (ord c)) * 0x100000001b3) 0xcbf29ce484222325

{- | R1 of docs/adr/0274: every run up to two parts, each input of lines up
to 5 em, balanced and without a limit, broken and placed: the hash of
'placedKey' of each. The golden file was written by the implementation
before the ADR.
-}
balancedLines :: Text
balancedLines =
  let -- each run hashed on every processor, then written in the order of the runs
      -- the runs of the parts before docs/adr/0275, as the hashes were written
      runs0274 = listsOf (Tiers [partsBefore0275])
      (_, hashes) = tallyAllPar 2 runs0274 (\run -> ([], Map.singleton run (hashOf run)))
      -- without the span of fr (docs/adr ADR 0276) and the change of
      -- docs/adr/0275, as the hashes were written before them
      hashOf run = T.pack (showHex (fnv (concat [placedKey (paragraphWith its i) | g <- normalGroups 5 run, sLang (gSetting g) /= Just "fr", let its = withoutNumberUnits False (T.replicate (gPre g) "あ" <> T.concat run <> T.replicate (gPost g) "い") (itemsOf False (gSetting g) (gPre g) (gRun g) (gPost g)), i <- groupInputs g])) "")
   in T.unlines [T.intercalate "\t" [T.pack (show run), Map.findWithDefault "" run hashes] | run <- concat (upTo 2 runs0274)]

-- | R7 of docs/adr/0274: the breaks of each input with each limit, pulling in first and not, are those without a limit.
limitMisses :: Int -> [Text] -> [Violation]
limitMisses maxWidth run =
  [ Violation "R7" (show (i, a))
  | g <- normalGroups maxWidth run,
    let its = itemsOf False (gSetting g) (gPre g) (gRun g) (gPost g),
    i <- groupInputs g,
    p <- [False, True],
    let breaksOf l = let br = pBreaks (paragraphAdjusted (Adjust p l 10000) its i) in (brPositions br, brDemerits br, brPass br),
    a <- [Adjust p (Just m) 10000 | m <- [0, 1000, 2500]],
    breaksOf (aLimit a) /= breaksOf Nothing
  ]

exhaustiveTests :: [TestTree]
exhaustiveTests =
  [ testCase "R1 (docs/adr/0274): balanced and without a limit, every input up to 2 parts is broken and placed as before the ADR (test/golden/line-adjustment-balanced.tsv)" $ do
      -- up to 'r1Depth', on pull requests too (docs/adr ADR 0286)
      depth <- linesDepth
      when (r1Depth depth > 0) $ do
        want <- BL.readFile "test/golden/line-adjustment-balanced.tsv"
        BL.fromStrict (TE.encodeUtf8 balancedLines) == want @? "the lines differ from test/golden/line-adjustment-balanced.tsv",
    testCase "R7 (docs/adr/0274): a stretch limit of 0, 1000 or 2500 changes no breaks, demerits nor pass of any input up to 2 parts (1 on pull requests)" $ do
      -- 1 on pull requests, as the normal form: up to 2 parts took 4 seconds of the area on a laptop (docs/adr/0208, its section 4)
      depth <- linesDepth
      let d = formDepth depth
      checkAllPar d runsT (limitMisses (maxWidthAt depth)) @?= Passed (length (concat (upTo d runsT))),
    testCase "L1 to L13, T1 and I4 (docs/adr ADR 0272), B2 to B4 (golem-layout ADR 0049), R2, R5 and R6 (docs/adr/0274, each input pulling in first and balanced, with no limit and limits of 0 and 2500) hold for every input up to GOLEM_ENUM_LINES_DEPTH parts, but the known bugs, which excuse as many inputs as pinned" $ do
      depth <- linesDepth
      let limit = bruteLimitAt depth
      -- built here, not in a value of its own, so that it is not held
      case tallyAllPar depth (groupT (groupsAt depth)) (judgeGroup depth limit) of
        (Failed k g _, _) -> case firstBroken depth limit g of
          Just i -> assertFailure (report limit ("the smallest input that breaks an invariant has " <> show k <> " parts") i)
          Nothing -> assertFailure "a group broke an invariant, but none of its inputs does"
        (Passed _, Excused counted) -> do
          let wrong =
                [ (lbItem b, lookup depth (lbCounts b), n)
                | (b, n) <- zip lineBugs (counted <> repeat 0),
                  lookup depth (lbCounts b) /= Just n
                ]
          if null wrong
            then pure ()
            else
              assertFailure
                ( "at depth "
                    <> show depth
                    <> ", the inputs a known bug excuses differ from the count pinned:\n"
                    <> intercalate "\n" [item <> ": pinned " <> maybe "nothing" show pinned <> ", counted " <> show n | (item, pinned, n) <- wrong]
                ),
    testCase "L1 to L13, T1 and I4 (docs/adr ADR 0272) hold for every input drawn one part past GOLEM_ENUM_LINES_DEPTH, GOLEM_ENUM_LINES_SAMPLES of them, but the known bugs" $ do
      depth <- linesDepth
      count <- linesSamples
      let limit = bruteLimitAt depth
          drawn = Tiers [sampleT sampleSeed count (drawInput (maxWidthAt depth) (depth + 1))]
      case checkAllPar 0 drawn (map (\b -> Violation (show (breachOf b)) (breachWhy b)) . fst . judged limit) of
        Passed _ -> pure ()
        Failed _ input _ ->
          let small = shrinkInput limit input
           in assertFailure (report limit ("an input drawn with " <> show (depth + 1) <> " parts breaks an invariant; with parts taken out as long as it still does, it has " <> show (length (inRun (fst small)))) small)
  ]

-- * inline code (golem-layout ADR 0034, its section 5)

-- | The paragraph of an input of code whose items are given.
codeParagraphWith :: [Item] -> Input -> Paragraph
codeParagraphWith its i = (paragraphWith its i) {pCode = T.concat (inRun i), pParams = ps, pBreaks = breakParagraph ps (const (lineWidth i)) its}
  where
    ps = paramsOf (inSetting i) False its

-- | The paragraph of an input of code.
codeParagraphOf :: Input -> Paragraph
codeParagraphOf i = codeParagraphWith (codeItemsOf False (inSetting i) (inPre i) (inRun i) (inPost i)) i

-- | The invariants a paragraph of code breaks, L7 not brute-forced.
codeBroken :: Paragraph -> [LineInvariant]
codeBroken = map breachOf . codeBreaches codeMark 0

{- | C4: the items of a run of code without a Japanese character are
those it has with an empty wrap mark, but the width and the mark of the
breaks of the mark; with the padding given (golem-layout ADR 0048).
-}
c4Misses :: Sp -> Group -> [Violation]
c4Misses pad g
  | any (T.any (\c -> c `notElem` (" ab/_\"-.1" :: String))) (gRun g) = []
  | otherwise =
      [ Violation "C4" (show (pad, gSetting g, gPre g, gRun g, gPost g))
      | map unmarked (codeItemsWith pad False (gSetting g) (gPre g) (gRun g) (gPost g)) /= map unmarked (fst (composeInlines (emptyMark (codeEnvWith pad False (gSetting g))) (codeInlinesOf (gSetting g) (gPre g) (gRun g) (gPost g))))
      ]
  where
    emptyMark e = e {ceRestyle = \lk inl -> (ceRestyle e lk inl) {lkWrapMark = ""}}
    unmarked = \case
      Penalty _ p (WrapMark _) -> Penalty 0 p NoHyphen
      Box w c -> Box w c {bcLook = (bcLook c) {lkWrapMark = ""}}
      it -> it

{- | The known bugs the runs of code find, in the order of 「既知の不具合」:
none since golem-layout ADR 0038, the space of code at the end of a
paragraph having gone with golem-layout ADR 0037.
-}
codeLineBugs :: [LineBug]
codeLineBugs = []

{- | The violations of the first input of a group of code that has some, C4
and D1 to D5 among them, and the known bugs that excuse its inputs: each
input without padding and with 'codePadding' (golem-layout ADR 0048).
-}
judgeCodeGroup :: Int -> Group -> ([Violation], Excused)
judgeCodeGroup limit g =
  let itemsWith pad = codeItemsWith pad False (gSetting g) (gPre g) (gRun g) (gPost g)
      bare = itemsWith 0
      padded = itemsWith codePadding
      judge its i =
        let bs = codeBreaches codeMark limit (codeParagraphWith its i)
            excuses b br = lbShape b i && lbExcuses b i br
         in ([br | br <- bs, not (any (`excuses` br) codeLineBugs)], [lbShape b i && any (lbExcuses b i) bs | b <- codeLineBugs])
      results = [((pad, i), judge its i) | (pad, its) <- [(0, bare), (codePadding, padded)], i <- groupInputs g]
      excused = Excused (foldr (zipWith (+) . map fromEnum . snd . snd) (map (const 0) codeLineBugs) results)
      edgeSpace = take 1 (gRun g) == [" "] || take 1 (reverse (gRun g)) == [" "]
      padding = [Violation (show (breachOf b)) (breachWhy b) | b <- paddingBreaches codePadding edgeSpace bare padded] <> [Violation "input" (show (gSetting g, gPre g, gRun g, gPost g)) | not (null (paddingBreaches codePadding edgeSpace bare padded))]
   in case c4Misses 0 g <> c4Misses codePadding g <> padding <> concat [[Violation (show (breachOf b)) (breachWhy b) | b <- bs] <> [Violation "input" (show i <> ", padding " <> show pad)] | ((pad, i), (bs, _)) <- take 1 [r | r@(_, (bs, _)) <- results, not (null bs)]] of
        vs -> (vs, excused)

-- | Every run of code up to a tier, each in its own value.
codeRunsT :: Tiers [Text]
codeRunsT = listsOf (Tiers [codeParts])

codeTests :: [TestTree]
codeTests =
  [ testCase "there are 18 parts of code, and 342 runs of up to 2 parts" $ do
      length (nub codeParts) @?= 18
      length (concat (upTo 2 codeRunsT)) @?= 1 + 342,
    testCase "C1, C2, C8: the runs of code are composed and broken as the ADR shows" $ do
      let (_, _, br) = breakCodeInput (Input plain False 4 0 ["漢", "あ", "a", "あ", "漢", "あ"] 0)
      map lineText (brLines br) @?= ["漢あa", "あ漢あ"]
      [m | l <- take 1 (brLines br), Penalty _ _ (WrapMark m) <- take 1 (reverse (lineItems l))] @?= [codeMark],
    testCase "C1: a break taken out between two Japanese characters of code" $ do
      let p = codeParagraphOf (Input plain False 4 0 ["漢", "あ", "漢"] 0)
          noBreak = map (\case Penalty w q h | q < infPenalty, q > negate infPenalty, h /= NoHyphen -> Penalty w infPenalty h; it -> it)
      codeBroken p @?= []
      nub (codeBroken p {pItems = noBreak (pItems p)}) @?= [C1],
    testCase "C1: a break put before a full stop of code" $ do
      let p = codeParagraphOf (Input plain False 4 0 ["漢", "。"] 0)
      codeBroken p @?= []
      codeBroken (rebroken (allowBefore "。") p) @?= [C1],
    testCase "C2: a break of 100 between two Japanese characters of code" $ do
      let p = codeParagraphOf (Input plain False 4 0 ["漢", "あ"] 0)
          hundred = map (\case Penalty w 0 h@(WrapMark _) -> Penalty w 100 h; it -> it)
      codeBroken p @?= []
      codeBroken p {pItems = hundred (pItems p)} @?= [C2],
    testCase "J3: a break between two Latin letters of code" $ do
      let p = codeParagraphOf (Input plain False 4 0 ["ab"] 0)
          split = concatMap (\case Box w c | bcText c == "ab" -> [Box (Sp (unSp w `div` 2)) c {bcText = "a"}, Penalty 0 0 NoHyphen, Box (Sp (unSp w `div` 2)) c {bcText = "b"}]; it -> [it])
      codeBroken p @?= []
      codeBroken p {pItems = split (pItems p)} @?= [J3],
    testCase "J1: the break after a hyphen-minus sign of code taken out" $ do
      let p = codeParagraphOf (Input plain False 2 0 ["ab", "-", "ab"] 0)
          noBreak = map (\case Penalty w 100 h@(WrapMark _) -> Penalty w infPenalty h; it -> it)
      map lineText (brLines (pBreaks p)) @?= ["ab-", "ab"]
      codeBroken p @?= []
      nub (codeBroken (rebroken noBreak p)) @?= [J1],
    testCase "J2: the break after a hyphen-minus sign of code of 0, or without the mark" $ do
      let p = codeParagraphOf (Input plain False 2 0 ["ab", "-", "ab"] 0)
          zero = map (\case Penalty w 100 h@(WrapMark _) -> Penalty w 0 h; it -> it)
          unmark = map (\case Penalty _ 100 (WrapMark _) -> Penalty 0 100 NoHyphen; it -> it)
      nub (codeBroken p {pItems = zero (pItems p)}) @?= [J2]
      nub (codeBroken (rebroken unmark p)) @?= [C8, J2, J6],
    testCase "J4: a break of 100 after a hyphen-minus sign of code before a Japanese character" $ do
      let p = codeParagraphOf (Input plain False 4 0 ["a", "-", "あ"] 0)
          hundred = map (\case Penalty w 0 h@(WrapMark _) -> Penalty w 100 h; it -> it)
      codeBroken p @?= []
      nub (codeBroken p {pItems = hundred (pItems p)}) @?= [C2, J4],
    testCase "J6: a box of code that lost a character" $ do
      let p = codeParagraphOf (Input plain False 4 0 ["a", "-", "ab"] 0)
          lose = map (\case Box w c | bcText c == "ab" -> Box w c {bcText = "a"}; it -> it)
      elem J6 (codeBroken p {pItems = lose (pItems p)}) @? "J6",
    testCase "J7: an output of a pass later than the items without the breaks of J1 give" $ do
      let p = codeParagraphOf (Input plain False 2 0 ["a", "-", "ab"] 0)
      brPass (pBreaks p) @?= 1
      codeBroken p {pBreaks = (pBreaks p) {brPass = 4}} @?= [J7],
    testCase "golem-layout ADR 0048 D1 to D5: a run with spaces at its ends breaks none; the padding moved or taken off, or the glue changed, breaks them" $ do
      let itemsWith pad run = codeItemsWith pad False plain 1 run 1
          judge run f = nub (map breachOf (paddingBreaches codePadding (take 1 run == [" "] || take 1 (reverse run) == [" "]) (itemsWith 0 run) (f (itemsWith codePadding run))))
          -- the boxes whose text is given, their padding set
          padIn t (s0, e0) = map (\case Box w c | bcText c == t -> Box (w - bcPadStart c - bcPadEnd c + s0 + e0) c {bcPadStart = s0, bcPadEnd = e0}; it -> it)
          edged = [" ", "漢", "a", " "]
      judge edged id @?= []
      judge edged (padIn "漢" (0, 0)) @?= [D1]
      judge edged (padIn "a" (0, 0)) @?= [D2]
      judge [" "] (padIn "あ" (codePadding, 0)) @?= [D3]
      judge ["漢", "a"] (padIn "漢" (0, 0)) @?= [D1, D4]
      judge edged (map (\case g@Glue {} -> g {itemWidth = itemWidth g + 1}; it -> it)) @?= [D5],
    testCase "golem-layout ADR 0038 S3: two ellipses of code broken at the space between them break no invariant" $ do
      let p = codeParagraphOf (Input plain False 1 0 ["…", " ", "…"] 0)
      map lineText (brLines (pBreaks p)) @?= ["…", "…"]
      codeBroken p @?= [],
    testCase "C8: a line broken inside code without the mark" $ do
      let p = codeParagraphOf (Input plain False 2 0 ["漢", "あ", "漢", "あ"] 0)
          unmark = map (\case Penalty _ q (WrapMark _) -> Penalty 0 q NoHyphen; it -> it)
      assertBool "more than one line" (length (brLines (pBreaks p)) > 1)
      codeBroken p @?= []
      nub (codeBroken (rebroken unmark p)) @?= [C8],
    testCase "the normal form of code: up to 2 parts (1 on pull requests), the inputs it leaves out give 'breakParagraph' no value it is not given" $ do
      depth <- linesDepth
      let d = formDepth depth
          w = maxWidthAt depth
          misses run =
            [ Violation "normal form" (show (s, pre, post))
            | s <- codeSettings,
              s `notElem` normalCodeSettings run,
              let normal = s {sStrict = sStrict s || not (any (`elem` ["ー", "ぁ"]) run), sLang = if any (T.any (`elem` ("…" :: String))) run then sLang s else Nothing},
              (pre, post, ws) <- placings w,
              x <- ws,
              let width = fromIntegral x * fs
                  its = codeItemsOf False s pre run post
                  nits = codeItemsOf False normal pre run post,
              keyOf width (paramsOf s False its) its /= keyOf width (paramsOf normal False nits) nits
            ]
      checkAllPar d codeRunsT misses @?= Passed (length (concat (upTo d codeRunsT))),
    testCase "vertical writing of code: up to 2 parts (1 on pull requests), it gives 'breakParagraph' the same values" $ do
      depth <- linesDepth
      let d = formDepth depth
          keys v g = let its = codeItemsOf v (gSetting g) (gPre g) (gRun g) (gPost g) in [keyOf (fromIntegral w * fs) (paramsOf (gSetting g) e its) its | (w, e) <- gCases g]
      checkAllPar d codeRunsT (\run -> [Violation "vertical" (show g) | g <- codeGroupsOf (maxWidthAt depth) run, keys True g /= keys False g])
        @?= Passed (length (concat (upTo d codeRunsT))),
    testCase "golem-layout ADR 0037 B1, 0038, 0045, 0048: L1 to L13, T1, C1, C2, C4, C6 to C8, J1 to J7 and D1 to D5 hold for every input of code up to GOLEM_ENUM_LINES_DEPTH parts, without padding and with it, but the known bugs, which excuse as many inputs as pinned" $ do
      depth <- linesDepth
      let limit = bruteLimitAt depth
      case tallyAllPar depth (codeGroupT (maxWidthAt depth)) (judgeCodeGroup limit) of
        (Failed k _ vs, _) -> assertFailure ("the smallest input of code that breaks an invariant has " <> show k <> " parts:\n" <> intercalate "\n" [show v | v <- vs])
        (Passed _, Excused counted) -> do
          let wrong =
                [ (lbItem b, lookup depth (lbCounts b), n)
                | (b, n) <- zip codeLineBugs (counted <> repeat 0),
                  lookup depth (lbCounts b) /= Just n
                ]
          if null wrong
            then pure ()
            else assertFailure ("at depth " <> show depth <> ", the inputs of code a known bug excuses differ from the count pinned:\n" <> intercalate "\n" [item <> ": pinned " <> maybe "nothing" show pinned <> ", counted " <> show n | (item, pinned, n) <- wrong])
  ]
