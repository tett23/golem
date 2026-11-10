-- the enumerations are built in the tests that check them, and must not
-- be floated out into values that live as long as the program (docs/adr/0208)
{-# OPTIONS_GHC -fno-full-laziness -fno-cse #-}

{- | The places of line adjustment in the order of JLReq (docs/adr/0278):
the kinds of glue, the stages that shrink and stretch a set line, and A1
to A9 and A12 on paragraphs made by hand and on every small input of
docs/adr/0209.
-}
module AdjustOrderSpec (adjustOrderTests, ordersAt, staged, defaultOrder) where

import Data.Bits (xor)
import Data.ByteString.Lazy qualified as BL
import Data.Char (ord)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word64)
import Fixtures (compose, fs, look0, sp, sp0)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..), noBoxSource)
import Golem.Project.Style (adjustPlaceNames)
import Golem.TestSupport.Enum
import LineBreakEnum
import LineBreakInvariants (lineEnd)
import LineBreakInvariantsSpec (linesPrDepth)
import Numeric (showHex)
import System.Environment (lookupEnv)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit
import Text.Read (readMaybe)

adjustOrderTests :: TestTree
adjustOrderTests =
  testGroup
    "the places of line adjustment in the order of JLReq (docs/adr/0278)"
    [ testGroup "the kinds of glue" kindTests,
      testGroup "A3 to A8 on lines made by hand" lineTests,
      testGroup "A1 to A6 on every small input (docs/adr/0209)" enumerationTests,
      goldenVsString
        "A9: the items of every input up to 2 parts, the kinds and the sizes of the glue left out, are those before the ADR (test/golden/adjust-order-items.tsv)"
        "test/golden/adjust-order-items.tsv"
        (pure (BL.fromStrict (TE.encodeUtf8 itemLines)))
    ]

-- | FNV-1a, 64 bits, over the code points of a string.
fnv :: String -> Word64
fnv = foldl (\h c -> (h `xor` fromIntegral (ord c)) * 0x100000001b3) 0xcbf29ce484222325

{- | An item as A9 compares it: a glue by its width, stretch and shrink
alone, the kind and the size it has after docs/adr/0278 left out.
-}
itemKey :: Item -> String
itemKey = \case
  Glue {itemWidth = w, itemStretch = y, itemShrink = z} -> "G" <> show (unSp w, unSp y, unSp z)
  it -> show it

{- | A9 of docs/adr/0278: the items of every run up to two parts, in every
setting of its normal form, at the start and not, at the end and not, in
horizontal and in vertical writing: the hash of each run. More characters
before and after the run repeat those items. The golden file was written
by the implementation before the ADR.
-}
itemLines :: Text
itemLines =
  let (_, hashes) = tallyAllPar 2 runsT (\run -> ([], Map.singleton run (hashOf run)))
      hashOf run = T.pack (showHex (fnv (concat [concatMap itemKey (itemsOf v s pre run post) | v <- [False, True], s <- normalSettings run, pre <- [0, 1], post <- [0, 1]])) "")
   in T.unlines [T.intercalate "\t" [T.pack (show run), Map.findWithDefault "" run hashes] | run <- concat (upTo 2 runsT)]

-- | The runs of the enumeration (docs/adr/0209).
runsT :: Tiers [Text]
runsT = listsOf (Tiers [parts])

-- * the kinds

{- | The kind and the size of each glue of a text, but the glue at the end
of the paragraph, in the composition of the default aki set; @code@ is a
character style of inline code.
-}
kindsOf :: [IR.Inline] -> [(GlueKind, Sp)]
kindsOf is = [(itemKind g, itemZw g) | g@Glue {} <- fst (composeInlines env is), itemStretch g < filStretch]
  where
    env =
      (defaultComposeEnv fs)
        { ceRestyle = \lk -> \case
            IR.CharStyle _ "code" _ -> lk {lkCode = True}
            IR.CharStyle _ "big" _ -> lk {lkSize = 2 * fs}
            _ -> lk
        }

