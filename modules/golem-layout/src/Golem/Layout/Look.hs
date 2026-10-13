{- | The look of the characters of a paragraph (golem-driver ADR 0004):
font roles, size, synthetic bold and slant, and colour. golem-layout
does not interpret the role and swatch names; it hands them to the
measuring functions and keeps them on the boxes for later stages.
-}
module Golem.Layout.Look
  ( Look (..),
    Synthetic (..),
    noSynthetic,
    plainLook,
  )
where

import Data.Text (Text)

-- | Synthetic bold and slant of one side, Japanese or Latin (docs/adr ADR 0005).
data Synthetic = Synthetic {synBold :: !Bool, synSlant :: !Bool}
  deriving stock (Eq, Ord, Show)

noSynthetic :: Synthetic
noSynthetic = Synthetic False False

data Look = Look
  { -- | the font role of Japanese characters
    lkFace :: !Text,
    -- | the font role of Latin characters
    lkLatinFace :: !Text,
    -- | the size in sp
    lkSize :: !Integer,
    -- | synthetic bold and slant of the Japanese side
    lkSynthetic :: !Synthetic,
    -- | synthetic bold and slant of the Latin side
    lkLatinSynthetic :: !Synthetic,
    -- | the swatch; Nothing is the default colour
    lkColor :: !(Maybe Text)
  }
  deriving stock (Eq, Ord, Show)

-- | One role for both scripts at a size, upright, regular, default colour.
plainLook :: Text -> Integer -> Look
plainLook role size = Look role role size noSynthetic noSynthetic Nothing
