{- | The look of the characters of a paragraph (golem-driver ADR 0004):
font roles, size, synthetic bold and slant, and colour. golem-layout
does not interpret the role and swatch names; it hands them to the
measuring functions and keeps them on the boxes for later stages.
-}
module Golem.Layout.Look
  ( Look (..),
    plainLook,
  )
where

import Data.Text (Text)

data Look = Look
  { -- | the font role of Japanese characters
    lkFace :: !Text,
    -- | the font role of Latin characters
    lkLatinFace :: !Text,
    -- | the size in sp
    lkSize :: !Integer,
    -- | synthetic bold
    lkEmbolden :: !Bool,
    -- | synthetic slant (on the side the italic role does not cover)
    lkSlant :: !Bool,
    -- | the swatch; Nothing is the default colour
    lkColor :: !(Maybe Text)
  }
  deriving stock (Eq, Ord, Show)

-- | One role for both scripts at a size, upright, regular, default colour.
plainLook :: Text -> Integer -> Look
plainLook role size = Look role role size False False Nothing
