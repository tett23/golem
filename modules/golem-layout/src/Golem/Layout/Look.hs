{- | The look of the characters of a paragraph (golem-driver ADR 0004):
font roles, size, synthetic bold and slant, and colour. golem-layout
does not interpret the role and swatch names; it hands them to the
measuring functions and keeps them on the boxes for later stages.
-}
module Golem.Layout.Look
  ( Look (..),
    Kerning (..),
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

{- | The kerning method (docs/adr/0020): metrics kerns pairs of Latin and of
Japanese characters, japanese-equal-width only Latin ones (Japanese stays
full-width), none nothing. Optical kerning is rejected before layout.
-}
data Kerning = KernMetrics | KernJapaneseEqualWidth | KernNone
  deriving stock (Eq, Ord, Show)

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
    lkColor :: !(Maybe Text),
    -- | the kerning method (docs/adr/0020)
    lkKerning :: !Kerning,
    -- | the space after each character in 1/1000 of the size
    lkTracking :: !Int,
    -- | palt (vpal in vertical text) on Japanese characters
    lkProportional :: !Bool,
    -- | in sp: up in horizontal text, right in vertical text
    lkBaselineShift :: !Integer,
    {- | the text is code (golem-driver ADR 0017): breaks only at spaces and
    after a slash, no hyphenation and no aki between its characters
    -} lkCode :: !Bool
  }
  deriving stock (Eq, Ord, Show)

{- | One role for both scripts at a size, upright, regular, default colour,
metrics kerning, no tracking, no proportional metrics, no baseline shift,
not code.
-}
plainLook :: Text -> Integer -> Look
plainLook role size = Look role role size noSynthetic noSynthetic Nothing KernMetrics 0 False 0 False
