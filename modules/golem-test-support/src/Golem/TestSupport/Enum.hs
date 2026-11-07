{- | Every small value, smallest first (docs/adr/0204): the part of
LeanCheck (Rudy Matela, BSD-3-Clause) that the exhaustive tests of
Golem use, written again.

An enumeration is a list of tiers: tier n holds every value of size n,
in a fixed order. Building a value with a constructor ('cons1' to
'cons4') makes it one larger than its parts; the sum ('\/') joins two
enumerations tier by tier; the product ('><') puts a pair in the tier
of the sum of the sizes of its parts.

There is no class of enumerable types (LeanCheck's @Listable@): an
enumeration is a value, passed where it is used, so that each test
chooses its own ranges.

'checkAll' checks every value up to a tier, in order, and returns the
first value with violations: the smallest one, and the same one every
time for the same tier.

The parts added by docs/adr/0208: 'checkAllPar' checks the values of a
tier on every processor and returns what 'checkAll' returns; 'tallyAll'
and 'tallyAllPar' also add up a count over the values checked, in the
same scan; 'nubTiersOn' keeps one value of each key; 'sampleT' draws
values with SplitMix64 (Steele, Lea and Flood, written again: the
splitmix package is BSD-3-Clause, but only a few dozen lines are used);
'shrinkList' makes a counterexample drawn so smaller.
-}
module Golem.TestSupport.Enum
  ( Tiers (..),
    value,
    cons1,
    cons2,
    cons3,
    cons4,
    (\/),
    (><),
    mapT,
    filterT,
    upTo,
    bools,
    intsIn,
    listsOf,
    listsOfLength,
    Violation (..),
    Result (..),
    checkAll,
    checkAllPar,
    checkAllParWith,
    tallyAll,
    tallyAllPar,
    tallyAllParWith,
    nubTiersOn,
    SplitMix,
    mkSplitMix,
    nextWord64,
    nextBelow,
    oneOf,
    sampleT,
    shrinkList,
  )
where

import Data.Bits (complement, countLeadingZeros, shiftR, xor, (.&.))
import Data.List (sortOn)
import Data.Word (Word64)
import GHC.Conc (numCapabilities, par, pseq)

-- | Tier n holds the values of size n.
newtype Tiers a = Tiers {tiers :: [[a]]}

infixr 7 \/

infixr 8 ><

-- | One value, of size 0.
value :: a -> Tiers a
value x = Tiers [[x]]

-- | The tiers one size larger: nothing of size 0.
delay :: Tiers a -> Tiers a
delay (Tiers xss) = Tiers ([] : xss)

-- | A constructor of one field: one larger than its field.
cons1 :: (a -> b) -> Tiers a -> Tiers b
cons1 f = delay . mapT f

-- | A constructor of two fields: one larger than the sum of its fields.
cons2 :: (a -> b -> c) -> Tiers a -> Tiers b -> Tiers c
cons2 f as bs = delay (mapT (uncurry f) (as >< bs))

-- | A constructor of three fields.
cons3 :: (a -> b -> c -> d) -> Tiers a -> Tiers b -> Tiers c -> Tiers d
cons3 f as bs cs = delay (mapT (\(a, (b, c)) -> f a b c) (as >< bs >< cs))

-- | A constructor of four fields.
cons4 :: (a -> b -> c -> d -> e) -> Tiers a -> Tiers b -> Tiers c -> Tiers d -> Tiers e
cons4 f as bs cs ds = delay (mapT (\(a, (b, (c, d))) -> f a b c d) (as >< bs >< cs >< ds))

-- | The sum: each tier of the left, then the same tier of the right.
(\/) :: Tiers a -> Tiers a -> Tiers a
Tiers xss \/ Tiers yss = Tiers (go xss yss)
  where
    go as [] = as
    go [] bs = bs
    go (a : as) (b : bs) = (a <> b) : go as bs

{- | The product: tier n holds the pairs whose sizes add up to n, those
with the smaller left part first.
-}
(><) :: Tiers a -> Tiers b -> Tiers (a, b)
Tiers xss >< Tiers yss = Tiers (productWith (,) xss yss)

productWith :: (a -> b -> c) -> [[a]] -> [[b]] -> [[c]]
productWith _ _ [] = []
productWith _ [] _ = []
productWith f (xs : xss) yss =
  tiers (Tiers (map (\ys -> [f x y | x <- xs, y <- ys]) yss) \/ delay (Tiers (productWith f xss yss)))

mapT :: (a -> b) -> Tiers a -> Tiers b
mapT f (Tiers xss) = Tiers (map (map f) xss)

-- | The values that satisfy the predicate, each in its own tier.
filterT :: (a -> Bool) -> Tiers a -> Tiers a
filterT p (Tiers xss) = Tiers (map (filter p) xss)

-- | The tiers from 0 to n; the tiers after n are never evaluated.
upTo :: Int -> Tiers a -> [[a]]
upTo n (Tiers xss) = take (n + 1) xss

-- | False and True, both of size 0.
bools :: Tiers Bool
bools = Tiers [[False, True]]

-- | The integers from lo to hi, each one larger than the one before: lo has size 0.
intsIn :: Int -> Int -> Tiers Int
intsIn lo hi = Tiers [[x] | x <- [lo .. hi]]

-- | The lists of the values: a list is one larger than the sum of its elements.
listsOf :: Tiers a -> Tiers [a]
listsOf xs = value [] \/ delay (Tiers (productWith (:) (tiers xs) (tiers (listsOf xs))))

-- | The lists of n values: a list is as large as the sum of its elements.
listsOfLength :: Int -> Tiers a -> Tiers [a]
listsOfLength n xs = Tiers (foldr (productWith (:)) [[[]]] (replicate n (tiers xs)))

-- | A rule a value breaks, and how.
data Violation = Violation {violationRule :: String, violationDetail :: String}
  deriving stock (Eq, Show)

-- | The values checked, or the first value with violations, its tier and its violations.
data Result a
  = Passed !Int
  | Failed {failedTier :: !Int, failedValue :: a, failedViolations :: [Violation]}
  deriving stock (Eq, Show)

{- | Checks the values of tiers 0 to n in order, and stops at the first
value with violations.
-}
checkAll :: Int -> Tiers a -> (a -> [Violation]) -> Result a
checkAll n xs check = fst (tallyAll n xs (\x -> (check x, ())))

{- | 'checkAll' that also adds up the counts of the values checked: those
before the first value with violations, and that value. The counts are
combined in the order of the values; '<>' should be strict, so that the
count of many values does not grow into a chain of thunks.
-}
tallyAll :: (Monoid m) => Int -> Tiers a -> (a -> ([Violation], m)) -> (Result a, m)
tallyAll n xs check = go 0 mempty (concat (zipWith (\k t -> map (k,) t) [0 :: Int ..] (upTo n xs)))
  where
    go count acc [] = (Passed count, acc)
    go count acc ((k, x) : rest) = case check x of
      ([], m) -> let acc' = acc <> m in acc' `seq` go (count + 1) acc' rest
      (vs, m) -> (Failed k x vs, acc <> m)

-- * in parallel

{- | 'checkAll' on every processor (docs/adr/0208): the same value as
'checkAll', whatever the number of processors. The program must be
built with @-threaded \"-with-rtsopts=-N -qg -A64m\"@ for the values
to be checked at the same time; without it they are checked one after
another.
-}
checkAllPar :: Int -> Tiers a -> (a -> [Violation]) -> Result a
checkAllPar = checkAllParWith numCapabilities parChunk

-- | The values a spark checks: enough for its work to outweigh its cost.
parChunk :: Int
parChunk = 512

{- | 'checkAllPar' with the number of workers and the values each of them
checks at a time given: the tests use it to put the values with
violations in different workers.
-}
checkAllParWith :: Int -> Int -> Int -> Tiers a -> (a -> [Violation]) -> Result a
checkAllParWith workers chunk n xs check = fst (tallyAllParWith workers chunk n xs (\x -> (check x, ())))

-- | 'tallyAll' on every processor: the same value as 'tallyAll'.
tallyAllPar :: (Monoid m) => Int -> Tiers a -> (a -> ([Violation], m)) -> (Result a, m)
tallyAllPar = tallyAllParWith numCapabilities parChunk

{- | 'tallyAllPar' with the number of workers and the values each of them
checks at a time given.

Each tier is taken in blocks of @workers * chunk@ values, in order. A
block is cut into parts of @chunk@ values that follow one another, and
each part is checked by a spark, up to its first value with violations.
The first part of the block with such a value holds the first such
value of the block: the block before it is passed, and the value is the
one 'tallyAll' returns. Only one block is held at a time, so that the
tiers, which may hold millions of values, are not.
-}
tallyAllParWith :: (Monoid m) => Int -> Int -> Int -> Tiers a -> (a -> ([Violation], m)) -> (Result a, m)
tallyAllParWith workers chunk n xs check = tiersFrom 0 mempty (zip [0 :: Int ..] (upTo n xs))
  where
    size = max 1 workers * max 1 chunk
    tiersFrom count acc [] = (Passed count, acc)
    tiersFrom count acc ((k, t) : rest) = blocks count acc t
      where
        blocks c a [] = tiersFrom c a rest
        blocks c a ys =
          let (block, more) = splitAt size ys
              parts = map (checkPart check) (chunksOf (max 1 chunk) block)
              combine c' a' [] = blocks c' a' more
              combine c' a' (Part found m checked : ps) =
                let a'' = a' <> m
                 in a'' `seq` case found of
                      Nothing -> combine (c' + checked) a'' ps
                      Just (x, vs) -> (Failed k x vs, a'')
           in sparkAll parts `pseq` combine c a parts
    sparkAll = foldr (\p rest -> p `par` rest) ()

-- | A part checked: its first value with violations, the count of the values checked and their number.
data Part a m = Part !(Maybe (a, [Violation])) !m !Int

-- | Checks the values of a part in order, up to the first with violations.
checkPart :: (Monoid m) => (a -> ([Violation], m)) -> [a] -> Part a m
checkPart check = go mempty 0
  where
    go acc i [] = Part Nothing acc i
    go acc i (x : rest) = case check x of
      ([], m) -> let acc' = acc <> m in acc' `seq` go acc' (i + 1) rest
      (vs, m) -> Part (Just (x, vs)) (acc <> m) (i + 1)

chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf k ys = let (a, b) = splitAt k ys in a : chunksOf k b

-- * one value of each key

{- | The values whose key no value before them has (docs/adr/0208): of the
values with the same key, the first of the smallest tier stays. The key
is meant to be the value the function under test is given, so that two
inputs that give it the same value are checked once.
-}
nubTiersOn :: (Ord k) => (a -> k) -> Tiers a -> Tiers a
nubTiersOn key (Tiers xss) = Tiers (go [] xss)
  where
    -- seen: the keys of the tiers before, in ascending order
    go _ [] = []
    go seen (t : ts) =
      let keyed = [(key x, i, x) | (i, x) <- zip [0 :: Int ..] t]
          firsts = firstOfEach (sortOn (\(k, i, _) -> (k, i)) keyed)
          fresh = minus firsts seen
          kept = map (\(_, _, x) -> x) (sortOn (\(_, i, _) -> i) fresh)
       in kept : go (mergeKeys seen [k | (k, _, _) <- fresh]) ts
    firstOfEach ((k, i, x) : rest) = (k, i, x) : firstOfEach (dropWhile (\(k', _, _) -> k' == k) rest)
    firstOfEach [] = []
    minus [] _ = []
    minus as [] = as
    minus as@(a@(k, _, _) : as') bs@(b : bs') = case compare k b of
      LT -> a : minus as' bs
      EQ -> minus as' bs'
      GT -> minus as bs'
    mergeKeys as [] = as
    mergeKeys [] bs = bs
    mergeKeys as@(a : as') bs@(b : bs') = if a <= b then a : mergeKeys as' bs else b : mergeKeys as bs'

-- * values drawn

{- | The state of SplitMix64 (Steele, Lea and Flood, \"Fast Splittable
Pseudorandom Number Generators\", OOPSLA 2014): the seed, and the odd
gamma added to it at each step.
-}
data SplitMix = SplitMix !Word64 !Word64
  deriving stock (Eq, Show)

{- | The generator of a seed, with the golden gamma: @new
SplittableRandom(seed)@ of the paper, @seedSMGen seed goldenGamma@ of
the splitmix package.
-}
mkSplitMix :: Word64 -> SplitMix
mkSplitMix seed = SplitMix seed 0x9e3779b97f4a7c15

-- | The next value: the seed moved by the gamma, mixed (@nextLong@ of the paper).
nextWord64 :: SplitMix -> (Word64, SplitMix)
nextWord64 (SplitMix seed gamma) = let seed' = seed + gamma in (mix64 seed', SplitMix seed' gamma)

-- | @mix64@ of the paper: the finalizer of MurmurHash3.
mix64 :: Word64 -> Word64
mix64 z0 =
  let shiftXor k z = z `xor` (z `shiftR` k)
      z1 = shiftXor 33 z0 * 0xff51afd7ed558ccd
      z2 = shiftXor 33 z1 * 0xc4ceb9fe1a85ec53
   in shiftXor 33 z2

{- | An integer from 0 to n - 1, each as likely as the others: the bits
below the highest bit of n - 1, drawn again while they are n or more
(@bitmaskWithRejection64@ of the splitmix package). n must be 1 or more.
-}
nextBelow :: Int -> SplitMix -> (Int, SplitMix)
nextBelow n g0
  | n <= 1 = (0, g0)
  | otherwise = go g0
  where
    range = fromIntegral (n - 1) :: Word64
    mask = complement 0 `shiftR` countLeadingZeros range
    go g = let (w, g') = nextWord64 g; x = w .&. mask in if x > range then go g' else (fromIntegral x, g')

-- | One of the values, each as likely as the others. The list must not be empty.
oneOf :: [a] -> SplitMix -> (a, SplitMix)
oneOf xs g = let (i, g') = nextBelow (length xs) g in (xs !! i, g')

{- | The values a function draws, one after another from the generator of
the seed (docs/adr/0208): the same seed, number and function give the
same values every time. None for a number of 0 or less.
-}
sampleT :: Word64 -> Int -> (SplitMix -> (a, SplitMix)) -> [a]
sampleT seed count draw = go count (mkSplitMix seed)
  where
    go k g
      | k <= 0 = []
      | otherwise = let (x, g') = draw g in x : go (k - 1) g'

-- * smaller counterexamples

{- | The list with elements taken out, from the first on, as long as the
predicate still holds without them (docs/adr/0208): when the predicate
holds for the list, it holds for the result, and no longer holds when
any one element of the result is taken out. A list the predicate does
not hold for is returned as it is.
-}
shrinkList :: ([a] -> Bool) -> [a] -> [a]
shrinkList p xs0
  | p xs0 = go 0 xs0
  | otherwise = xs0
  where
    go i xs
      | i >= length xs = xs
      | otherwise =
          let without = take i xs <> drop (i + 1) xs
           in if p without then go 0 without else go (i + 1) xs
