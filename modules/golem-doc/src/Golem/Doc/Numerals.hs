{- | Number notations: positional kanji (十、百二十), digit-by-digit kanji
(一〇、一二〇) and the number formats of style.toml.
-}
module Golem.Doc.Numerals
  ( kanji,
    kanjiDigits,
    formatNumber,
    circled,
  )
where

import Data.Text (Text)
import Data.Text qualified as T

{- | A circled number from 1 to 50 (golem-driver ADR 0023): U+2460 for 1
to 20, U+3251 for 21 to 35, U+32B1 for 36 to 50; another number in
parentheses.
-}
circled :: Int -> Text
circled n
  | n >= 1 && n <= 20 = T.singleton (toEnum (0x2460 + n - 1))
  | n >= 21 && n <= 35 = T.singleton (toEnum (0x3251 + n - 21))
  | n >= 36 && n <= 50 = T.singleton (toEnum (0x32B1 + n - 36))
  | otherwise = "(" <> T.pack (show n) <> ")"

digitChar :: Integer -> Char
digitChar d = T.index "〇一二三四五六七八九" (fromInteger d)

-- | Positional kanji numerals: 10 → 十, 120 → 百二十, 10000 → 一万.
kanji :: Integer -> Text
kanji n
  | n < 0 = "マイナス" <> kanji (negate n)
  | n == 0 = "〇"
  | otherwise = T.concat (reverse (go n bigUnits))
  where
    bigUnits = ["", "万", "億", "兆", "京"]
    go 0 _ = []
    go m (u : us) =
      let (q, r) = m `divMod` 10000
          part = small r
       in (if r == 0 then "" else part <> u) : go q us
    go m [] = [T.pack (show m)]
    small r =
      T.concat
        [ (if d == 1 && p /= "" then "" else T.singleton (digitChar d)) <> p
        | (d, p) <- zip (digitsOf r) ["千", "百", "十", ""],
          d /= 0
        ]
    digitsOf r = [r `div` 1000, (r `div` 100) `mod` 10, (r `div` 10) `mod` 10, r `mod` 10]

-- | Digit-by-digit kanji: 10 → 一〇.
kanjiDigits :: Integer -> Text
kanjiDigits n
  | n < 0 = "マイナス" <> kanjiDigits (negate n)
  | otherwise = T.map (\c -> digitChar (read [c])) (T.pack (show n))

-- | Fills @{n}@, @{n:kanji}@, @{1}@, @{2}@ and @{chapter}@.
formatNumber :: Text -> [Integer] -> Maybe Integer -> Text
formatNumber fmt levels chapter = go fmt
  where
    own = if null levels then 0 else last levels
    go t = case T.breakOn "{" t of
      (pre, rest)
        | T.null rest -> pre
        | otherwise ->
            let (key, after) = T.breakOn "}" (T.drop 1 rest)
             in pre <> fill key <> go (T.drop 1 after)
    fill = \case
      "n" -> T.pack (show own)
      "n:kanji" -> kanji own
      "1" -> maybe "" (T.pack . show) (nth 0)
      "2" -> maybe "" (T.pack . show) (nth 1)
      "chapter" -> maybe "" (T.pack . show) chapter
      other -> "{" <> other <> "}"
    nth i = case drop i levels of
      (x : _) -> Just x
      [] -> Nothing
