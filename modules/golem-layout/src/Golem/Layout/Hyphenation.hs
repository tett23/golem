{- | Liang's hyphenation (golem-layout ADR 0001). Patterns use the TeX
notation: digits between letters, @.@ for a word boundary.
-}
module Golem.Layout.Hyphenation
  ( Patterns,
    parsePatterns,
    withExceptions,
    hyphenate,
  )
where

import Data.Char (isDigit, toLower)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T

-- | Letters of a pattern and the values between them (one more than the letters).
data Patterns = Patterns
  { patTable :: !(Map Text [Int]),
    -- | words hyphenated by hand (lower case → break positions)
    patExceptions :: !(Map Text [Int]),
    patLeftMin :: !Int,
    patRightMin :: !Int
  }

-- | Whitespace-separated patterns, e.g. @"hy3ph he2n hena4"@.
parsePatterns :: Int -> Int -> Text -> Patterns
parsePatterns leftMin rightMin src = Patterns (Map.fromList (map one (T.words src))) Map.empty leftMin rightMin
  where
    one p =
      let go acc vals pending t = case T.uncons t of
            Nothing -> (T.pack (reverse acc), reverse (pending : vals))
            Just (c, rest)
              | isDigit c -> go acc vals (fromEnum c - fromEnum '0') rest
              | otherwise -> go (c : acc) (pending : vals) 0 rest
       in go [] [] 0 p

{- | Adds exceptions written as hyphenated words (@ta-ble@); a word without
hyphens is never hyphenated.
-}
withExceptions :: Text -> Patterns -> Patterns
withExceptions src ps = ps {patExceptions = Map.fromList (map one (T.words src))}
  where
    one w =
      let parts = T.splitOn "-" w
       in (T.toLower (T.concat parts), init (scanl1 (+) (map T.length parts)))

-- | Positions (number of letters before the break) where the word may be hyphenated.
hyphenPoints :: Patterns -> Text -> [Int]
hyphenPoints ps word = case Map.lookup (T.map toLower word) (patExceptions ps) of
  Just points -> points
  Nothing -> patternPoints ps word

patternPoints :: Patterns -> Text -> [Int]
patternPoints ps word =
  let w = "." <> T.map toLower word <> "."
      len = T.length w
      values = foldr maxAt (replicate (len + 1) 0) [(i, vs) | i <- [0 .. len - 1], j <- [i + 1 .. len], Just vs <- [Map.lookup (T.take (j - i) (T.drop i w)) (patTable ps)]]
      maxAt (i, vs) acc = [if k >= i && k - i < length vs then max a (vs !! (k - i)) else a | (k, a) <- zip [0 ..] acc]
      -- value at index k sits between w[k-1] and w[k]; letters of the word start at w[1]
      n = T.length word
   in [p | p <- [patLeftMin ps .. n - patRightMin ps], odd (values !! (p + 1))]

-- | The word split at its hyphenation points.
hyphenate :: Patterns -> Text -> [Text]
hyphenate ps word = go 0 (hyphenPoints ps word)
  where
    go from [] = [T.drop from word]
    go from (p : rest) = T.take (p - from) (T.drop from word) : go p rest
