{- | Number notations: positional kanji (十、百二十), digit-by-digit kanji
(一〇、一二〇). The table of notations is "Golem.Numerals.Notation" and
the formats of style.toml "Golem.Numerals.Format" (docs/adr/0177).
-}
module Golem.Numerals
  ( kanji,
    kanjiDigits,
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

{- | Positional kanji numerals: 10 → 十, 120 → 百二十, 10000 → 一万.
The units go up to 京 (10^16), so the domain is an absolute value below
10^20; the numbers of the IR are int64 and stay far below it (golem-doc
ADR 0006).
-}
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
