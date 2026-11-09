{- | Ordering of index readings, based on JIS X 4061 (golem-doc ADR 0002).
No locale-dependent collation library is used.
-}
module Golem.Assemble.Collation
  ( collationKey,
    CollationKey,
    indexHeading,
  )
where

import Data.Char (chr, isAsciiLower, isAsciiUpper, isDigit, ord, toLower, toUpper)
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

{- | The heading of the section of the index of a reading (docs/adr/0265):
by the primary key of its first character, 記号と数字 for symbols and
digits, the capital of a Latin letter, the head of the row of the clear
hiragana of a kana, and その他 for the rest. The heading is a monotonic
function of the primary key, so the entries of one heading are next to
each other in collation order.
-}
indexHeading :: Text -> Text
indexHeading t = case fst3 (collationKey t) of
  (2, c) : _ -> T.singleton (toUpper c)
  (3, c) : _ -> maybe "その他" T.singleton (lookup c [(k, head') | (head', row) <- kanaRows, k <- row])
  (4, _) : _ -> "その他"
  _ -> "記号と数字"
  where
    fst3 (a, _, _) = a
    kanaRows = [('あ', "あいうえお"), ('か', "かきくけこ"), ('さ', "さしすせそ"), ('た', "たちつてと"), ('な', "なにぬねの"), ('は', "はひふへほ"), ('ま', "まみむめも"), ('や', "やゆよ"), ('ら', "らりるれろ"), ('わ', "わゐゑをん")]

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
