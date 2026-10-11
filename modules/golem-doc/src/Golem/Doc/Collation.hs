{- | Ordering of index readings, based on JIS X 4061 (golem-doc ADR 0002).
No locale-dependent collation library is used.
-}
module Golem.Doc.Collation
  ( collationKey,
    CollationKey,
  )
where

import Data.Char (chr, isAsciiLower, isAsciiUpper, isDigit, ord, toLower)
import Data.Text (Text)
import Data.Text qualified as T

-- | (primary, secondary, tertiary). Compared lexicographically.
type CollationKey = ([(Int, Char)], [Int], [Int])

data Voicing = Clear | Voiced | SemiVoiced
  deriving stock (Eq, Enum)

collationKey :: Text -> CollationKey
collationKey t =
  let chars = expandLong (map toHiragana (T.unpack t))
      info = map classify chars
   in ([p | (p, _, _) <- info], [s | (_, s, _) <- info], [x | (_, _, x) <- info])

toHiragana :: Char -> Char
toHiragana c
  | c >= 'ァ' && c <= 'ヶ' = chr (ord c - 0x60)
  | otherwise = c

-- | The long vowel mark takes the vowel of the preceding kana.
expandLong :: String -> String
expandLong = go Nothing
  where
    go _ [] = []
    go prev ('ー' : rest) = case prev >>= vowelOf of
      Just v -> v : go (Just v) rest
      Nothing -> 'ー' : go prev rest
    go _ (c : rest) = c : go (Just c) rest

vowelOf :: Char -> Maybe Char
vowelOf c =
  let (base, _, _) = baseKana c
   in lookup base [(k, v) | (row, v) <- zip rows "あいうえお", k <- row]
  where
    rows =
      [ "あかさたなはまやらわ",
        "いきしちにひみり",
        "うくすつぬふむゆる",
        "えけせてねへめれ",
        "おこそとのほもよろを"
      ]

-- | Base kana, voicing, and whether it was small.
baseKana :: Char -> (Char, Voicing, Bool)
baseKana c = case lookup c small of
  Just b -> (b, Clear, True)
  Nothing -> case lookup c voiced of
    Just b -> (b, Voiced, False)
    Nothing -> case lookup c semi of
      Just b -> (b, SemiVoiced, False)
      Nothing -> (c, Clear, False)
  where
    small = zip "ぁぃぅぇぉっゃゅょゎゕゖ" "あいうえおつやゆよわかけ"
    voiced = zip "がぎぐげござじずぜぞだぢづでどばびぶべぼゔ" "かきくけこさしすせそたちつてとはひふへほう"
    semi = zip "ぱぴぷぺぽ" "はひふへほ"

classify :: Char -> ((Int, Char), Int, Int)
classify c
  | isDigit c = ((1, c), 0, 0)
  | isAsciiLower c || isAsciiUpper c = ((2, toLower c), 0, if isAsciiUpper c then 1 else 0)
  | c >= 'ぁ' && c <= 'ゖ' =
      let (b, v, sm) = baseKana c
       in ((3, b), fromEnum v, if sm then 1 else 0)
  | c >= '\x4E00' = ((4, c), 0, 0)
  | otherwise = ((0, c), 0, 0)
