{- | How the source is read (docs/adr ADR 0013): the settings of the
[source] table of manifest.toml, shared by the manifest and the settings
a file gives itself.
-}
module Golem.Parser.SourceSettings
  ( ParagraphSeparator (..),
    SourceSettings (..),
    defaultSourceSettings,
    sourceKeys,
    paragraphSeparators,
  )
where

import Data.Text (Text)

-- | How paragraphs are separated: by a blank line, or by a newline.
data ParagraphSeparator = BlankLineSeparated | LineSeparated
  deriving stock (Eq, Show)

newtype SourceSettings = SourceSettings
  { ssParagraphSeparator :: ParagraphSeparator
  }
  deriving stock (Eq, Show)

-- | The line style, one paragraph a line (docs/adr/0193).
defaultSourceSettings :: SourceSettings
defaultSourceSettings = SourceSettings LineSeparated

paragraphSeparators :: [(Text, ParagraphSeparator)]
paragraphSeparators = [("blank-line", BlankLineSeparated), ("line", LineSeparated)]

{- | The keys of [source] and how a string value of each changes the
settings. An invalid value gives a message listing the accepted values.
-}
sourceKeys :: [(Text, Text -> Either Text (SourceSettings -> SourceSettings))]
sourceKeys = [("paragraph-separator", paragraphSeparator)]
  where
    paragraphSeparator v = case lookup v paragraphSeparators of
      Just separator -> Right (\s -> s {ssParagraphSeparator = separator})
      Nothing -> Left ("paragraph-separator は \"blank-line\" か \"line\" です: " <> v)
