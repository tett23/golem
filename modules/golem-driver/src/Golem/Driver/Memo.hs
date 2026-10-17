{- | Pure memoisation through a lazy trie (docs/adr ADR 0034). A key is
encoded as a list of small non-negative integers; the trie holds, for
every such list, the result as an unevaluated thunk, and only the nodes on
the paths that are looked up are ever built. Laziness does the caching:
looking a key up a second time finds the thunk already evaluated. There is
no mutable state, so the table needs neither IO nor unsafePerformIO, and
threads that look up the same key at once at worst evaluate one pure
thunk twice.
-}
module Golem.Driver.Memo
  ( memoWith,
    digitLimit,
    textDigits,
    shapingTextKey,
    fromShapingTextKey,
  )
where

import Data.Bits (shiftL, shiftR, (.&.))
import Data.Char (ord)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Vector qualified as V
import Golem.Driver.Pdf (Shaping (..))

-- | Each digit of a key is below this: 2^24, above every Unicode code point.
digitLimit :: Int
digitLimit = 1 `shiftL` (levels * bitsPerLevel)

bitsPerLevel :: Int
bitsPerLevel = 3

levels :: Int
levels = 8

{- | A complete 8-ary tree of depth 8 over the digits, built lazily. Eight
children a node: sixteen took 10 % more memory to set the developer
manual, four 2 % more time than eight.
-}
data Radix a = Leaf a | Node !(V.Vector (Radix a))

radix :: (Int -> a) -> Radix a
radix f = go levels 0
  where
    go 0 base = Leaf (f base)
    go d base = Node (V.generate (1 `shiftL` bitsPerLevel) (\i -> go (d - 1) ((base `shiftL` bitsPerLevel) + i)))

radixAt :: Radix a -> Int -> a
radixAt r n = go levels r
  where
    go _ (Leaf a) = a
    go d (Node v) = go (d - 1) (V.unsafeIndex v ((n `shiftR` ((d - 1) * bitsPerLevel)) .&. (1 `shiftL` bitsPerLevel - 1)))

-- | The value of the empty suffix and a child for every next digit.
data Trie a = Trie a (Radix (Trie a))

trie :: ([Int] -> a) -> Trie a
trie f = Trie (f []) (radix (\d -> trie (f . (d :))))

trieAt :: Trie a -> [Int] -> a
trieAt (Trie a _) [] = a
trieAt (Trie _ cs) (d : ds) = trieAt (radixAt cs d) ds

{- | @memoWith encode decode f@ is @f@, remembering its results. @encode@
must be injective and @decode@ its inverse on what it returns; a key whose
digits are not all in @[0, digitLimit)@ is not remembered, only computed.
The table lives as long as the function returned.
-}
memoWith :: (k -> [Int]) -> ([Int] -> k) -> (k -> v) -> k -> v
memoWith encode decode f = \k ->
  let ds = encode k
   in if all (\d -> d >= 0 && d < digitLimit) ds then trieAt table ds else f k
  where
    table = trie (f . decode)

-- | A text as its length and then its code points: a prefix-free encoding.
textDigits :: Text -> [Int]
textDigits t = T.length t : map ord (T.unpack t)

{- | A shaping and a text as digits: whether vertical, the role, the number
of extra features, each feature, then the text.
-}
shapingTextKey :: (Shaping, Text) -> [Int]
shapingTextKey (Shaping role vertical extra, t) =
  fromEnum vertical : textDigits role <> (length extra : concatMap textDigits extra) <> textDigits t

-- | The inverse of 'shapingTextKey' on the keys it gives.
fromShapingTextKey :: [Int] -> (Shaping, Text)
fromShapingTextKey ds0 =
  let (vertical, ds1) = case ds0 of
        (v : rest) -> (v /= 0, rest)
        [] -> (False, [])
      (role, ds2) = takeText ds1
      (n, ds3) = case ds2 of
        (k : rest) -> (k, rest)
        [] -> (0, [])
      (extra, ds4) = takeTexts n ds3
      (t, _) = takeText ds4
   in (Shaping role vertical extra, t)
  where
    takeText = \case
      (k : rest) -> let (cs, rest') = splitAt k rest in (T.pack (map toEnum cs), rest')
      [] -> (T.empty, [])
    takeTexts k ds
      | k <= 0 = ([], ds)
      | otherwise =
          let (x, ds') = takeText ds
              (xs, ds'') = takeTexts (k - 1) ds'
           in (x : xs, ds'')