kindTests :: [TestTree]
kindTests =
  [ testCase "each row of the table of the kinds: the space between two characters of it is of its kind, in the size of its characters" $
      mapM_
        (\(t, want) -> (t, kindsOf [sp0 t]) @?= (t, want))
        [ ("ab cd", [(WordSpaceGlue, fs)]),
          ("漢・漢", [(MiddleDotGlue, fs), (MiddleDotGlue, fs)]),
          ("漢「漢", [(BracketsGlue, fs)]),
          ("漢」漢", [(BracketsGlue, fs)]),
          ("漢、漢", [(CommaGlue, fs)]),
          ("漢。漢", [(FullStopGlue, fs)]),
          ("「漢", [(ParagraphStartGlue, fs)]),
          ("漢ab", [(JapaneseWesternGlue, fs)]),
          ("ab漢", [(JapaneseWesternGlue, fs)]),
          ("あ漢", [(BetweenCharactersGlue, fs)])
        ],
    testCase "the space after a closing bracket before a middle dot is middle-dot, the first row it is in" $
      kindsOf [sp0 "漢」・漢"] @?= [(MiddleDotGlue, fs), (MiddleDotGlue, fs)],
    testCase "a space before an opening bracket at the paragraph start is paragraph-start, whatever the class after it" $
      kindsOf [sp0 "・漢"] @?= [(ParagraphStartGlue, fs), (MiddleDotGlue, fs)],
    testCase "a space between words in a larger size has that size; one of inline code has no kind and no size" $ do
      kindsOf [IR.CharStyle sp "big" [sp0 "ab cd"]] @?= [(WordSpaceGlue, 2 * fs)]
      kindsOf [IR.CharStyle sp "code" [sp0 "ab cd"]] @?= [(OtherGlue, 0)],
    testCase "the space after a larger closing bracket is in the size of the bracket" $
      kindsOf [IR.CharStyle sp "big" [sp0 "」"], sp0 "漢"] @?= [(BracketsGlue, 2 * fs)],
    testCase "the glue at the end of a paragraph has no kind and no size" $
      [(itemKind g, itemZw g) | g@Glue {} <- compose (defaultComposeEnv fs) "漢", itemStretch g >= filStretch] @?= [(OtherGlue, 0)],
    testCase "every kind but OtherGlue has a name, those style.toml reads, in the order of the table" $
      mapMaybe glueKindName [minBound .. maxBound] @?= adjustPlaceNames
  ]

-- * lines made by hand

-- | The order of the default of style.toml (docs/adr/0278, its section 3).
defaultOrder :: AdjustOrder
defaultOrder =
  AdjustStaged
    [[WordSpaceGlue], [MiddleDotGlue], [BracketsGlue, CommaGlue], [JapaneseWesternGlue]]
    [[WordSpaceGlue], [JapaneseWesternGlue], [BetweenCharactersGlue]]

-- | A box of no content of a width.
boxOf :: Sp -> Item
boxOf w = Box w (BoxContent "" False 0 0 0 look0 0 0 [] 0 0 noBoxSource Nothing noLeaf 0)

-- | A line of items set to a target, of an order, with no expansion, protrusion nor limit.
lineOf :: AdjustOrder -> Sp -> [Item] -> Line
lineOf o target its = Line its 0 target 0 (0, 0) 0 (0, 0) Nothing o

-- | The natural width of items.
naturalOf :: [Item] -> Sp
naturalOf its = sum [itemWidth it | it <- its, not (isPenalty it)]
  where
    isPenalty = \case
      Penalty {} -> True
      _ -> False

-- | A word space of the size of the text: a third of an em, stretching by a half of it and shrinking by a third.
wordSpace :: Item
wordSpace = Glue (third fs) (Sp (unSp (third fs) `div` 2)) (Sp (unSp (third fs) `div` 3)) WordSpaceGlue fs
  where
    third x = Sp (unSp x `div` 3)

-- | The half em after a comma of a size: it shrinks to nothing.
commaSpace :: Sp -> Item
commaSpace s = Glue (Sp (unSp s `div` 2)) 0 (Sp (unSp s `div` 2)) CommaGlue s

