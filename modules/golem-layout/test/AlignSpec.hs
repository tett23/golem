{- | The alignment of the lines of a paragraph (docs/adr/0189): lines that
are not justified use no stretch of their glue and no expansion, and are
shifted by the difference between the line and its contents; the
justified values set every line but the last as before.
-}
module AlignSpec (alignTests) where

import Control.Monad (forM_)
import Golem.Layout.Align
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (noBoxSource)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import KnuthPlassReference (finish, referenceLook)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

box :: Sp -> Item
box w = Box w (BoxContent "w" True 0 0 0 referenceLook 0 0 [] 0 0 noBoxSource)

-- | Words of the given widths with glue of width 6, the stretch and the shrink given between them.
words' :: Sp -> Sp -> [Sp] -> [Item]
words' y z ws = concat [box w : [Glue 6 y z | i < length ws - 1] | (i, w) <- zip [0 :: Int ..] ws] <> finish

paragraph :: [Sp] -> [Item]
paragraph = words' 3 2

-- | The offsets of the boxes of a set line, shifted by its alignment.
boxesAt :: ParaAlign -> Bool -> Line -> [Sp]
boxesAt a final l = [lineShift a final l + x | (Box {}, x) <- placeLine l]

-- | Where the last box of a set line ends, unshifted.
contentEnd :: Line -> Sp
contentEnd l = maximum (0 : [x + w | (Box w _, x) <- placeLine l])

-- | Whether a glue of the set line is stretched.
stretched :: Line -> Bool
stretched l = glueRatio l > 0 && any isStretchy (lineItems l)
  where
    isStretchy = \case
      Glue _ y _ -> y > 0
      _ -> False

expanding :: Params
expanding = defaultParams {pExpansion = Just (20, 5)}

genParagraph :: Gen ([Sp], Sp)
genParagraph = do
  target <- Sp <$> Gen.integral (Range.linear 60 200)
  ws <- Gen.list (Range.linear 1 25) (Sp <$> Gen.integral (Range.linear 1 (unSp target)))
  pure (ws, target)

ragged :: [ParaAlign]
ragged = map Ragged [LineStart, LineCenter, LineEnd]

alignTests :: TestTree
alignTests =
  testGroup
    "the alignment of the lines of a paragraph (docs/adr/0189)"
    [ testProperty "a ragged paragraph stretches no glue and expands no glyph" $ property $ do
        (ws, target) <- forAll genParagraph
        a <- forAll (Gen.element ragged)
        let ls = brLines (breakAligned a expanding (const target) (paragraph ws))
        filter stretched ls === []
        map lineExpansion ls === map (const 0) ls
        [w | l <- ls, Box w _ <- lineItems l] === ws,
      testCase "a ragged line may shrink" $ do
        -- 50 + 6 + 50 = 106 is over 105 by 1; the shrink of 20 takes it at badness 0
        let ls = brLines (breakAligned (Ragged LineStart) defaultParams (const 105) (words' 3 20 [50, 50]))
        length ls @?= 1
        assertBool "shrunk" (all ((< 0) . glueRatio) ls)
        map (lineShift (Ragged LineEnd) True) ls @?= [0],
      testCase "left, center and right shift by the difference; an odd one leaves 1sp at the end" $ do
        -- 10 + 6 + 10 = 26 in 101: the difference is 75
        let ls = brLines (breakAligned (Ragged LineStart) defaultParams (const 101) (paragraph [10, 10]))
        map (boxesAt (Ragged LineStart) True) ls @?= [[0, 16]]
        map (boxesAt (Ragged LineCenter) True) ls @?= [[37, 53]]
        map (boxesAt (Ragged LineEnd) True) ls @?= [[75, 91]]
        map lineSlack ls @?= [75],
      testProperty "the lines of a ragged paragraph are of the same breaks whatever the side" $ property $ do
        (ws, target) <- forAll genParagraph
        let ls a = map lineItems (brLines (breakAligned a defaultParams (const target) (paragraph ws)))
        ls (Ragged LineCenter) === ls (Ragged LineStart)
        ls (Ragged LineEnd) === ls (Ragged LineStart),
      testProperty "every ragged line is set within its measure" $ property $ do
        (ws, target) <- forAll genParagraph
        a <- forAll (Gen.element ragged)
        let ls = brLines (breakAligned a defaultParams (const target) (paragraph ws))
        filter (\l -> lineShift a False l + contentEnd l > target) ls === [],
      testProperty "left-justified breaks and sets the lines as before" $ property $ do
        (ws, target) <- forAll genParagraph
        let before = breakParagraph expanding (const target) (paragraph ws)
            after = breakAligned (Justified (Just LineStart)) expanding (const target) (paragraph ws)
        brLines after === brLines before
        [lineShift (Justified (Just LineStart)) (i == length (brLines after) - 1) l | (i, l) <- zip [0 :: Int ..] (brLines after)] === map (const 0) (brLines after),
      testCase "center- and right-justified shift only the last line" $ do
        let ws = [30, 40, 20, 50, 30, 10, 20]
            target = 100
            base = brLines (breakParagraph defaultParams (const target) (paragraph ws))
        assertBool "more than one line" (length base > 1)
        assertBool "a short last line" (contentEnd (last base) < target)
        forM_ [(LineCenter, \s -> Sp (unSp s `div` 2)), (LineEnd, id)] $ \(la, shiftOf) -> do
          let a = Justified (Just la)
              ls = brLines (breakAligned a defaultParams (const target) (paragraph ws))
              lastIx = length ls - 1
          ls @?= base
          [boxesAt a (i == lastIx) l | (i, l) <- zip [0 ..] (init ls)] @?= [boxesAt (Justified (Just LineStart)) False l | l <- init base]
          boxesAt a True (last ls) @?= map (+ shiftOf (target - contentEnd (last base))) (boxesAt (Justified (Just LineStart)) True (last base)),
      testCase "fully-justified sets the last line as wide as the others" $ do
        let ws = [30, 40, 20, 50, 30, 10, 10, 10]
            ls = brLines (breakAligned (Justified Nothing) defaultParams (const 100) (paragraph ws))
        assertBool "more than one line" (length ls > 1)
        assertBool "a last line of words" (length [() | Box {} <- lineItems (last ls)] > 1)
        assertBool "a short last line as left-justified" (contentEnd (last (brLines (breakParagraph defaultParams (const 100) (paragraph ws)))) < 100)
        map contentEnd ls @?= map (const 100) ls
        map (lineShift (Justified Nothing) True) ls @?= map (const 0) ls,
      testCase "fully-justified keeps at the start a last line without glue to stretch" $ do
        let ls = brLines (breakAligned (Justified Nothing) defaultParams (const 100) (paragraph [60, 60]))
        length ls @?= 2
        boxesAt (Justified Nothing) True (last ls) @?= [0]
        contentEnd (last ls) @?= 60,
      testCase "a fully-justified paragraph of one short line is one line, stretched" $ do
        let ls = brLines (breakAligned (Justified Nothing) defaultParams (const 100) (paragraph [10, 10]))
        length ls @?= 1
        map contentEnd ls @?= [100]
    ]
