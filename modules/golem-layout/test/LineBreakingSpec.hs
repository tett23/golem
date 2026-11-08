{- | Invariants of Knuth–Plass line breaking (golem-layout ADR 0001) as
properties: when every word fits the measure, no line is overfull and
no set line reaches past its target length.
-}
module LineBreakingSpec (lineBreakingTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs)
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (noBoxSource)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import KnuthPlassReference (finish, referenceLook)
import LineBreakEnum (Input (..), Setting (..), advance, breakInput, itemsOf, lineText)
import Golem.Length qualified as L
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

-- | Words of the given widths separated by glue of width 6, stretch 3 and shrink 2.
paragraph :: [Sp] -> [Item]
paragraph ws = concat [Box w (BoxContent "w" False 0 0 0 referenceLook 0 0 [] 0 0 noBoxSource Nothing noLeaf 0) : [Glue 6 3 2 | i < length ws - 1] | (i, w) <- zip [0 :: Int ..] ws] <> finish

-- | Where the last box of a set line ends.
lastBoxEnd :: Line -> Sp
lastBoxEnd l = maximum (0 : [x + w | (Box w _, x) <- placeLine l])

-- | A length from @lo@ to @hi@ sp.
genSp :: Sp -> Sp -> Gen Sp
genSp lo hi = Sp <$> Gen.integral (Range.linear (unSp lo) (unSp hi))

-- | A paragraph whose words all fit a measure of 60 to 200.
genFitting :: Gen ([Sp], Sp)
genFitting = do
  target <- genSp 60 200
  ws <- Gen.list (Range.linear 1 25) (genSp 1 target)
  pure (ws, target)

-- | A paragraph with at least one word wider than the measure of 60 to 200 (docs/adr/0067).
genWithWide :: Gen ([Sp], Sp)
genWithWide = do
  target <- genSp 60 200
  ws <- Gen.list (Range.linear 0 12) (genSp 1 (2 * target))
  wide <- genSp (target + 1) (3 * target)
  at <- Gen.int (Range.linear 0 (length ws))
  let (before, rest) = splitAt at ws
  pure (before <> [wide] <> rest, target)

lineBreakingTests :: TestTree
lineBreakingTests =
  testGroup
    "line breaking invariants (golem-layout ADR 0001)"
    [ testProperty "when every word fits the measure, no line is overfull" $ property $ do
        (ws, target) <- forAll genFitting
        let r = breakParagraph defaultParams (const target) (paragraph ws)
        filter lineOverfull (brLines r) === [],
      testProperty "when every word fits the measure, no set line ends past it" $ property $ do
        (ws, target) <- forAll genFitting
        let r = breakParagraph defaultParams (const target) (paragraph ws)
        filter (> target) (map lastBoxEnd (brLines r)) === [],
      testProperty "the lines hold every word once, in order" $ property $ do
        (ws, target) <- forAll genFitting
        let r = breakParagraph defaultParams (const target) (paragraph ws)
        [w | l <- brLines r, Box w _ <- lineItems l] === ws,
      testProperty "with a word wider than the measure, the lines still hold every word once, in order" $ property $ do
        (ws, target) <- forAll genWithWide
        let r = breakParagraph defaultParams (const target) (paragraph ws)
        [w | l <- brLines r, Box w _ <- lineItems l] === ws,
      kinsokuTests
    ]

-- | The setting of the defaults: strict kinsoku, no hanging, no protrusion, no span.
plain :: Setting
plain = Setting True False False Nothing

-- | The lines of a run in the setting given, in lines of the width given in em.
linesIn :: Setting -> Int -> [Text] -> [Text]
linesIn s w run = let (_, _, br) = breakInput (Input s False w 0 run 0) in map lineText (brLines br)

-- | The items of a run, a box as its text, glue as its widths, a penalty as its value and kind.
shapes :: Setting -> [Text] -> [String]
shapes s run = map shape (itemsOf False s 0 run 0)
  where
    shape = \case
      Box _ c -> T.unpack (bcText c)
      Glue w y z -> "_" <> show (unSp w, unSp y, unSp z)
      Penalty _ p h -> "|" <> show p <> case h of
        PatternHyphen _ -> "P"
        ExplicitHyphen -> "E"
        NoHyphen -> ""

-- | The glue that fills the last line.
fil :: String
fil = "_" <> show (0 :: Integer, unSp filStretch, 0 :: Integer)

-- | The glue of a space between Latin words in the advances of the tests.
space :: String
space = let sw = L.zwToSp fs (advance True ' ') in "_" <> show (unSp sw, unSp sw `div` 2, unSp sw `div` 3)

{- | Kinsoku across a space between words and the break after a hyphen
or a dash written in a word (golem-layout ADR 0028), on lines of 2 em.
-}
kinsokuTests :: TestTree
kinsokuTests =
  testGroup
    "kinsoku across spaces and written hyphens (golem-layout ADR 0028)"
    [ testCase "K2: あ「 いい does not end a line with 「 at the space after it" $
        linesIn plain 2 ["あ", "「", " ", "い", "い"] @?= ["あ", "「い", "い"],
      testCase "K1: あ 〜 does not start a line with 〜 at the space before it" $
        linesIn plain 2 ["あ", " ", "〜"] @?= ["あ〜"],
      testCase "K4: … … may break at the space between the two ellipses" $
        linesIn plain 2 ["あ", "…", " ", "…"] @?= ["あ…", "…"],
      testCase "K3: …—… in a span of en does not break between the dash and the ellipsis" $
        linesIn plain {sLang = Just "en"} 2 ["あ", "…", "—", "…"] @?= ["あ", "…—…"],
      testCase "K1: …—” in a span of en does not start a line with ” after the dash" $
        linesIn plain {sLang = Just "en"} 2 ["あ", "…", "—", "”"] @?= ["あ", "…—”"],
      testCase "K1: a—” out of a span does not start a line with ” after the dash" $
        linesIn plain 2 ["あ", "a", "—", "”"] @?= ["あ", "a—”"],
      testCase "K5: “ a and a ” break as the opening and the closing quotation mark, in no span, en and ja" $
        sequence_
          [ do
              linesIn plain {sLang = l} 2 ["あ", "あ", "“", " ", "a"] @?= ["ああ", "“a"]
              linesIn plain {sLang = l} 2 ["あ", "a", " ", "”"] @?= ["あ", "a”"]
          | l <- [Nothing, Just "en", Just "ja"]
          ],
      testCase "K6: the items of a space and of a written hyphen no prohibition applies to are as before" $ do
        shapes plain ["a", " ", "table"] @?= ["a", space, "ta", "|50P", "ble", "|10000", fil, "|-10000"]
        shapes plain ["lime-tree"] @?= ["lime-", "|50E", "tree", "|10000", fil, "|-10000"],
      testCase "K7: where a space is no longer a break, it is the only glue between the two characters" $
        -- the space of the paragraph start before 「, as before
        take 4 (drop 1 (shapes plain ["「", " ", "a"])) @?= ["「", "|10000", space, "a"]
    ]
