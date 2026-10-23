{- | Invariants of Knuth–Plass line breaking (golem-layout ADR 0001) as
properties: when every word fits the measure, no line is overfull and
no set line reaches past its target length.
-}
module LineBreakingSpec (lineBreakingTests) where

import Golem.Layout.KnuthPlass
import Golem.Layout.Look (noBoxSource)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import KnuthPlassReference (finish, referenceLook)
import Test.Tasty
import Test.Tasty.Hedgehog (testProperty)

-- | Words of the given widths separated by glue of width 6, stretch 3 and shrink 2.
paragraph :: [Sp] -> [Item]
paragraph ws = concat [Box w (BoxContent "w" False 0 0 0 referenceLook 0 0 [] 0 0 noBoxSource) : [Glue 6 3 2 | i < length ws - 1] | (i, w) <- zip [0 :: Int ..] ws] <> finish

-- | Where the last box of a set line ends.
lastBoxEnd :: Line -> Sp
lastBoxEnd l = maximum (0 : [x + w | (Box w _, x) <- placeLine l])

-- | A paragraph whose words all fit a measure of 60 to 200.
genFitting :: Gen ([Sp], Sp)
genFitting = do
  target <- Gen.integral (Range.linear 60 200)
  ws <- Gen.list (Range.linear 1 25) (Gen.integral (Range.linear 1 target))
  pure (ws, target)

-- | A paragraph with at least one word wider than the measure of 60 to 200 (docs/adr/0067).
genWithWide :: Gen ([Sp], Sp)
genWithWide = do
  target <- Gen.integral (Range.linear 60 200)
  ws <- Gen.list (Range.linear 0 12) (Gen.integral (Range.linear 1 (2 * target)))
  wide <- Gen.integral (Range.linear (target + 1) (3 * target))
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
        [w | l <- brLines r, Box w _ <- lineItems l] === ws
    ]
