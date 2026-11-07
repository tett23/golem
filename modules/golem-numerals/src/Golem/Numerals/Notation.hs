{- | The table of number notations (docs/adr/0177): each row is a name and
the rule that writes a number in it. A notation is added by adding a row.
-}
module Golem.Numerals.Notation
  ( Notation,
    notationName,
    Rule (..),
    notationRule,
    notations,
    notationNamed,
    writeNumber,
    notationRange,
    arabic,
    kanjiNotation,
    kanjiDigitsNotation,
    circledNotation,
    lowerAlphaNotation,
    upperAlphaNotation,
    lowerRomanNotation,
    upperRomanNotation,
    irohaNotation,
    aiueoNotation,
    asterisksNotation,
    noteSymbolsNotation,
  )
where

import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Numerals (kanji, kanjiDigits)

{- | How a notation writes a number: the systems of CSS Counter Styles
Level 3 that the table needs, and a function for the notations data
cannot write.
-}
data Rule
  = -- | positional: the digits from zero; 0 and up
    Numeric ![Char]
  | -- | bijective: the letters from one, then aa, ab; 1 and up
    Alphabetic ![Char]
  | -- | the weights and their symbols, largest first; 1 up to the maximum
    Additive !Integer ![(Integer, Text)]
  | -- | the symbols of 1, 2, … in order; the numbers they reach
    Fixed ![Text]
  | -- | a symbol as many times as the number; 1 and up
    Repeat !Text
  | -- | a function that writes 0 and up
    Function (Integer -> Text)

-- | A row of the table: its name and its rule.
data Notation = Notation
  { notationName :: !Text,
    notationRule :: Rule
  }

-- | Notations are one by their name: the names of the table differ.
instance Eq Notation where
  a == b = notationName a == notationName b

instance Show Notation where
  showsPrec d n = showParen (d > 10) (showString "notationNamed " . shows (notationName n))

-- | The table (docs/adr/0177), in the order of the ADR.
notations :: [Notation]
notations =
  [ arabic,
    kanjiNotation,
    kanjiDigitsNotation,
    circledNotation,
    lowerAlphaNotation,
    upperAlphaNotation,
    lowerRomanNotation,
    upperRomanNotation,
    irohaNotation,
    aiueoNotation,
    asterisksNotation,
    noteSymbolsNotation
  ]

-- | The row of a name.
notationNamed :: Text -> Maybe Notation
notationNamed name = find ((== name) . notationName) notations

arabic :: Notation
arabic = Notation "arabic" (Numeric "0123456789")

-- | Positional kanji (十二); the rule of [number-text] style kanji.
kanjiNotation :: Notation
kanjiNotation = Notation "kanji" (Function kanji)

-- | Digit-by-digit kanji (一二); the rule of [number-text] style kanji-digits.
kanjiDigitsNotation :: Notation
kanjiDigitsNotation = Notation "kanji-digits" (Function kanjiDigits)

-- | ① to ㊿ (golem-driver ADR 0023): U+2460 for 1 to 20, U+3251 for 21 to 35, U+32B1 for 36 to 50.
circledNotation :: Notation
circledNotation =
  Notation
    "circled"
    ( Fixed
        (map T.singleton (['\x2460' .. '\x2473'] <> ['\x3251' .. '\x325F'] <> ['\x32B1' .. '\x32BF']))
    )

lowerAlphaNotation :: Notation
lowerAlphaNotation = Notation "lower-alpha" (Alphabetic ['a' .. 'z'])

upperAlphaNotation :: Notation
upperAlphaNotation = Notation "upper-alpha" (Alphabetic ['A' .. 'Z'])

romanWeights :: [(Integer, Text)]
romanWeights = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]

lowerRomanNotation :: Notation
lowerRomanNotation = Notation "lower-roman" (Additive 3999 [(w, T.toLower s) | (w, s) <- romanWeights])

upperRomanNotation :: Notation
upperRomanNotation = Notation "upper-roman" (Additive 3999 romanWeights)

-- | イロハ順, 47 characters.
irohaNotation :: Notation
irohaNotation = Notation "iroha" (Fixed (map T.singleton "イロハニホヘトチリヌルヲワカヨタレソツネナラムウヰノオクヤマケフコエテアサキユメミシヱヒモセス"))

-- | アイウエオ順, 46 characters.
aiueoNotation :: Notation
aiueoNotation = Notation "aiueo" (Fixed (map T.singleton "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"))

-- | U+002A as many times as the number.
asterisksNotation :: Notation
asterisksNotation = Notation "asterisks" (Repeat "*")

{- | The seven symbols of JLReq 4.2.2 in its order: ASTERISK, DAGGER, DOUBLE
DAGGER, PILCROW SIGN, SECTION SIGN, DOUBLE VERTICAL LINE and NUMBER SIGN.
-}
noteSymbolsNotation :: Notation
noteSymbolsNotation = Notation "note-symbols" (Fixed ["*", "\x2020", "\x2021", "\x00B6", "\x00A7", "\x2016", "#"])

{- | The smallest number a notation writes and the largest, Nothing for no
largest: both from the data of its row.
-}
notationRange :: Notation -> (Integer, Maybe Integer)
notationRange n = case notationRule n of
  Numeric _ -> (0, Nothing)
  Alphabetic _ -> (1, Nothing)
  Additive top _ -> (1, Just top)
  Fixed syms -> (1, Just (toInteger (length syms)))
  Repeat _ -> (1, Nothing)
  Function _ -> (0, Nothing)

-- | A number in a notation; Nothing outside its range.
writeNumber :: Notation -> Integer -> Maybe Text
writeNumber n k
  | k < lo || maybe False (k >) hi = Nothing
  | otherwise = Just $ case notationRule n of
      Numeric ds -> T.pack (positional ds k)
      Alphabetic ls -> T.pack (bijective ls k)
      Additive _ ws -> additive ws k
      Fixed syms -> syms !! fromInteger (k - 1)
      Repeat s -> T.replicate (fromInteger k) s
      Function f -> f k
  where
    (lo, hi) = notationRange n
    positional ds m =
      let base = toInteger (length ds)
          go 0 acc = acc
          go x acc = let (q, r) = x `divMod` base in go q (ds !! fromInteger r : acc)
       in if m == 0 then [head' ds] else go m []
    head' = \case
      (d : _) -> d
      [] -> '0'
    bijective ls m =
      let base = toInteger (length ls)
          go x
            | x <= 0 = []
            | otherwise = let (q, r) = (x - 1) `divMod` base in go q <> [ls !! fromInteger r]
       in go m
    additive ws m = case ws of
      [] -> ""
      (w, s) : rest
        | m >= w -> s <> additive ws (m - w)
        | otherwise -> additive rest m
