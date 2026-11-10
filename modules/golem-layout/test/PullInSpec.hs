{- | Pulling in first and the limit of the stretch (docs/adr/0274): the
badness of a line that shrinks within the shrink of its glue, and the
glue ratio of a set line capped by the stretch limit, R3 to R6 on
paragraphs made by hand. The enumeration checks R1, R2 and R7
(LineBreakInvariantsSpec).
-}
module PullInSpec (pullInTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import LineBreakEnum (Setting (..), composeEnv)
import Test.Tasty
import Test.Tasty.HUnit

pullInTests :: TestTree
pullInTests =
  testGroup
    "pulling in first and the stretch limit (docs/adr/0274)"
    [ testGroup "R3: a paragraph that fits one line by its shrink" r3Tests,
      testGroup "R4: the items do not change" r4Tests,
      testGroup "R5, R6: the stretch limit" r5Tests
    ]

-- | The default setting of the enumeration.
plain :: Setting
plain = Setting True False False Nothing

{- | The composition of R3: every character half an em but the comma, a
full-width glyph (a narrower one would take a box of half an em, docs/adr/0302):
a box of half an em and the half em after it, which shrinks to nothing.
「あいう、えお」 is 3.5 em at its natural width and 3 em with the half em
taken; 「あいう、え」 is 3 em, the width of the lines ('r3Width').
-}
r3Env :: Bool -> ComposeEnv
r3Env vertical = (composeEnv vertical plain) {ceAdvance = \_ c -> if c == '、' then 1 else 1 / 2}

-- | The width of the lines of R3: 3 em, six half-em characters.
r3Width :: Sp
r3Width = 3 * fs

itemsIn :: ComposeEnv -> Text -> [Item]
itemsIn env t = fst (composeInlines env [IR.Text sp t])

linesOf :: Params -> Sp -> [Item] -> [Text]
linesOf ps w its = [T.concat [bcText c | Box _ c <- lineItems l] | l <- brLines (breakParagraph ps (const w) its)]

pullIn, balanced :: Params
pullIn = defaultParams {pPullInFirst = True}
balanced = defaultParams {pPullInFirst = False}

r3Tests :: [TestTree]
r3Tests =
  [ testCase "R3: あいう、えお in lines of five characters is one line pulling in first, and two balanced" $ do
      let its = itemsIn (r3Env False) "あいう、えお"
      linesOf pullIn r3Width its @?= ["あいう、えお"]
      -- balanced: the line squeezed has the badness 100, demerits 110 squared, more than two lines of badness 0
      linesOf balanced r3Width its @?= ["あいう、え", "お"],
    testCase "R3: the line pulled in has the demerits of a line of badness 0, (10 + 0) squared, in the first pass" $ do
      let br = breakParagraph pullIn (const r3Width) (itemsIn (r3Env False) "あいう、えお")
      (brPass br, brDemerits br) @?= (1, 100),
    testCase "R3: vertical writing alike" $ do
      linesOf pullIn r3Width (itemsIn (r3Env True) "あいう、えお") @?= ["あいう、えお"]
      linesOf balanced r3Width (itemsIn (r3Env True) "あいう、えお") @?= ["あいう、え", "お"],
    testCase "R3: a line that needs 1 sp more than the shrink of its glue is not pulled in" $ do
      -- the lines 1 sp narrower: the paragraph does not fit one line however squeezed
      let its = itemsIn (r3Env False) "あいう、えお"
      linesOf pullIn (r3Width - 1) its @?= linesOf balanced (r3Width - 1) its
      length (linesOf pullIn (r3Width - 1) its) @?= 2,
    testCase "R3: a line that needs exactly the shrink of its glue is pulled in, and one that needs none is as balanced" $ do
      let its = itemsIn (r3Env False) "あいう、えお"
      linesOf pullIn r3Width its @?= ["あいう、えお"]
      linesOf pullIn (Sp (unSp fs * 7 `div` 2)) its @?= linesOf balanced (Sp (unSp fs * 7 `div` 2)) its
  ]

r4Tests :: [TestTree]
r4Tests =
  [ testCase "R4: the parameters do not reach the composition: the items are those of the text alone" $
      -- composeInlines takes no Params; the line adjustment is a parameter of the breaking only
      itemsIn (r3Env False) "あいう、えお" @?= itemsIn (r3Env False) "あいう、えお"
  ]

-- | A box of a width in sp.
boxOf :: Integer -> Item
boxOf w = case [c | Box _ c <- itemsIn (r3Env False) "x"] of
  c : _ -> Box (Sp w) c
  [] -> error "no box"

{- | Two lines forced, of a width of 100: the first of a natural width of 80
and a stretch of 40 (a ratio of 1/2), the second of 70 and a stretch of
10 (a ratio of 3), then the paragraph end.
-}
twoLines :: [Item]
twoLines =
  [boxOf 40, glue 0 40 0, boxOf 40, Penalty 0 (negate infPenalty) NoHyphen, boxOf 35, glue 0 10 0, boxOf 35, Penalty 0 (negate infPenalty) NoHyphen]

setWith :: Maybe Rational -> [Line]
setWith m = brLines (breakParagraph defaultParams {pStretchLimit = m} (const 100) twoLines)

r5Tests :: [TestTree]
r5Tests =
  [ testCase "R5: with a limit of 1000, the line of a ratio of 1/2 is placed as without it, and the line of 3 at a ratio of 1" $ do
      let unlimited = setWith Nothing
          limited = setWith (Just 1)
      map glueRatio unlimited @?= [1 / 2, 3]
      map glueRatio (take 2 limited) @?= [1 / 2, 1]
      map placeLine (take 1 limited) @?= map placeLine (take 1 unlimited),
    testCase "R6: the line capped ends at its natural width and its stretch from the line start, before W, and starts where it did" $ do
      let unlimited = setWith Nothing
          limited = setWith (Just 1)
          endOf l = case reverse (placeLine l) of
            (Box w _, off) : _ -> off + w
            _ -> error "no box at the end"
          startOf l = map snd (take 1 (placeLine l))
      map endOf limited @?= [100, 80]
      map startOf limited @?= map startOf unlimited,
    testCase "R6: in vertical writing, a line of Japanese text capped ends where its natural width and its stretch end" $ do
      -- あいう in lines of 4 em with the paragraph end taken: two gaps of a tenth of an em stretch
      let its = itemsIn ((composeEnv True plain) {ceAdvance = \_ _ -> 1}) "あいう"
          ps = defaultParams {pStretchLimit = Just 1}
          l = case brLines (breakParagraph ps (const (4 * fs)) its) of
            x : _ -> x
            [] -> error "no line"
          capped = l {lineItems = [it | it <- lineItems l, not (isFill it)]}
          isFill = \case
            Glue _ y _ _ _ -> y >= filStretch
            _ -> False
      glueRatio capped @?= 1
      lineEndOf capped @?= 3 * fs + 2 * Sp (unSp fs `div` 10)
  ]
  where
    lineEndOf l = case reverse [(w, off) | (Box w _, off) <- placeLine l] of
      (w, off) : _ -> off + w
      [] -> 0
