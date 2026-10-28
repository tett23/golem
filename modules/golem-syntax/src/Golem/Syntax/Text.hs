{- | Small functions on text that packages with nothing else in common
need: golem-syntax is the one package they all depend on. They are kept
in this one module, and are not re-exported by "Golem.Syntax", so that
they do not spread over golem-syntax or clash with local names.
-}
module Golem.Syntax.Text
  ( tshow,
    escapeXml,
    isSpaceTab,
  )
where

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
