{- | The cases of E1 of docs/adr/0208, which both test suites of
golem-test-support check: golem-test-support-test with the workers and
parts given ('checkAllParWith'), golem-test-support-par-test with
'checkAllPar' on one and four processors.

The enumerations have tiers of 0, 1, fewer than the workers, as many as
a block holds, and one more; the predicates break on no value, on the
first value of a tier, on its last, and on two values of a tier that
fall in different parts.
-}
module EnumParCases (Case (..), parCases, tierSizes, positions) where

import Golem.TestSupport.Enum

-- | An enumeration and a predicate on it, named.
data Case = Case
  { caseName :: String,
    caseTiers :: Tiers (Int, Int),
    caseCheck :: (Int, Int) -> [Violation]
  }

{- | The sizes of the tiers: with four workers of two values each (a block
of eight), none, one, fewer than the workers, a block, a block and one,
two blocks and one; with parts of one value, a block of four.
-}
tierSizes :: [[Int]]
tierSizes = [[0, 1, 3, 8, 9, 17], [5, 4, 0, 3, 1], [0, 0, 2]]

-- | The values a predicate breaks on, by the tier and the size of the tier.
positions :: [(String, Int -> Int -> Int -> Bool)]
positions =
  [ ("no value", \_ _ _ -> False),
    ("the first value of each tier", \_ _ i -> i == 0),
    ("the last value of each tier", \_ s i -> i == s - 1),
    ("the first and the last value of tier 4", \t s i -> t == 4 && (i == 0 || i == s - 1)),
    ("the second and the seventh value of each tier", \_ _ i -> i == 1 || i == 6),
    ("a value of the second block of tier 4", \t _ i -> t == 4 && i == 8),
    ("every value from the third", \_ _ i -> i >= 2)
  ]

-- | Every enumeration with every predicate.
parCases :: [Case]
parCases =
  [ Case
      (show sizes <> ", " <> name)
      (Tiers [[(t, i) | i <- [0 .. s - 1]] | (t, s) <- zip [0 ..] sizes])
      (\(t, i) -> [Violation "broken" (show (t, i)) | breaks t (sizeOf sizes t) i] <> [Violation "also" "" | breaks t (sizeOf sizes t) i, even i])
  | sizes <- tierSizes,
    (name, breaks) <- positions
  ]
  where
    sizeOf sizes t = sizes !! t
