-- | The separator between a number and its title (golem-html ADR 0002).
module Golem.Doc.Numbering
  ( numberSeparator,
  )
where

import Data.Text (Text)
import Data.Text qualified as T

{- | The text between a number and its title, from the language of the book
(a BCP 47 tag) and the number: an ideographic space when the primary
subtag is @ja@, a space otherwise, and nothing when the number already
ends with a space, an ideographic space or a tab.
-}
numberSeparator :: Text -> Text -> Text
numberSeparator lang num
  | maybe False ((`elem` [' ', '\x3000', '\t']) . snd) (T.unsnoc num) = ""
  | T.toLower (T.takeWhile (/= '-') lang) == "ja" = "\x3000"
  | otherwise = " "
