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
  )
where

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
checkAll n xs check = go 0 (concat (zipWith (\k t -> map (k,) t) [0 :: Int ..] (upTo n xs)))
  where
    go count [] = Passed count
    go count ((k, x) : rest) = case check x of
      [] -> go (count + 1) rest
      vs -> Failed k x vs
