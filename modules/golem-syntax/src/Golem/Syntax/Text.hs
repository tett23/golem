{- | Small functions on text that packages with nothing else in common
need: golem-syntax is the one package they all depend on. They are kept
in this one module, and are not re-exported by "Golem.Syntax", so that
they do not spread over golem-syntax or clash with local names.
-}
module Golem.Syntax.Text
  ( tshow,
    escapeXml,
    isSpaceTab,
    showRationalDigits,
  )
where

import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as T

tshow :: (Show a) => a -> Text
tshow = T.pack . show

-- | The four characters of XML markup as character references.
escapeXml :: Text -> Text
escapeXml = T.concatMap $ \case
  '&' -> "&amp;"
  '<' -> "&lt;"
  '>' -> "&gt;"
  '"' -> "&quot;"
  c -> T.singleton c

-- | A space or a tab.
isSpaceTab :: Char -> Bool
isSpaceTab c = c == ' ' || c == '\t'

{- | A rational to at most @n@ decimals, rounded half to even with integer
arithmetic, trailing zeros removed.
-}
showRationalDigits :: Int -> Rational -> Text
showRationalDigits n r
  | q < 0 = "-" <> digitsOf (negate q)
  | otherwise = digitsOf q
  where
    scale = 10 ^ n :: Integer
    q = roundHalfEven (r * fromInteger scale)
    digitsOf x =
      let (i, f) = x `quotRem` scale
          frac = T.dropWhileEnd (== '0') (T.justifyRight n '0' (T.pack (show f)))
       in T.pack (show i) <> (if T.null frac then "" else "." <> frac)

roundHalfEven :: Rational -> Integer
roundHalfEven r =
  let n = numerator r
      d = denominator r
      (q, m) = n `divMod` d
   in case compare (2 * m) d of
        LT -> q
        GT -> q + 1
        EQ -> if even q then q else q + 1
