-- | The JLReq character classes the composition uses (golem-layout ADR 0002).
module Golem.Layout.CharClass
  ( CharClass (..),
    charClass,
    dualCharacters,
    isDualCharacter,
    isJoinerCharacter,
    isHyphenCharacter,
    isArabicDigit,
    isNumeral,
    isPrefixedAbbreviation,
    isPostfixedAbbreviation,
    charClassIn,
    dualJapaneseClass,
    spanIsJapanese,
    isExtending,
    clusters,
  )
where

import Data.Char (GeneralCategory (..), generalCategory, isAscii, isDigit, isSpace, ord)
import Data.IntSet qualified as IntSet
import Data.Text (Text)
import Data.Text qualified as T

-- | JLReq character classes used by the rules (cl-01 … cl-27).
data CharClass
  = Opening -- cl-01
  | Closing -- cl-02
  | Hyphen -- cl-03
  | Dividing -- cl-04
  | MiddleDot -- cl-05
  | FullStop -- cl-06
  | Comma -- cl-07
  | Inseparable -- cl-08
  | Iteration -- cl-09
  | ProlongedSound -- cl-10
  | SmallKana -- cl-11
  | IdeographicSpace -- cl-14
  | Kana -- cl-15, cl-16
  | Ideograph -- cl-19 and other full-width characters
  | Western -- cl-27
  deriving stock (Eq, Ord, Show, Enum, Bounded)

{- | The classes as tables (docs/adr/0250): each list is made a set once,
when it is first used, so that a character is looked up, not compared
with every character of a list decoded again from its literal.
-}
charSet :: String -> IntSet.IntSet
charSet = IntSet.fromList . map ord

inSet :: IntSet.IntSet -> Char -> Bool
inSet s c = IntSet.member (ord c) s

openings, closings, hyphens, dividings, middleDots, fullStops, commas, inseparables, iterations, smallKana :: IntSet.IntSet
-- ⦅ and ⦆ of JLReq, 〞 the closing of 〝, ～ for 〜, and ⸺ and ⸻ as ― (golem-layout ADR 0049)
openings = charSet "「『（［｛〈《【〔〘〖〝‘“｟«⦅"
closings = charSet "」』）］｝〉》】〕〙〗〟’”｠»⦆〞"
hyphens = charSet "‐‑〜゠–～"
dividings = charSet "？！‼⁇⁈⁉"
middleDots = charSet "・：；"
fullStops = charSet "。．"
commas = charSet "、，"
inseparables = charSet "—―…‥〳〴〵⸺⸻"
iterations = charSet "ヽヾゝゞ々〻"
smallKana = charSet "ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ"

charClass :: Char -> CharClass
charClass c
  | inSet openings c = Opening
  | inSet closings c = Closing
  | inSet hyphens c = Hyphen
  | inSet dividings c = Dividing
  | inSet middleDots c = MiddleDot
  | inSet fullStops c = FullStop
  | inSet commas c = Comma
  | inSet inseparables c = Inseparable
  | inSet iterations c = Iteration
  | c == 'ー' = ProlongedSound
  | inSet smallKana c = SmallKana
  | c == '\x3000' = IdeographicSpace
  | (c >= '\x3041' && c <= '\x309F') || (c >= '\x30A0' && c <= '\x30FF') = Kana
  | isAscii c || (c >= '\x00A0' && c <= '\x024F') || (c >= '\x0370' && c <= '\x04FF') = Western
  | otherwise = Ideograph

{- | The characters of both scripts (docs/adr ADR 0187): Japanese and
Latin text both use them, so the character alone does not tell which it
is. The one list of them.
-}
dualCharacters :: [Char]
dualCharacters = "‘’“”«»‹›—–‐‑…"

isDualCharacter :: Char -> Bool
isDualCharacter = inSet dualSet

dualSet :: IntSet.IntSet
dualSet = charSet dualCharacters

{- | The quotation marks, apostrophes, hyphens and dashes that join a Latin
word outside a language span when the nearest letter on either side is
Latin (golem-layout ADR 0008; the span is checked by the composition).
-}
isJoinerCharacter :: Char -> Bool
isJoinerCharacter = inSet joiners

joiners :: IntSet.IntSet
joiners = charSet "‘’“”—‐‑–"

{- | The hyphens and dashes of a Latin word, where it may break with the
explicit hyphen penalty (docs/adr/0222).
-}
isHyphenCharacter :: Char -> Bool
isHyphenCharacter = inSet wordHyphens

wordHyphens :: IntSet.IntSet
wordHyphens = charSet "-‐‑–—"

