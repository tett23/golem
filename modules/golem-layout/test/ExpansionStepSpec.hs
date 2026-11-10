{- | The steps of the glyph expansion never put a line past its target
(golem-layout ADR 0029): a line that shrinks is expanded by the ratio
times the limit rounded up to a multiple of the step, a line that
stretches by it rounded towards 0, and the limit is the multiple of the
step at or below it (E1 to E6).
-}
module ExpansionStepSpec (expansionStepTests) where

import Fixtures (look0)
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (noBoxSource)
import LineBreakEnum (Input (..), Setting (..), breakInput)
import LineBreakInvariants (lineEnd)
import Test.Tasty
import Test.Tasty.HUnit

-- | A box of Latin text, which takes the glyph expansion, of a width in sp.
word :: Sp -> Item
word w = Box w (BoxContent "w" True 0 0 0 look0 0 0 [] 0 0 noBoxSource Nothing noLeaf 0)

-- | The end of a paragraph: no break, the glue that fills the last line, the forced break.
finish :: [Item]
finish = [Penalty 0 infPenalty NoHyphen, glue 0 filStretch 0, Penalty 0 (negate infPenalty) NoHyphen]

-- | The items given as the first line, a forced break, then a last line of one small box.
firstLine :: [Item] -> [Item]
firstLine its = its <> [Penalty 0 (negate infPenalty) NoHyphen, word 10] <> finish

-- | The first line of the items given as 'firstLine', broken in lines of the width given.
lineOf :: Maybe (Int, Int) -> Sp -> [Item] -> Line
lineOf e w its = case brLines (breakParagraph defaultParams {pExpansion = e} (const w) (firstLine its)) of
  l : _ -> l
  [] -> error "no line"

expansionStepTests :: TestTree
expansionStepTests =
  testGroup
    "the steps of the glyph expansion (golem-layout ADR 0029)"
    [ testCase "E2, E3: hyphenation. in lines of 5 em, with protrusion and the expansion of 20 and 5, ends within W and its protrusion" $ do
        let (_, _, br) = breakInput (Input (Setting True False True Nothing) True 5 0 ["hyphenation", "."] 0)
            w = 5 * 655360
        mapM_
          (\l -> assertBool ("past W: " <> show l) (lineOverfull l || lineEnd l <= w + snd (lineProtrusion l) + 1))
          (brLines br)
        assertBool "a line shrinks" (any ((< 0) . lineExpansion) (brLines br)),
      testCase "E3: a line that shrinks rounds the expansion up, and its glue shrinks by no more than the ratio of the line" $ do
        -- 5000 + 100 + 5000 in 9900: a ratio of −200 / 250, −16 permille rounded up to −20; the glue does not shrink
        let l = lineOf (Just (20, 5)) 9900 [word 5000, glue 100 0 50, word 5000]
        lineExpansion l @?= -20
        lineOverfull l @?= False
        assertBool "the glue shrinks more than the line" (glueRatio l >= lineRatio l)
        assertBool "past W" (lineEnd l <= 9900),
      testCase "E1, E5: with a limit of 22 and a step of 5, a line that needs 21 permille is overfull, one that needs 20 is not" $ do
        let needs21 = lineOf (Just (22, 5)) 9790 [word 10000]
            needs20 = lineOf (Just (22, 5)) 9800 [word 10000]
        (lineOverfull needs21, lineOverflow needs21, lineExpansion needs21) @?= (True, 10, -20)
        (lineOverfull needs20, lineExpansion needs20) @?= (False, -20),
      testCase "E1: with a limit of 3 and a step of 5, or a step of 0, no line is expanded, and a line that would need it is overfull" $ do
        let lines' e = [lineOf e t [word 10000] | t <- [9970, 9997, 10000, 10030]]
        map lineExpansion (lines' (Just (3, 5))) @?= [0, 0, 0, 0]
        map lineExpansion (lines' (Just (20, 0))) @?= [0, 0, 0, 0]
        map lineOverfull (lines' (Just (3, 5))) @?= [True, True, False, False]
        map lineOverfull (lines' (Just (20, 0))) @?= [True, True, False, False],
      testCase "E4: a line that stretches rounds the expansion towards 0, as before" $ do
        let l = lineOf (Just (20, 5)) 10120 [word 10000]
        lineExpansion l @?= 10,
      testCase "E6: a line of one word with no glue that stretches is short of W by less than a step" $ do
        -- 12 permille to shrink, rounded up to 15: 30 sp short, a step is 50
        let shrunk = lineOf (Just (20, 5)) 9880 [word 10000]
        lineExpansion shrunk @?= -15
        lineOverfull shrunk @?= False
        assertBool ("past W: " <> show (lineEnd shrunk)) (lineEnd shrunk <= 9880)
        assertBool ("short by a step: " <> show (lineEnd shrunk)) (lineEnd shrunk > 9880 - 50)
        -- 12 permille to stretch, rounded down to 10: 20 sp short
        let stretched = lineOf (Just (20, 5)) 10120 [word 10000]
        assertBool ("short by a step: " <> show (lineEnd stretched)) (lineEnd stretched > 10120 - 50 && lineEnd stretched <= 10120)
    ]
