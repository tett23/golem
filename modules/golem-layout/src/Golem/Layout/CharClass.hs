-- | The JLReq character classes the composition uses (golem-layout ADR 0002).
module Golem.Layout.CharClass
  ( CharClass (..),
    charClass,
    isExtending,
    clusters,
  )
where

import Data.Char (GeneralCategory (..), generalCategory, isAscii, isSpace)
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

charClass :: Char -> CharClass
charClass c
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
  | isAscii c || (c >= '\x00A0' && c <= '\x024F') || (c >= '\x0370' && c <= '\x04FF') = Western
  | otherwise = Ideograph

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
