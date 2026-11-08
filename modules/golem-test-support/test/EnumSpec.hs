{- | Tests of "Golem.TestSupport.Enum" (docs/adr/0204), after the tests
of LeanCheck (test/tiers.hs and the sizes of its operators): the tiers
of the base enumerations, the sizes of the tiers of sums and products,
no value twice and none missing, 'checkAll' returning the smallest
value, and 'upTo' never evaluating the tiers after its bound.

Then the parts added by docs/adr/0208, after its invariants E1 to E4:
'checkAllPar' returning what 'checkAll' returns, 'nubTiersOn' keeping
every key once, 'sampleT' drawing the same values for the same seed, and
'shrinkList' returning a list it cannot shrink further.
-}
module EnumSpec (enumTests) where

import Control.Exception (evaluate)
import Control.Monad (replicateM)
import Data.List (nub, sort)
import Data.Word (Word64)
import EnumParCases (Case (..), parCases)
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
      lazinessTests,
      parallelTests,
      nubTests,
      sampleTests,
      shrinkTests
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

-- * docs/adr/0208

{- | The ordered list of the values checked: the count of 'tallyAll' that
shows the order, and that every value checked is counted once.
-}
checkedValues :: Case -> (Int, Int) -> ([Violation], [(Int, Int)])
checkedValues c x = (caseCheck c x, [x])

parallelTests :: TestTree
parallelTests =
  testGroup
    "E1 checkAllPar returns what checkAll returns"
    [ testCase "E1: for every number of workers and of values a part holds, every bound and every case" $
        mapM_
          ( \(c, w, k, n) ->
              (caseName c, w, k, n, checkAllParWith w k n (caseTiers c) (caseCheck c))
                @?= (caseName c, w, k, n, checkAll n (caseTiers c) (caseCheck c))
          )
          [(c, w, k, n) | c <- parCases, w <- [1 .. 4], k <- [1 .. 3], n <- [0 .. 6]],
      testCase "E1: tallyAllPar counts the values checked, in order, as tallyAll does" $
        mapM_
          ( \(c, w, k, n) ->
              (caseName c, w, k, n, tallyAllParWith w k n (caseTiers c) (checkedValues c))
                @?= (caseName c, w, k, n, tallyAll n (caseTiers c) (checkedValues c))
          )
          [(c, w, k, n) | c <- parCases, w <- [1 .. 4], k <- [1 .. 3], n <- [0 .. 6]],
      testCase "E1: tallyAll counts every value before the first with violations, and that value" $ do
        let p x = ([Violation "big" "" | x >= 2], [x])
        tallyAll 5 (intsIn 0 5) p @?= (Failed 2 2 [Violation "big" ""], [0, 1, 2])
        tallyAll 1 (intsIn 0 5) p @?= (Passed 2, [0, 1]),
      testCase "E1: checkAllPar on the processors of this program is checkAll" $
        mapM_ (\c -> (caseName c, checkAllPar 6 (caseTiers c) (caseCheck c)) @?= (caseName c, checkAll 6 (caseTiers c) (caseCheck c))) parCases,
      testCase "E1: no value is checked past the bound, nor a tier past it evaluated" $ do
        let t = Tiers ([[1], [2], [3 :: Int]] <> error "evaluated a tier past the bound")
        checkAllParWith 4 1 2 t (const []) @?= Passed 3
        checkAllParWith 2 2 2 t (\x -> [Violation "big" "" | x > 1]) @?= Failed 1 2 [Violation "big" ""]
    ]

