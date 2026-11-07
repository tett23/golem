{- | Tests of "Golem.TestSupport.Enum" (docs/adr/0204), after the tests
of LeanCheck (test/tiers.hs and the sizes of its operators): the tiers
of the base enumerations, the sizes of the tiers of sums and products,
no value twice and none missing, 'checkAll' returning the smallest
value, and 'upTo' never evaluating the tiers after its bound.
-}
module EnumSpec (enumTests) where

import Control.Exception (evaluate)
import Control.Monad (replicateM)
import Data.List (nub, sort)
import Golem.TestSupport.Enum
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

enumTests :: TestTree
enumTests =
  testGroup
    "enumerations of small values (docs/adr/0204)"
    [ baseTests,
      sizeTests,
      exhaustiveTests,
      checkAllTests,
      lazinessTests
    ]

-- | The sizes of the tiers up to n.
sizes :: Int -> Tiers a -> [Int]
sizes n = map length . upTo n

-- | The sum of two lists of sizes, tier by tier.
plus :: [Int] -> [Int] -> [Int]
plus (a : as) (b : bs) = a + b : plus as bs
plus as [] = as
plus [] bs = bs

-- | The sizes of the product: tier k adds up a_i * b_(k - i).
convolve :: [Int] -> [Int] -> [Int]
convolve as bs =
  [ sum [a * b | (i, a) <- zip [0 ..] as, let j = k - i, j >= 0, j < length bs, let b = bs !! j]
  | k <- [0 .. length as + length bs - 2]
  ]

-- | Enumerations with tiers of several sizes, some of them empty.
samples :: [(String, Tiers Int)]
samples =
  [ ("intsIn 0 3", intsIn 0 3),
    ("one value", value 7),
    ("tiers with a gap", Tiers [[1, 2], [], [3, 4, 5]]),
    ("lengths of lists of bools", mapT length (listsOf bools)),
    ("filtered", filterT even (intsIn 0 9))
  ]

baseTests :: TestTree
baseTests =
  testGroup
    "the base enumerations"
    [ testCase "the tiers of Bool are [[False, True]]" $
        upTo 5 bools @?= [[False, True]],
      testCase "intsIn 0 3 has 0, 1, 2 and 3 in tiers of their own" $
        upTo 10 (intsIn 0 3) @?= [[0], [1], [2], [3]],
      testCase "intsIn 3 8 starts at size 0 with 3" $
        upTo 10 (intsIn 3 8) @?= [[3], [4], [5], [6], [7], [8]],
      testCase "intsIn of an empty range has no value" $
        upTo 3 (intsIn 2 1) @?= [],
      testCase "one value is in tier 0" $
        upTo 3 (value 'x') @?= ["x"],
      testCase "the lists of Bool, by length" $
        upTo 2 (listsOf bools) @?= [[[]], [[False], [True]], [[False, False], [False, True], [True, False], [True, True]]],
      testCase "the lists of a given length are as large as their elements" $
        upTo 3 (listsOfLength 2 (intsIn 0 1)) @?= [[[0, 0]], [[0, 1], [1, 0]], [[1, 1]]],
      testCase "the lists of length 0 are one empty list" $
        upTo 3 (listsOfLength 0 bools) @?= [[[]]],
      testCase "cons1 makes a value one larger than its field" $
        upTo 3 (cons1 Just (intsIn 0 1)) @?= [[], [Just 0], [Just 1]],
      testCase "cons2 makes a value one larger than the sum of its fields" $
        upTo 4 (cons2 (,) (intsIn 0 1) (intsIn 0 1)) @?= [[], [(0, 0)], [(0, 1), (1, 0)], [(1, 1)]],
      testCase "cons3 and cons4 add one to the sum of their fields" $ do
        upTo 2 (cons3 (,,) bools bools (intsIn 0 1)) @?= [[], [(a, b, 0) | a <- [False, True], b <- [False, True]], [(a, b, 1) | a <- [False, True], b <- [False, True]]]
        sizes 6 (cons4 (,,,) (intsIn 0 1) (intsIn 0 1) (intsIn 0 1) (intsIn 0 1)) @?= [0, 1, 4, 6, 4, 1],
      testCase "mapT keeps the tiers" $
        upTo 3 (mapT (* 10) (intsIn 0 2)) @?= [[0], [10], [20]],
      testCase "filterT keeps the tier of each value it keeps" $
        upTo 4 (filterT odd (intsIn 0 4)) @?= [[], [1], [], [3], []],
      testCase "the sum puts each tier of the left before the same tier of the right" $
        upTo 3 (Tiers [[1], [2]] \/ Tiers [[10], [], [30 :: Int]]) @?= [[1, 10], [2], [30]],
      testCase "the product puts the pairs of the smaller left part first" $
        upTo 2 (intsIn 0 2 >< intsIn 0 2) @?= [[(0, 0)], [(0, 1), (1, 0)], [(0, 2), (1, 1), (2, 0)]]
    ]

