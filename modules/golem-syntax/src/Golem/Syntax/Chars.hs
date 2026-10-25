{- | The characters that cannot be written to the output (docs/adr ADR
0042): those outside the Char production of XML 1.0. They are refused
where the text is read, in manifest.toml (G03028) and in the manuscript
(G02089), so that no output has to change them.
-}
module Golem.Syntax.Chars
  ( firstUnwritable,
    codePointText,
  )
where

import Data.Char (ord, toUpper)
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (showHex)

{- | A C0 control character but tab, newline and return, U+FFFE, U+FFFF
or a surrogate code point. U+007F and the C1 controls are not, as XML
allows them.
-}
isUnwritable :: Char -> Bool
isUnwritable c =
  (c < ' ' && c `notElem` ("\t\n\r" :: String))
    || c == '\xFFFE'
    || c == '\xFFFF'
    || (c >= '\xD800' && c <= '\xDFFF')

-- | The first character of a text that cannot be written to the output.
firstUnwritable :: Text -> Maybe Char
firstUnwritable = T.find isUnwritable

-- | A code point as @U+0001@: at least four upper-case hexadecimal digits.
codePointText :: Char -> Text
codePointText c =
  let h = map toUpper (showHex (ord c) "")
   in T.pack ("U+" <> replicate (4 - length h) '0' <> h)