-- | The tiers of the values whose key no value before them has, built naively.
naiveNub :: (Eq k) => (a -> k) -> Int -> Tiers a -> [[a]]
naiveNub key n xs =
  let ts = upTo n xs
      before k j = [key y | (k', t) <- zip [0 :: Int ..] ts, (j', y) <- zip [0 :: Int ..] t, k' < k || (k' == k && j' < j)]
   in [[x | (j, x) <- zip [0 ..] t, key x `notElem` before k j] | (k, t) <- zip [0 ..] ts]

nubTests :: TestTree
nubTests =
  testGroup
    "E2 nubTiersOn keeps every key once"
    [ testCase "E2: with the key the value itself, a sum or a product that holds no value twice is kept as it is" $ do
        upTo 6 (nubTiersOn id (listsOf (intsIn 0 2))) @?= upTo 6 (listsOf (intsIn 0 2))
        upTo 6 (nubTiersOn id (intsIn 0 3 >< intsIn 0 3)) @?= upTo 6 (intsIn 0 3 >< intsIn 0 3),
      testCase "E2: with a constant key, only the first value of the first tier stays" $
        upTo 4 (nubTiersOn (const ()) (listsOf bools)) @?= [[[]], [], [], [], []],
      testCase "E2: with the parity of the sum, the first even and the first odd value stay" $
        upTo 4 (nubTiersOn (even . sum) (listsOf (intsIn 0 2))) @?= [[[]], [], [[1]], [], []],
      testCase "E2: the keys and the values kept are those built naively, for every key" $
        mapM_
          (\(name, key) -> (name, upTo 6 (nubTiersOn key (listsOf (intsIn 0 2)))) @?= (name, naiveNub key 6 (listsOf (intsIn 0 2))))
          [ ("the list itself, in base 4" :: String, foldr (\x a -> a * 4 + x + 1) 0),
            ("constant", const 0),
            ("parity", (`mod` 2) . sum),
            ("the sum", sum),
            ("the length", length),
            ("the sorted values", sum . map (10 ^) . sort)
          ],
      testCase "E2: two values of the same key in the same tier, and in two tiers" $ do
        upTo 2 (nubTiersOn (`div` 2) (Tiers [[1, 2, 3 :: Int], [4, 5, 0]])) @?= [[1, 2], [4]]
        upTo 2 (nubTiersOn (`mod` 3) (Tiers [[3 :: Int], [6, 1, 4, 2]])) @?= [[3], [1, 2]],
      testCase "E2: no tier past the bound is evaluated" $ do
        let t = Tiers ([[1, 1], [2, 1], [3 :: Int]] <> error "evaluated a tier past the bound")
        n <- evaluate (length (concat (upTo 2 (nubTiersOn id t))))
        n @?= 3
    ]

sampleTests :: TestTree
sampleTests =
  testGroup
    "E3 sampleT draws the same values for the same seed"
    [ testCase "E3: the first values of SplitMix64 from the seeds 0, 1 and 42 are those of the paper's algorithm" $
        -- new SplittableRandom(seed).nextLong() of Steele, Lea and Flood
        -- (OOPSLA 2014): mix64 (MurmurHash3's finalizer) of the seed plus
        -- n times the golden gamma; the same values as seedSMGen seed
        -- 0x9e3779b97f4a7c15 and nextWord64 of the splitmix package
        -- (0.1.3.2, Hackage)
        mapM_
          (\(seed, ws) -> (seed, take 4 (sampleT seed 4 nextWord64)) @?= (seed, ws))
          [ (0, [0x9ca066f1a4ab2eea, 0xd30b054265133dd7, 0xd7f1515598b6b983, 0x6ae4c48206c1097e]),
            (1, [0xe5fdc025e13eeed5, 0xe85028e6b31f8e7a, 0xa288ccdc266474e3, 0x1991df90c96fbf6c]),
            (42, [0x2d1c8760f8047fc7, 0x077fb59b63a77004, 0x778bf073f79acc91, 0xfe8930b98846eec4])
          ],
      testCase "E3: the same seed, number and function give the same values" $ do
        let draw = nextBelow 1000
        sampleT 7 500 draw @?= sampleT 7 500 draw
        sampleT 7 500 (oneOf "abc") @?= sampleT 7 500 (oneOf "abc"),
      testCase "E3: another seed gives other values" $
        assertBool "seeds 7 and 8" (sampleT 7 20 (nextBelow 1000) /= sampleT 8 20 (nextBelow 1000)),
      testCase "E3: a number of 0 or less draws nothing; 1 draws one; more than the values there are draws that many" $ do
        sampleT 3 0 nextWord64 @?= []
        sampleT 3 (-2) nextWord64 @?= []
        length (sampleT 3 1 nextWord64) @?= 1
        let drawn = sampleT 3 50 (oneOf [False, True])
        length drawn @?= 50
        sort (nub drawn) @?= [False, True],
      testCase "E3: the first values drawn are a prefix of more values drawn" $
        sampleT 11 10 (nextBelow 7) @?= take 10 (sampleT 11 30 (nextBelow 7)),
      testCase "E3: nextBelow n draws every integer from 0 to n - 1, and none other" $
        mapM_
          (\n -> (n, sort (nub (sampleT (fromIntegral n) 2000 (nextBelow n)))) @?= (n, [0 .. n - 1]))
          [1, 2, 3, 5, 8, 17, 64],
      testCase "E3: nextBelow of 1 is 0 and leaves the generator as it is" $
        nextBelow 1 (mkSplitMix 5) @?= (0, mkSplitMix 5),
      testCase "E3: the generator moves by the golden gamma at each value" $
        snd (nextWord64 (mkSplitMix 0)) @?= snd (nextWord64 (snd (nextWord64 (mkSplitMix (negate goldenGamma)))))
    ]
  where
    goldenGamma = 0x9e3779b97f4a7c15 :: Word64

-- | Whether taking out any one element breaks the predicate.
minimal :: ([a] -> Bool) -> [a] -> Bool
minimal p xs = and [not (p (take i xs <> drop (i + 1) xs)) | i <- [0 .. length xs - 1]]

shrinkTests :: TestTree
shrinkTests =
  testGroup
    "E4 shrinkList returns a counterexample it cannot shrink further"
    [ testCase "E4: the result holds the predicate, and taking out any one element breaks it" $
        mapM_
          ( \(name, p, xs) ->
              let r = shrinkList p xs
               in assertBool (name <> ": " <> show r) (p r && minimal p r)
          )
          predicates,
      testCase "E4: the elements are taken out from the first on" $ do
        shrinkList (elem 3) [1, 3, 2, 3, 4 :: Int] @?= [3]
        shrinkList ((>= 2) . length) [5, 6, 7, 8 :: Int] @?= [7, 8]
        shrinkList ((>= 5) . sum) [1, 2, 3, 4 :: Int] @?= [3, 4]
        shrinkList (\ys -> 1 `elem` ys && 2 `elem` ys) [2, 9, 1, 2 :: Int] @?= [1, 2],
      testCase "E4: an element that may go only after another went is taken out too" $
        -- [0, 1, 2] holds, [1, 2] does not, [0, 2] holds and [2] holds
        shrinkList (\ys -> ys == [0, 1, 2] || ys == [0, 2] || ys == [2 :: Int]) [0, 1, 2] @?= [2],
      testCase "E4: no element, one element, and only elements that cannot go" $ do
        shrinkList (const True) ([] :: [Int]) @?= []
        shrinkList (const True) [1 :: Int] @?= []
        shrinkList (== [1 :: Int]) [1] @?= [1]
        shrinkList (\ys -> length ys == 3) [1, 2, 3 :: Int] @?= [1, 2, 3],
      testCase "E4: a list the predicate does not hold for is returned as it is" $
        shrinkList (elem 9) [1, 2, 3 :: Int] @?= [1, 2, 3]
    ]
  where
    predicates :: [(String, [Int] -> Bool, [Int])]
    predicates =
      [ ("contains 3", elem 3, [1, 3, 2, 3, 4]),
        ("at least two elements", (>= 2) . length, [1 .. 9]),
        ("a sum of 10 or more", (>= 10) . sum, [1 .. 9]),
        ("an even element after an odd one", \ys -> or [odd a && even b | (i, a) <- zip [0 :: Int ..] ys, b <- drop (i + 1) ys], [2, 4, 1, 6, 3, 8]),
        ("sorted, with three elements or more", \ys -> length ys >= 3 && sort ys == ys, [1, 2, 5, 6, 7])
      ]