-- | The space between Japanese and Latin of the default set: a quarter em, to an eighth and to a half.
jwSpace :: Sp -> Item
jwSpace s = Glue (q 4) (q 4) (q 8) JapaneseWesternGlue s
  where
    q n = Sp (unSp s `div` n)

-- | The stretch of a tenth of an em before kana and ideographs.
charSpace :: Sp -> Item
charSpace s = Glue 0 (Sp (unSp s `div` 10)) 0 BetweenCharactersGlue s

lineTests :: [TestTree]
lineTests =
  [ testCase "A3, A4: a line of a word space and the half em after a comma, short by 1 sp more than the shrink of the space, shrinks the space to its limit and the comma by 1 sp" $ do
      let its = [boxOf fs, wordSpace, boxOf fs, commaSpace fs, boxOf fs]
          l = lineOf defaultOrder (naturalOf its - itemShrink wordSpace - 1) its
      glueAmounts l @?= [negate (toRational (unSp (itemShrink wordSpace))), -1],
    testCase "A5: two word spaces and two commas of two sizes shrink in proportion to their shrink in their stage" $ do
      let its = [boxOf fs, commaSpace fs, boxOf fs, commaSpace (2 * fs), boxOf fs, wordSpace, boxOf fs]
          l = lineOf defaultOrder (naturalOf its - itemShrink wordSpace - 3 * 65536) its
      glueAmounts l @?= [-65536, -(2 * 65536), negate (toRational (unSp (itemShrink wordSpace)))],
    testCase "A3: a line shorter than all the shrink is shrunk by all of it, as by the ratio -1" $ do
      let its = [boxOf fs, wordSpace, boxOf fs, commaSpace fs, boxOf fs]
          l = lineOf defaultOrder (naturalOf its - fs) its
      glueAmounts l @?= map (negate . toRational . unSp . itemShrink) [wordSpace, commaSpace fs],
    testCase "A4, A6: the space between Japanese and Latin and the stretch before kana, spaced more than their stretch, widen past it by as many em" $ do
      let its = [boxOf fs, jwSpace fs, boxOf fs, charSpace fs, boxOf fs]
          extra = Sp (unSp fs `div` 5)
          l = lineOf defaultOrder (naturalOf its + itemStretch (jwSpace fs) + itemStretch (charSpace fs) + 2 * extra) its
      glueAmounts l @?= map (toRational . unSp) [itemStretch (jwSpace fs) + extra, itemStretch (charSpace fs) + extra],
    testCase "A6: the last stage widens a glue of twice the size twice as far" $ do
      let its = [boxOf fs, charSpace fs, boxOf fs, charSpace (2 * fs), boxOf fs]
          l = lineOf defaultOrder (naturalOf its + itemStretch (charSpace fs) + itemStretch (charSpace (2 * fs)) + 3 * 65536) its
      glueAmounts l @?= map (toRational . unSp) [itemStretch (charSpace fs) + 65536, itemStretch (charSpace (2 * fs)) + 2 * 65536],
    testCase "A4: the space between Japanese and Latin stretches to its limit before the stretch before kana" $ do
      let its = [boxOf fs, charSpace fs, boxOf fs, jwSpace fs, boxOf fs]
          l = lineOf defaultOrder (naturalOf its + itemStretch (jwSpace fs) + 1) its
      glueAmounts l @?= [1, toRational (unSp (itemStretch (jwSpace fs)))],
    testCase "the stretch limit caps what the line stretches by before the stages share it (docs/adr/0274)" $ do
      let its = [boxOf fs, charSpace fs, boxOf fs, jwSpace fs, boxOf fs]
          ys = itemStretch (jwSpace fs) + itemStretch (charSpace fs)
          l = (lineOf defaultOrder (naturalOf its + 2 * ys) its) {lineStretchLimit = Just (1 / 2)}
      sum (glueAmounts l) @?= toRational (unSp ys) / 2
      glueAmounts l @?= [0, toRational (unSp ys) / 2],
    testCase "the line with the glue of the end of a paragraph stretches it alone, as by one ratio" $ do
      let its = [boxOf fs, wordSpace, boxOf fs, glue 0 filStretch 0]
          l = lineOf defaultOrder (naturalOf its + fs) its
      glueAmounts l @?= glueAmounts l {lineAdjustOrder = AdjustUniform},
    testCase "A7: a line of word spaces of one size alone is placed as by one ratio, stretched or shrunk, in any order" $
      sequence_
        [ placeLine l @?= placeLine l {lineAdjustOrder = AdjustUniform}
        | let its = [boxOf fs, wordSpace, boxOf fs, wordSpace, boxOf (2 * fs)],
          o <- [defaultOrder, AdjustStaged [] [], AdjustStaged [[JapaneseWesternGlue], [WordSpaceGlue]] [[BetweenCharactersGlue], [WordSpaceGlue]]],
          d <- [-(2 * 65536), -1, 1, 3 * 65536, fs],
          let l = lineOf o (naturalOf its + d) its
        ],
    testCase "A8: with an empty shrink-order a line that shrinks is placed as by one ratio" $
      sequence_
        [ placeLine l @?= placeLine l {lineAdjustOrder = AdjustUniform}
        | let its = [boxOf fs, wordSpace, boxOf fs, commaSpace (2 * fs), boxOf fs, jwSpace fs, boxOf fs],
          d <- [1, 65536, 5 * 65536, 2 * fs],
          let l = lineOf (AdjustStaged [] [[WordSpaceGlue]]) (naturalOf its - d) its
        ],
    testCase "A2: the last item ends where it does by one ratio" $
      sequence_
        [ abs (lineEnd l - lineEnd l {lineAdjustOrder = AdjustUniform}) <= 1 @? show d
        | let its = [boxOf fs, wordSpace, boxOf fs, commaSpace fs, boxOf fs, jwSpace fs, boxOf fs, charSpace fs, boxOf fs],
          d <- [-fs, -65536, -1, 1, 65536, fs, 3 * fs],
          let l = lineOf defaultOrder (naturalOf its + d) its
        ]
  ]

