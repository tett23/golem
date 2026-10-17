-- | The grid lines and the places of paragraph rules (golem-driver ADR 0027).
module RuleAreaSpec (ruleAreaTests) where

import Golem.Layout.RuleArea
import Test.Tasty
import Test.Tasty.HUnit

pt :: Rational -> Integer
pt x = round (x * 65536)

-- | Size 10pt, pitch 17pt: 7pt between the em boxes of two lines.
grid :: RuleGrid
grid = RuleGrid (pt 17) (pt 10)

-- | A rule of a weight with its inner and outer spaces, written or not.
side :: Rational -> Maybe Rational -> Maybe Rational -> RuleSide
side w i o = RuleSide (maybe 0 pt i) (maybe 0 pt o) (pt w) (i /= Nothing || o /= Nothing) Nothing

ruleAreaTests :: [TestTree]
ruleAreaTests =
  [ testCase "inside a column, no spaces, 0.3pt: no line, the rule in the middle of the 7pt" $
      ruleBefore grid (side 0.3 Nothing Nothing) 0 @?= (0, (pt 7 - pt 0.3) `div` 2),
    testCase "inside a column, inner 2pt, outer 4pt, 0.5pt: 6.5pt fits in 7pt, the rule 2pt from the paragraph" $ do
      ruleBefore grid (side 0.5 (Just 2) (Just 4)) 0 @?= (0, pt 7 - pt 2 - pt 0.5)
      ruleAfter grid (side 0.5 (Just 2) (Just 4)) 0 @?= (0, pt 2),
    testCase "inside a column, inner 5pt, outer 10pt: one line; the outer space becomes 18.5pt" $ do
      let (k, at) = ruleBefore grid (side 0.5 (Just 5) (Just 10)) 0
      k @?= 1
      -- from the em box before to the rule
      at @?= pt 18.5,
    testCase "at the start of a column, inner 5pt, outer 10pt: the outer space is not counted" $
      ruleBeforeAtStart grid (side 0.5 (Just 5) (Just 10)) 0 @?= (1, pt 17 - pt 5 - pt 0.5),
    testCase "at the start of a column, out of the column: no line, 5pt out of the paragraph" $
      ruleBeforeAtStart grid (side 0.5 (Just 5) Nothing) {rsdOutside = Just (pt 20)} 0 @?= (0, negate (pt 5 + pt 0.5)),
    testCase "out of the column but over the margin: kept in the column" $
      ruleBeforeAtStart grid (side 0.5 (Just 5) Nothing) {rsdOutside = Just (pt 5)} 0 @?= (1, pt 17 - pt 5 - pt 0.5),
    testCase "at the end of a column the rule after keeps the inner space; out of the column it takes no line" $ do
      ruleAfterAtEnd grid (side 0.5 (Just 5) (Just 10)) @?= (1, pt 5)
      ruleAfterAtEnd grid (side 0.5 (Just 5) Nothing) {rsdOutside = Just (pt 20)} @?= (0, pt 5)
      -- without spaces, in the middle of the line to the edge of the column
      ruleAfterAtEnd grid (side 0.5 Nothing Nothing) @?= (1, (pt 17 - pt 0.5) `div` 2),
    testCase "rules in a row: 11pt - 7pt rounds up to one line, 6pt or more between them" $ do
      let (k, a, b) = rulesJoined grid (side 0.5 (Just 2) (Just 3)) (side 0.5 (Just 2) (Just 6)) 0
      k @?= 1
      a @?= pt 2
      b @?= pt 24 - pt 2 - pt 0.5
      assertBool "6pt between" (b - (a + pt 0.5) >= pt 6),
    testCase "rules in a row without spaces: three equal spaces, the remainder in the middle" $ do
      let (k, a, b) = rulesJoined grid (side 0.5 Nothing Nothing) (side 0.5 Nothing Nothing) 0
          rest = pt 7 - pt 1
      k @?= 0
      a @?= rest `div` 3
      b @?= rest `div` 3 + pt 0.5 + rest `div` 3 + rest `mod` 3
      (pt 7 - (b + pt 0.5)) @?= rest `div` 3,
    testCase "ruby over the first line: 12.1pt - 7pt is one line; the rule 2pt from the reading" $ do
      ruleBefore grid (side 0.5 (Just 2) (Just 4)) (pt 5.6) @?= (1, pt 24 - pt 5.6 - pt 2 - pt 0.5)
      fst (ruleBefore grid (side 0.5 (Just 2) (Just 4)) 0) @?= 0,
    testCase "ruby over the next line: no line, the rule in the middle of the 1.4pt left" $
      ruleAfter grid (side 0.3 Nothing Nothing) (pt 5.6) @?= (0, (pt 7 - pt 5.6 - pt 0.3) `div` 2),
    testCase "kenten count as ruby does" $
      fst (ruleBefore grid (side 0.5 (Just 2) (Just 4)) (pt 5)) @?= 1,
    testCase "rules in a row: the ruby of the next paragraph is added" $ do
      let (k, _, b) = rulesJoined grid (side 0.5 (Just 2) (Just 3)) (side 0.5 (Just 2) (Just 6)) (pt 5.6)
      -- 11pt + 5.6pt - 7pt = 9.6pt: one line
      k @?= 1
      b @?= pt 24 - pt 5.6 - pt 2 - pt 0.5,
    testCase "at the start of a column with ruby: 11.1pt over 17pt is one line" $
      fst (ruleBeforeAtStart grid (side 0.5 (Just 5) Nothing) (pt 5.6)) @?= 1,
    testCase "the rule after at the end of a column counts no ruby" $
      ruleAfterAtEnd grid (side 0.5 (Just 5) Nothing) @?= (1, pt 5)
  ]