{- | The Arabic digits, of ASCII and full-width (golem-layout ADR 0049):
two of them next to each other are not broken in horizontal writing
(JLReq 3.1.10).
-}
isArabicDigit :: Char -> Bool
isArabicDigit c = isDigit c || (c >= '\xFF10' && c <= '\xFF19')

-- | The numerals (golem-layout ADR 0049): the Arabic digits and the kanji numerals.
isNumeral :: Char -> Bool
isNumeral c = isArabicDigit c || inSet kanjiNumerals c

kanjiNumerals :: IntSet.IntSet
kanjiNumerals = charSet "〇一二三四五六七八九十百千万億兆"

{- | The prefixed abbreviations of JLReq (cl-12) and their full-width
forms (golem-layout ADR 0049): no break between one and a numeral after
it. They are no class of 'CharClass'.
-}
isPrefixedAbbreviation :: Char -> Bool
isPrefixedAbbreviation = inSet prefixedAbbreviations

prefixedAbbreviations :: IntSet.IntSet
prefixedAbbreviations = IntSet.fromList [0x00A5, 0x0024, 0x00A3, 0x0023, 0x20AC, 0x2116, 0xFFE5, 0xFF04, 0xFFE1, 0xFF03]

{- | The postfixed abbreviations of JLReq (cl-13) and their full-width
forms (golem-layout ADR 0049): no break between a numeral and one after
it. They are no class of 'CharClass'.
-}
isPostfixedAbbreviation :: Char -> Bool
isPostfixedAbbreviation = inSet postfixedAbbreviations

postfixedAbbreviations :: IntSet.IntSet
postfixedAbbreviations =
  IntSet.fromList
    [ 0x00B0,
      0x2032,
      0x2033,
      0x2103,
      0x00A2,
      0x0025,
      0x2030,
      0x33CB,
      0x2113,
      0x3303,
      0x330D,
      0x3314,
      0x3318,
      0x3322,
      0x3323,
      0x3326,
      0x3327,
      0x332B,
      0x3336,
      0x333B,
      0x3349,
      0x334A,
      0x334D,
      0x3351,
      0x3357,
      0x338E,
      0x338F,
      0x339C,
      0x339D,
      0x339E,
      0x33A1,
      0x33C4,
      0xFF05,
      0xFFE0
    ]

{- | Whether a language span is Japanese (docs/adr ADR 0187): its primary
subtag, in lower case, is ja, as the separator after a number decides
(golem-html ADR 0002). Every other span is Latin, Chinese and Korean
among them.
-}
spanIsJapanese :: Text -> Bool
spanIsJapanese l = T.toLower (T.takeWhile (/= '-') l) == "ja"

{- | The class of a character in a language span, or outside one
(docs/adr ADR 0187): a character of both scripts is Latin in a Latin
span, and the Japanese class in a Japanese span (an opening or closing
bracket, inseparable or a hyphen; ‹ and › are brackets there). Outside
a span, and for every other character, it is 'charClass'.
-}
charClassIn :: Maybe Text -> Char -> CharClass
charClassIn lang c = case lang of
  Just l
    | isDualCharacter c, spanIsJapanese l -> dualJapaneseClass c
    | isDualCharacter c -> Western
  _ -> charClass c

-- | The Japanese class of a character of both scripts (docs/adr ADR 0187).
dualJapaneseClass :: Char -> CharClass
dualJapaneseClass c
  | inSet dualOpenings c = Opening
  | inSet dualClosings c = Closing
  | inSet dualInseparables c = Inseparable
  | otherwise = Hyphen

dualOpenings, dualClosings, dualInseparables :: IntSet.IntSet
dualOpenings = charSet "“‘«‹"
dualClosings = charSet "”’»›"
dualInseparables = charSet "—…"

{- | A character that joins the character before it in one box: general
category Mn, Mc or Me (combining characters, variation selectors among
them; golem-driver ADR 0036).
-}
isExtending :: Char -> Bool
isExtending c = generalCategory c `elem` [NonSpacingMark, SpacingCombiningMark, EnclosingMark]

{- | A text cut into its character units (golem-driver ADR 0036): a base
character and the combining characters after it. A combining character
with no base before it (at the start, after a space or another such
character) is a unit of its own.
-}
clusters :: Text -> [Text]
clusters = map T.pack . go . T.unpack
  where
    go = \case
      [] -> []
      c : rest
        | isSpace c || isExtending c -> [c] : go rest
        | otherwise -> let (marks, rest') = span isExtending rest in (c : marks) : go rest'