-- * every small input

-- | The three orders of the test design: the default, its stages reversed, and every kind in one stage.
staged :: [AdjustOrder]
staged =
  [ defaultOrder,
    AdjustStaged (reverse (aoShrink defaultOrder)) (reverse (aoStretch defaultOrder)),
    AdjustStaged [named] [named]
  ]
  where
    named = [k | k <- [minBound .. maxBound], k /= OtherGlue]

-- | The stage of a kind in an order, the kinds of no stage after every stage.
stageIn :: [[GlueKind]] -> GlueKind -> Int
stageIn order k = case [i | (i, ks) <- zip [0 :: Int ..] order, k `elem` ks] of
  i : _ -> i
  [] -> length order

{- | A3 to A6 of a set line of an order: the amounts within the limits,
each stage used up before the next, the glue of a stage in proportion to
its limit, and the last stage widening each glue by as many em. A line
with the glue of the end of a paragraph stretches as by one ratio and is
left out.
-}
stageBreaches :: Line -> [String]
stageBreaches l =
  case lineAdjustOrder l of
    AdjustStaged shrinkOrder stretchOrder
      | not (any ((>= filStretch) . itemStretch) gs) ->
          let shrinking = any (< 0) as
              order = if shrinking then shrinkOrder else stretchOrder
              limitOf = num . (if shrinking then itemShrink else itemStretch)
              ks = map (stageIn order . itemKind) gs
              rows = zip3 gs as ks
              lastStage = not shrinking && sum as > sum (map (num . itemStretch) gs)
              mag a = if shrinking then negate a else a
           in [ "A3 " <> show (g, a)
              | (g, a, _) <- rows,
                if shrinking then a < negate (limitOf g) || a > 0 else a < 0 || (not lastStage && a > limitOf g)
              ]
                <> [ "A4 " <> show (g, a, h, b)
                   | not lastStage,
                     (g, a, k) <- rows,
                     mag a > 0,
                     (h, b, k') <- rows,
                     k' < k,
                     mag b /= limitOf h
                   ]
                <> ["A4 last " <> show (g, a) | lastStage, (g, a, _) <- rows, itemStretch g > 0, a < limitOf g]
                <> [ "A5 " <> show (g, a, h, b)
                   | not lastStage,
                     (g, a, k) <- rows,
                     (h, b, k') <- rows,
                     k == k',
                     a * limitOf h /= b * limitOf g
                   ]
                <> [ "A6 " <> show (g, a, h, b)
                   | lastStage,
                     (g, a, _) <- rows,
                     itemStretch g > 0,
                     itemZw g > 0,
                     (h, b, _) <- rows,
                     itemStretch h > 0,
                     itemZw h > 0,
                     (a - limitOf g) * num (itemZw h) /= (b - limitOf h) * num (itemZw g)
                   ]
    _ -> []
  where
    gs = [g | g@Glue {} <- lineItems l]
    as = glueAmounts l
    num = toRational . unSp

{- | A1 to A6 of the inputs of a run of docs/adr/0209 in lines up to a
width, in the orders given: each pulling in first, as golem-typeset
breaks by default, broken with one ratio and with each order.
-}
orderMisses :: [AdjustOrder] -> Int -> [Text] -> [Violation]
orderMisses orders maxWidth run =
  [ Violation rule (show (gSetting g, gPre g, gPost g, w, e, o) <> ": " <> why)
  | g <- normalGroups maxWidth run,
    let its = itemsOf False (gSetting g) (gPre g) (gRun g) (gPost g),
    (w, e) <- gCases g,
    let ps = (paramsOf (gSetting g) e its) {pPullInFirst = True}
        breaksWith o = breakParagraph ps {pAdjustOrder = o} (const (fromIntegral w * fs)) its
        uniform = breaksWith AdjustUniform,
    o <- orders,
    let br = breaksWith o,
    (rule, why) <-
      [("A1", show (brPositions br, brDemerits br, brPass br)) | (brPositions br, brDemerits br, brPass br) /= (brPositions uniform, brDemerits uniform, brPass uniform)]
        <> [ ("A2", "line " <> show (i :: Int) <> " ends at " <> show (lineEnd l) <> ", not " <> show (lineEnd u))
           | (i, l, u) <- zip3 [0 ..] (brLines br) (brLines uniform),
             abs (lineEnd l - lineEnd u) > 1
           ]
        <> [(take 2 b, "line " <> show (i :: Int) <> ": " <> b) | (i, l) <- zip [0 ..] (brLines br), b <- stageBreaches l]
  ]

-- | The depth: GOLEM_ENUM_LINES_DEPTH, or 'linesPrDepth' (docs/adr/0209).
ordersDepth :: IO Int
ordersDepth =
  lookupEnv "GOLEM_ENUM_LINES_DEPTH" >>= \case
    Just v | Just n <- readMaybe v -> pure n
    _ -> pure linesPrDepth

{- | The orders and the widest line the enumeration checks at a depth: past
'linesPrDepth' (the nightly job) the three orders of the test design in
lines up to 5 em; on pull requests the default order alone in lines up to
4 em, the default composition (docs/adr ADR 0281, its section 3). The
other orders are values moved to the nightly job (docs/adr/0278, its test
design). Timed as docs/adr ADR 0281 asks, the three orders back on pull
requests keep the area within its 10 seconds (7.33 to 9.20) but take the
sum of the areas past its 30 (30.67 to 39.46), so they stay on the
nightly job (its section 7).
-}
ordersAt :: Int -> ([AdjustOrder], Int)
ordersAt depth = if depth > linesPrDepth then (staged, 5) else ([defaultOrder], 4)

enumerationTests :: [TestTree]
enumerationTests =
  [ testCase "A1 to A6: every input up to 2 parts, broken with an order, breaks as with one ratio, its lines end where they do with it, and spread their glue in stages: the default order in lines up to 4 em on pull requests, and also the default reversed and every kind in one stage in lines up to 5 em in the nightly job" $ do
      (orders, width) <- ordersAt <$> ordersDepth
      checkAllPar 2 runsT (orderMisses orders width) @?= Passed (length (concat (upTo 2 runsT)))
  ]
