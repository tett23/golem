{- | Pure memoisation through a lazy trie (docs/adr ADR 0034). A key is
encoded as a list of small non-negative integers; the trie holds, for
every such list, the result as an unevaluated thunk, and only the nodes on
the paths that are looked up are ever built. Laziness does the caching:
looking a key up a second time finds the thunk already evaluated. There is
no mutable state, so the table needs neither IO nor unsafePerformIO, and
threads that look up the same key at once at worst evaluate one pure
thunk twice.
-}
module Golem.Typeset.Memo
  ( memoWith,
    digitLimit,
    textDigits,
    shapingTextKey,
    fromShapingTextKey,
  )
where

import Data.Bits (shiftL, shiftR, (.&.))
import Data.Char (chr, isDigit, ord)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Vector qualified as V
import Golem.Typeset (Shaping (..))

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

{- | A shaping and a text as digits (docs/adr/0253), given the roles of
the fonts in order. The first digit is four times the number of the role
among them, plus two if vertical, plus one if the characters of both
scripts are Latin. A role that is not among them has the number after
the last one and its name follows as a text. Then come the number of
extra features, each feature ('featureDigits'), and the text. In the
role body without features, the key of one character is four digits.
-}
shapingTextKey :: [Text] -> (Shaping, Text) -> [Int]
shapingTextKey roles = \(Shaping role vertical extra dual, t) ->
  let bits = 2 * fromEnum vertical + fromEnum dual
      named = case Map.lookup role numbers of
        Just n -> [4 * n + bits]
        Nothing -> 4 * other + bits : textDigits role
   in named <> (length extra : concatMap featureDigits extra) <> textDigits t
  where
    numbers = Map.fromList (zip roles [0 ..])
    other = length roles

{- | A feature as digits: an OpenType tag of four ASCII characters, alone
or after + or -, is two digits of fourteen bits, seven a character, with
the sign (1 for +, 2 for -) above the fourteen bits of the first
(docs/adr ADR 0255); a tag with a value, @tag=N@ with N from 0 to 65535,
has the sign 3 and N as a third digit (docs/adr/0268); any
other text is @-(1 + its length)@ and its code points, a key that is
decoded but not remembered.
-}
featureDigits :: Text -> [Int]
featureDigits f = case T.unpack f of
  ['+', a, b, c, d] | ascii [a, b, c, d] -> tag 1 a b c d
  ['-', a, b, c, d] | ascii [a, b, c, d] -> tag 2 a b c d
  [a, b, c, d] | ascii [a, b, c, d] -> tag 0 a b c d
  a : b : c : d : '=' : n
    | ascii [a, b, c, d],
      not (null n),
      length n <= 5,
      all isDigit n,
      -- the text of the value as it reads back: no leading zero
      show (read n :: Int) == n,
      read n <= (65535 :: Int) ->
        tag 3 a b c d <> [read n]
  cs -> negate (1 + length cs) : map ord cs
  where
    ascii = all (\x -> ord x < 128)
    tag s a b c d = [s `shiftL` 14 + pair a b, pair c d]
    pair a b = ord a `shiftL` 7 + ord b

-- | The inverse of 'shapingTextKey' on the keys it gives, with the same roles.
fromShapingTextKey :: [Text] -> [Int] -> (Shaping, Text)
fromShapingTextKey roles = \ds0 ->
  let (h, ds1) = case ds0 of
        (x : rest) -> (x, rest)
        [] -> (0, [])
      vertical = h .&. 2 /= 0
      dual = h .&. 1 /= 0
      (role, ds2) = case names V.!? (h `shiftR` 2) of
        Just r -> (r, ds1)
        Nothing -> takeText ds1
      (n, ds3) = case ds2 of
        (k : rest) -> (k, rest)
        [] -> (0, [])
      (extra, ds4) = takeFeatures n ds3
      (t, _) = takeText ds4
   in (Shaping role vertical extra dual, t)
  where
    names = V.fromList roles
    takeText = \case
      (k : rest) -> let (cs, rest') = splitAt k rest in (T.pack (map chr cs), rest')
      [] -> (T.empty, [])
    takeFeatures k ds
      | k <= 0 = ([], ds)
      | otherwise =
          let (x, ds') = takeFeature ds
              (xs, ds'') = takeFeatures (k - 1) ds'
           in (x : xs, ds'')
    takeFeature = \case
      (a : rest)
        | a < 0 -> let (cs, rest') = splitAt (negate a - 1) rest in (T.pack (map chr cs), rest')
      (a : b : n : rest)
        | a `shiftR` 14 == 3 -> (T.pack (unpair (a .&. 0x3FFF) <> unpair b <> "=" <> show n), rest)
      (a : b : rest) ->
        let sign = case a `shiftR` 14 of
              1 -> "+"
              2 -> "-"
              _ -> ""
         in (T.pack (sign <> unpair (a .&. 0x3FFF) <> unpair b), rest)
      _ -> (T.empty, [])
    unpair x = [chr (x `shiftR` 7), chr (x .&. 0x7F)]
