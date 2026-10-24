{- | The string functions of Python that the converters were first written
with, so that the converters give the same bytes (docs/adr/0023), and the
functions on lines that more than one converter uses.
-}
module Golem.Fixtures.Python
  ( isPySpace,
    isPyDecimal,
    pyStrip,
    pyLStrip,
    pyRStrip,
    collapseSpace,
    universalNewlines,
    specialLineStart,
    escapeLineStart,
    toBlocks,
    indentOf,
    escapeSlot,
  )
where

import Data.Char (GeneralCategory (..), generalCategory)
import Data.Text (Text)
import Data.Text qualified as T

-- | @str.isspace@ of one character, which is also @\\s@ of @re@.
isPySpace :: Char -> Bool
isPySpace c =
  ('\t' <= c && c <= '\r')
    || ('\x1c' <= c && c <= '\x1f')
    || c `elem` [' ', '\x85', '\xa0', '\x1680', '\x2028', '\x2029', '\x202f', '\x205f', '\x3000']
    || ('\x2000' <= c && c <= '\x200a')

-- | @\\d@ of @re@: a decimal digit of any script.
isPyDecimal :: Char -> Bool
isPyDecimal c = generalCategory c == DecimalNumber

pyStrip, pyLStrip, pyRStrip :: Text -> Text
pyStrip = T.dropAround isPySpace
pyLStrip = T.dropWhile isPySpace
pyRStrip = T.dropWhileEnd isPySpace

-- | @re.sub(r"\\s+", " ", s)@.
collapseSpace :: Text -> Text
collapseSpace = T.concat . map collapse . T.groupBy (\a b -> isPySpace a == isPySpace b)
  where
    collapse run
      | T.any isPySpace run = " "
      | otherwise = run

{- | The newlines of a file that Python opens as text: @\\r\\n@ and @\\r@
become @\\n@.
-}
universalNewlines :: Text -> Text
universalNewlines = T.replace "\r" "\n" . T.replace "\r\n" "\n"

-- | The characters that make a line something other than a paragraph.
specialLineStart :: [Char]
specialLineStart = "#-+=@|"

-- | A backslash before a line that starts with one of 'specialLineStart'.
escapeLineStart :: Text -> Text
escapeLineStart s = case T.uncons s of
  Just (c, _) | c `elem` specialLineStart -> "\\" <> s
  _ -> s

-- | Blocks of lines between blank lines, each line without trailing space.
toBlocks :: [Text] -> [[Text]]
toBlocks = filter (not . null) . go []
  where
    go cur [] = [reverse cur]
    go cur (l : ls)
      | T.null (pyStrip l) = reverse cur : go [] ls
      | otherwise = go (pyRStrip l : cur) ls

-- | The number of spaces a line starts with.
indentOf :: Text -> Int
indentOf = T.length . T.takeWhile (== ' ')

-- | A text escaped for a slot of a command: backslashes, brackets and bars.
escapeSlot :: Text -> Text
escapeSlot = T.replace "|" "\\|" . T.replace "]" "\\]" . T.replace "[" "\\[" . T.replace "\\" "\\\\"
