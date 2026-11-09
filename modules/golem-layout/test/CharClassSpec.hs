{- | The character classes as tables (docs/adr/0250): every code point
gives what the lists of characters gave. The reference below is the
definition of golem-layout before ADR 0250, membership in String
literals, copied as it was; a change of a class changes both.
-}
module CharClassSpec (charClassTests) where

import Data.Char (chr)
import Data.Text (Text)
import Golem.Layout.CharClass
import Test.Tasty
import Test.Tasty.HUnit

charClassTests :: TestTree
charClassTests =
  testGroup
    "character classes as tables (docs/adr/0250)"
    [ testCase "I1: charClass is the reference on every code point" $
        mismatches (\c -> charClass c == refCharClass c) @?= [],
      testCase "I2: charClassIn is the reference on every code point, outside a span and in ja, JA-JP and en" $
        mapM_ (\l -> (l, mismatches (\c -> charClassIn l c == refCharClassIn l c)) @?= (l, [])) langs,
      testCase "I3: isDualCharacter is the reference on every code point" $
        mismatches (\c -> isDualCharacter c == refIsDualCharacter c) @?= [],
      testCase "I3: isJoinerCharacter is the reference on every code point" $
        mismatches (\c -> isJoinerCharacter c == refIsJoiner c) @?= [],
      testCase "I3: isHyphenCharacter is the reference on every code point" $
        mismatches (\c -> isHyphenCharacter c == refIsHyphen c) @?= [],
      testCase "the boundaries: the ends of the code points, the first and last character of each list and their neighbours, surrogates, a noncharacter" $ do
        let points = boundaries
        [c | c <- points, charClass c /= refCharClass c] @?= []
        [(l, c) | l <- langs, c <- points, charClassIn l c /= refCharClassIn l c] @?= []
        [c | c <- points, isDualCharacter c /= refIsDualCharacter c] @?= []
        [c | c <- points, isJoinerCharacter c /= refIsJoiner c] @?= []
        [c | c <- points, isHyphenCharacter c /= refIsHyphen c] @?= [],
      testCase "the boundaries: examples of each class" $
        map charClass "「」‐？・。、—々ーぁ\x3000あ亜A" @?= [Opening, Closing, Hyphen, Dividing, MiddleDot, FullStop, Comma, Inseparable, Iteration, ProlongedSound, SmallKana, IdeographicSpace, Kana, Ideograph, Western],
      testCase "dualCharacters is still the list of the characters of both scripts" $
        filter isDualCharacter dualCharacters @?= dualCharacters
    ]
  where
    -- the code points (at most the first ten) where the property fails
    mismatches p = take 10 [c | c <- [minBound .. maxBound], not (p c)]

langs :: [Maybe Text]
langs = [Nothing, Just "ja", Just "JA-JP", Just "en"]

-- the ends of each list and the code points next to them (docs/adr/0250, 境界の入力)
boundaries :: [Char]
boundaries =
  [minBound, maxBound, '\xD7FF', '\xDFFF', '\xE000', '\xFFFE', '\xFFFF', '\x300B', '\x300C', '\x300D', '\x300E']
    <> concat [[pred' e, e, succ' e] | l <- refLists, e <- take 1 l <> take 1 (reverse l)]
  where
    pred' c = if c == minBound then c else pred c
    succ' c = if c == maxBound then c else succ c

refLists :: [String]
refLists =
  [ "「『（［｛〈《【〔〘〖〝‘“｟«",
    "」』）］｝〉》】〕〙〗〟’”｠»",
    "‐‑〜゠–",
    "？！‼⁇⁈⁉",
    "・：；",
    "。．",
    "、，",
    "—―…‥〳〴〵",
    "ヽヾゝゞ々〻",
    "ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ",
    "‘’“”«»‹›—–‐‑…",
    "“‘«‹",
    "”’»›",
    "—…",
    "‘’“”—‐‑–",
    "-‐‑–—",
    [chr 0x3041, chr 0x309F, chr 0x30A0, chr 0x30FF, chr 0x00A0, chr 0x024F, chr 0x0370, chr 0x04FF]
  ]

-- the reference: Golem.Layout.CharClass before docs/adr/0250

refCharClass :: Char -> CharClass
refCharClass c
  | c `elem` ("「『（［｛〈《【〔〘〖〝‘“｟«" :: String) = Opening
  | c `elem` ("」』）］｝〉》】〕〙〗〟’”｠»" :: String) = Closing
  | c `elem` ("‐‑〜゠–" :: String) = Hyphen
  | c `elem` ("？！‼⁇⁈⁉" :: String) = Dividing
  | c `elem` ("・：；" :: String) = MiddleDot
  | c `elem` ("。．" :: String) = FullStop
  | c `elem` ("、，" :: String) = Comma
  | c `elem` ("—―…‥〳〴〵" :: String) = Inseparable
  | c `elem` ("ヽヾゝゞ々〻" :: String) = Iteration
  | c == 'ー' = ProlongedSound
  | c `elem` ("ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ" :: String) = SmallKana
  | c == '\x3000' = IdeographicSpace
  | (c >= '\x3041' && c <= '\x309F') || (c >= '\x30A0' && c <= '\x30FF') = Kana
  | isAsciiRef c || (c >= '\x00A0' && c <= '\x024F') || (c >= '\x0370' && c <= '\x04FF') = Western
  | otherwise = Ideograph
  where
    isAsciiRef x = x < '\x80'

refIsDualCharacter :: Char -> Bool
refIsDualCharacter c = c `elem` ("‘’“”«»‹›—–‐‑…" :: String)

refCharClassIn :: Maybe Text -> Char -> CharClass
refCharClassIn lang c = case lang of
  Just l
    | refIsDualCharacter c, spanIsJapanese l -> refDualJapaneseClass c
    | refIsDualCharacter c -> Western
  _ -> refCharClass c

refDualJapaneseClass :: Char -> CharClass
refDualJapaneseClass c
  | c `elem` ("“‘«‹" :: String) = Opening
  | c `elem` ("”’»›" :: String) = Closing
  | c `elem` ("—…" :: String) = Inseparable
  | otherwise = Hyphen

-- isJoiner of Golem.Layout.Japanese, without the condition on the span
refIsJoiner :: Char -> Bool
refIsJoiner c = c `elem` ("‘’“”—‐‑–" :: String)

-- isHyphen of wordItems in Golem.Layout.Japanese
refIsHyphen :: Char -> Bool
refIsHyphen c = c `elem` ("-‐‑–—" :: String)