sizeTests :: TestTree
sizeTests =
  testGroup
    "the sizes of the tiers"
    [ testCase "the lists of Bool have 1, 2, 4 and 8 values in tiers 0 to 3" $
        sizes 3 (listsOf bools) @?= [1, 2, 4, 8],
      testCase "the lists of Bool of length n are 2 to the n, all in tier 0" $
        mapM_ (\n -> (n, sizes 4 (listsOfLength n bools)) @?= (n, [2 ^ n])) [0 .. 6],
      testCase "the sizes of the lists of Bool up to length n add up to 2 to the n + 1, less one" $
        mapM_ (\n -> (n, sum (sizes n (listsOf bools))) @?= (n, 2 ^ (n + 1) - 1)) [0 .. 8],
      testCase "the tiers of a sum are the sums of the tiers" $
        mapM_
          (\((na, a), (nb, b)) -> (na, nb, sizes 6 (a \/ b)) @?= (na, nb, plus (sizes 6 a) (sizes 6 b)))
          [(x, y) | x <- samples, y <- samples],
      testCase "the tiers of a product are the convolution of the tiers" $
        mapM_
          (\((na, a), (nb, b)) -> (na, nb, sizes 6 (a >< b)) @?= (na, nb, take 7 (convolve (sizes 6 a) (sizes 6 b))))
          [(x, y) | x <- samples, y <- samples]
    ]

exhaustiveTests :: TestTree
exhaustiveTests =
  testGroup
    "no value twice, none missing"
    [ testCase "no tier of the lists of intsIn 0 2 holds a value twice, and no value is in two tiers" $ do
        let ts = upTo 6 (listsOf (intsIn 0 2))
        mapM_ (\t -> length (nub t) @?= length t) ts
        length (nub (concat ts)) @?= length (concat ts),
      testCase "the lists of intsIn 0 2 up to tier 6 are those built naively, each in the tier of its size" $ do
        let ts = upTo 6 (listsOf (intsIn 0 2))
            naive k = [xs | len <- [0 .. k], xs <- replicateM len [0 .. 2], len + sum xs == k]
        mapM_ (\k -> (k, sort (ts !! k)) @?= (k, sort (naive k))) [0 .. 6],
      testCase "the triples of cons3 over intsIn 0 3 are those built naively" $ do
        let ts = upTo 8 (cons3 (,,) (intsIn 0 3) (intsIn 0 3) (intsIn 0 3))
            naive k = [(a, b, c) | a <- [0 .. 3], b <- [0 .. 3], c <- [0 .. 3], 1 + a + b + c == k]
        mapM_ (\k -> (k, sort (ts !! k)) @?= (k, sort (naive k))) [0 .. 8]
        length (nub (concat ts)) @?= length (concat ts),
      testCase "the lists of length 3 of intsIn 0 3 are every such list, once" $ do
        let vs = concat (upTo 20 (listsOfLength 3 (intsIn 0 3)))
        sort vs @?= sort (replicateM 3 [0 .. 3]),
      testCase "a sum of disjoint enumerations holds each value once" $ do
        let vs = concat (upTo 10 (mapT Left (intsIn 0 4) \/ mapT Right (listsOf bools)))
        length (nub vs) @?= length (vs :: [Either Int [Bool]])
    ]

checkAllTests :: TestTree
checkAllTests =
  testGroup
    "checkAll"
    [ testCase "the first value with violations of the smallest tier is returned" $ do
        let longOrTrue xs = [Violation "long" (show xs) | length xs >= 2, or xs]
        checkAll 5 (listsOf bools) longOrTrue @?= Failed 2 [False, True] [Violation "long" "[False,True]"],
      testCase "the same bound gives the same value every time" $ do
        let p xs = [Violation "sum" "" | sum xs >= 5]
            r = checkAll 8 (listsOf (intsIn 0 3)) p
        r @?= checkAll 8 (listsOf (intsIn 0 3)) p
        failedValue r @?= [2, 3],
      testCase "no value is checked past the bound" $
        checkAll 2 (intsIn 0 9) (\x -> [Violation "big" "" | x > 2]) @?= Passed 3,
      testCase "with no violations, every value up to the bound is counted" $
        checkAll 4 (listsOf bools) (const []) @?= Passed (1 + 2 + 4 + 8 + 16),
      testCase "all the violations of the value are returned, in order" $
        checkAll 3 (intsIn 0 3) (\x -> [Violation r "" | x == 1, r <- ["a", "b"]]) @?= Failed 1 1 [Violation "a" "", Violation "b" ""]
    ]

lazinessTests :: TestTree
lazinessTests =
  testGroup
    "upTo evaluates no tier past its bound"
    [ testCase "the tiers after the bound may be undefined" $ do
        let t = Tiers ([[1], [2], [3 :: Int]] <> error "evaluated a tier past the bound")
        n <- evaluate (length (concat (upTo 2 t)))
        n @?= 3,
      testCase "nor through a sum, a product, a filter and a map" $ do
        let t = Tiers ([[1], [2], [3 :: Int]] <> error "evaluated a tier past the bound")
        n <- evaluate (length (concat (upTo 2 (mapT (+ 1) (filterT odd (t \/ t))))))
        n @?= 4
        m <- evaluate (length (concat (upTo 2 (t >< t))))
        m @?= 6,
      testCase "an infinite enumeration stops at the bound" $ do
        n <- evaluate (length (concat (upTo 12 (listsOf bools))))
        n @?= 2 ^ (13 :: Int) - 1
        assertBool "checkAll stops" (checkAll 10 (listsOf (intsIn 0 1)) (const []) == Passed (length (concat (upTo 10 (listsOf (intsIn 0 1))))))
    ]
