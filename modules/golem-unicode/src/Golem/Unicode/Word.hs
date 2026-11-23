{- | Word boundaries by the WB rules of UAX #29, Unicode 17.0.0
(docs/adr/0411).

The rules follow src/word.c of libgrapheme 3.0.0
(https://libs.suckless.org/libgrapheme/, Copyright 2019-2025 Laslo
Hunhold, ISC license; LICENSE-libgrapheme of this package). One segment is
read from its first character. Between two characters, the rules up to
WB4 look at the characters themselves; the later ones look at the
properties with Extend, Format and ZWJ skipped (WB4): the last two before
the position, from the start of the segment, and the first two after it.
-}
module Golem.Unicode.Word
  ( wordSegments,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Unicode.Ranges (RangeTable, lookupRange, rangeTable)
import Golem.Unicode.Table (WordBreak (..), wordBreakRanges)

{- | The segments between the word boundaries of the text, in order; each is
non-empty, and together they are the text. A segment is a word, or the
spaces, punctuation or other characters between words.
-}
wordSegments :: Text -> [Text]
wordSegments t
  | T.null t = []
  | otherwise =
      let (segment, after) = T.splitAt (segmentLength (map property (T.unpack t))) t
       in segment : wordSegments after

property :: Char -> WordBreak
property = lookupRange WbOther table

table :: RangeTable WordBreak
table = rangeTable wordBreakRanges

{- | The properties around a position (Nothing is beyond the segment or the
text), and whether the regional indicators that end the skipped properties
before it are even in number.
-}
data Around = Around
  { rawPrev :: Maybe WordBreak,
    rawNext :: Maybe WordBreak,
    prev0 :: Maybe WordBreak,
    prev1 :: Maybe WordBreak,
    next0 :: Maybe WordBreak,
    next1 :: Maybe WordBreak,
    riEven :: Bool
  }

{- | The number of characters of the segment at the start of the properties
(1 or more for a non-empty list).
-}
segmentLength :: [WordBreak] -> Int
segmentLength = go 0 Nothing Nothing True
  where
    -- n characters read; p0 and p1 the last two skipped properties before
    go :: Int -> Maybe WordBreak -> Maybe WordBreak -> Bool -> [WordBreak] -> Int
    go n p0 p1 ev = \case
      [] -> n
      x : rest ->
        let (p0', p1', ev')
              | skippable x = (p0, p1, ev)
              | otherwise = (Just x, p0, x /= WbRegionalIndicator || not ev)
            (n0, n1) = case filter (not . skippable) rest of
              a : b : _ -> (Just a, Just b)
              [a] -> (Just a, Nothing)
              [] -> (Nothing, Nothing)
            around =
              Around
                { rawPrev = Just x,
                  rawNext = case rest of
                    r : _ -> Just r
                    [] -> Nothing,
                  prev0 = p0',
                  prev1 = p1',
                  next0 = n0,
                  next1 = n1,
                  riEven = ev'
                }
         in if joins around then go (n + 1) p0' p1' ev' rest else n + 1

skippable :: WordBreak -> Bool
skippable p = p == WbExtend || p == WbFormat || p == WbZWJ

-- | Whether no boundary falls at the position.
joins :: Around -> Bool
joins a
  -- WB3
  | rp == Just WbCR && rn == Just WbLF = True
  -- WB3a
  | any isNewline rp = False
  -- WB3b
  | any isNewline rn = False
  -- WB3c
  | rp == Just WbZWJ && (rn == Just WbExtendedPictographic || rn == Just WbALetterExtendedPictographic) = True
  -- WB3d
  | rp == Just WbWSegSpace && rn == Just WbWSegSpace = True
  -- WB4
  | any skippable rn = True
  -- WB5
  | ahLetter p0 && ahLetter n0 = True
  -- WB6
  | ahLetter p0 && midLetterQ n0 && ahLetter n1 = True
  -- WB7
  | midLetterQ p0 && ahLetter n0 && ahLetter p1 = True
  -- WB7a
  | p0 == Just WbHebrewLetter && n0 == Just WbSingleQuote = True
  -- WB7b
  | p0 == Just WbHebrewLetter && n0 == Just WbDoubleQuote && n1 == Just WbHebrewLetter = True
  -- WB7c
  | p0 == Just WbDoubleQuote && n0 == Just WbHebrewLetter && p1 == Just WbHebrewLetter = True
  -- WB8
  | p0 == Just WbNumeric && n0 == Just WbNumeric = True
  -- WB9
  | ahLetter p0 && n0 == Just WbNumeric = True
  -- WB10
  | p0 == Just WbNumeric && ahLetter n0 = True
  -- WB11
  | midNumQ p0 && n0 == Just WbNumeric && p1 == Just WbNumeric = True
  -- WB12
  | p0 == Just WbNumeric && midNumQ n0 && n1 == Just WbNumeric = True
  -- WB13
  | p0 == Just WbKatakana && n0 == Just WbKatakana = True
  -- WB13a
  | (ahLetter p0 || p0 `elem` map Just [WbNumeric, WbKatakana, WbExtendNumLet]) && n0 == Just WbExtendNumLet = True
  -- WB13b
  | p0 == Just WbExtendNumLet && (ahLetter n0 || n0 `elem` map Just [WbNumeric, WbKatakana]) = True
  -- WB15, WB16
  | not (riEven a) && n0 == Just WbRegionalIndicator = True
  -- WB999
  | otherwise = False
  where
    rp = rawPrev a
    rn = rawNext a
    p0 = prev0 a
    p1 = prev1 a
    n0 = next0 a
    n1 = next1 a
    isNewline p = p == WbNewline || p == WbCR || p == WbLF
    ahLetter = any (\p -> p == WbALetter || p == WbALetterExtendedPictographic || p == WbHebrewLetter)
    midLetterQ = any (\p -> p == WbMidLetter || p == WbMidNumLet || p == WbSingleQuote)
    midNumQ = any (\p -> p == WbMidNum || p == WbMidNumLet || p == WbSingleQuote)
