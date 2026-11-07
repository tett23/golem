{- | The form of a language tag (docs/adr ADR 0183): a well-formed tag of
BCP 47 (RFC 5646, 2.1 and 2.2.9). Only the form is checked, not whether
the subtags are in the IANA registry, so that the result does not change
with the version of Golem. The one function for [metadata] language of a
book that declares PDF/A or PDF/UA, and for the tags of [lang] and @lang
(docs/adr ADR 0187).
-}
module Golem.Syntax.LanguageTag
  ( isLanguageTag,
  )
where

import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Text (Text)
import Data.Text qualified as T

{- | Whether a text is a well-formed language tag: a langtag, a private
use tag or one of the grandfathered tags, in any case.
-}
isLanguageTag :: Text -> Bool
isLanguageTag t =
  let lower = T.toLower t
   in lower `elem` grandfathered || case T.splitOn "-" lower of
        subtags | any T.null subtags -> False
        subtags -> privateUse subtags || langtag subtags

-- langtag = language ["-" script] ["-" region] *("-" variant) *("-" extension) ["-" privateuse]
langtag :: [Text] -> Bool
langtag = \case
  [] -> False
  l : rest
    | len 2 3 l && alpha l -> afterLanguage (dropExtlang rest)
    | len 4 8 l && alpha l -> afterLanguage rest
    | otherwise -> False
  where
    -- extlang = 3ALPHA *2("-" 3ALPHA), only after a language of 2 or 3 letters
    dropExtlang xs = drop (min 3 (length (takeWhile (\x -> T.length x == 3 && alpha x) xs))) xs
    afterLanguage xs =
      let xs1 = case xs of
            s : r | T.length s == 4 && alpha s -> r
            _ -> xs
          xs2 = case xs1 of
            r : r' | (T.length r == 2 && alpha r) || (T.length r == 3 && T.all isDigit r) -> r'
            _ -> xs1
          xs3 = dropWhile variant xs2
       in extensions xs3
    variant v = (len 5 8 v && alnum v) || (T.length v == 4 && isDigit (T.head v) && alnum v)
    -- extension = singleton 1*("-" (2*8alphanum)); then the private use
    extensions = \case
      [] -> True
      s : r
        | s == "x" -> privateUse (s : r)
        | T.length s == 1 && alnum s ->
            let (body, rest) = span (\x -> len 2 8 x && alnum x) r
             in not (null body) && extensions rest
        | otherwise -> False

-- privateuse = "x" 1*("-" (1*8alphanum))
privateUse :: [Text] -> Bool
privateUse = \case
  "x" : r@(_ : _) -> all (\x -> len 1 8 x && alnum x) r
  _ -> False

len :: Int -> Int -> Text -> Bool
len lo hi x = let n = T.length x in n >= lo && n <= hi

alpha :: Text -> Bool
alpha = T.all (\c -> isAsciiLower c || isAsciiUpper c)

alnum :: Text -> Bool
alnum = T.all (\c -> isAsciiLower c || isAsciiUpper c || isDigit c)

-- | The grandfathered tags of RFC 5646, irregular and regular, in lower case.
grandfathered :: [Text]
grandfathered =
  [ "en-gb-oed",
    "i-ami",
    "i-bnn",
    "i-default",
    "i-enochian",
    "i-hak",
    "i-klingon",
    "i-lux",
    "i-mingo",
    "i-navajo",
    "i-pwn",
    "i-tao",
    "i-tay",
    "i-tsu",
    "sgn-be-fr",
    "sgn-be-nl",
    "sgn-ch-de",
    "art-lojban",
    "cel-gaulish",
    "no-bok",
    "no-nyn",
    "zh-guoyu",
    "zh-hakka",
    "zh-min",
    "zh-min-nan",
    "zh-xiang"
  ]
