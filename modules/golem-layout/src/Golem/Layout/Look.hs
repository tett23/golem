{- | The look of the characters of a paragraph (golem-driver ADR 0004):
font roles, size, synthetic bold and slant, and colour. golem-layout
does not interpret the role and swatch names; it hands them to the
measuring functions and keeps them on the boxes for later stages.
-}
module Golem.Layout.Look
  ( Look (..),
    Kerning (..),
    Synthetic (..),
    plainLook,
    KentenShape (..),
    kentenChar,
    kentenShapeName,
    kentenShapeFromName,
    SizeSource (..),
    BoxSource,
    noBoxSource,
  )
where

import Data.Text (Text)
import Golem.Length (Sp)
import Golem.Project.Style (SizeSource (..))
import Golem.Syntax (FileId (..), SrcSpan, mkSpan)

{- | Where the size of a box comes from and where its characters are in the
source (golem-cli ADR 0008), for golem preflight. Kept beside the look,
not in it: two boxes of one look may come from different definitions,
and nothing that sets or draws the text reads it.
-}
type BoxSource = (SizeSource, SrcSpan)

-- | The source of a box nothing names: the grid, at the start of file 0.
noBoxSource :: BoxSource
noBoxSource = (SourceGrid, mkSpan (FileId 0) 0 0)

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

{- | The shape of kenten (golem-driver ADR 0019): the ten of CSS
text-emphasis-style, filled and open.
-}
data KentenShape
  = KentenSesame
  | KentenOpenSesame
  | KentenDot
  | KentenOpenDot
  | KentenCircle
  | KentenOpenCircle
  | KentenDoubleCircle
  | KentenOpenDoubleCircle
  | KentenTriangle
  | KentenOpenTriangle
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The character drawn for a shape.
kentenChar :: KentenShape -> Char
kentenChar = \case
  KentenSesame -> '\xFE45'
  KentenOpenSesame -> '\xFE46'
  KentenDot -> '\x2022'
  KentenOpenDot -> '\x25E6'
  KentenCircle -> '\x25CF'
  KentenOpenCircle -> '\x25CB'
  KentenDoubleCircle -> '\x25C9'
  KentenOpenDoubleCircle -> '\x25CE'
  KentenTriangle -> '\x25B2'
  KentenOpenTriangle -> '\x25B3'

-- | The name of a shape in the source and in style.toml.
kentenShapeName :: KentenShape -> Text
kentenShapeName = \case
  KentenSesame -> "sesame"
  KentenOpenSesame -> "open-sesame"
  KentenDot -> "dot"
  KentenOpenDot -> "open-dot"
  KentenCircle -> "circle"
  KentenOpenCircle -> "open-circle"
  KentenDoubleCircle -> "double-circle"
  KentenOpenDoubleCircle -> "open-double-circle"
  KentenTriangle -> "triangle"
  KentenOpenTriangle -> "open-triangle"

-- | The shape of a name; Nothing for a name not in the list.
kentenShapeFromName :: Text -> Maybe KentenShape
kentenShapeFromName n = lookup n [(kentenShapeName s, s) | s <- [minBound .. maxBound]]

data Look = Look
  { -- | the font role of Japanese characters
    lkFace :: !Text,
    -- | the font role of Latin characters
    lkLatinFace :: !Text,
    -- | the size in sp
    lkSize :: !Sp,
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
    lkBaselineShift :: !Sp,
    {- | the text is code (golem-driver ADR 0017): breaks only at spaces and
    after a slash, no hyphenation and no aki between its characters
    -} lkCode :: !Bool,
    {- | the text is a URL (golem-doc ADR 0005): broken as code, but only
    after the last slash of a run of slashes, and kerned
    -} lkUrl :: !Bool,
    -- | the shape of kenten (golem-driver ADR 0019); Nothing is no kenten
    lkKenten :: !(Maybe KentenShape),
    {- | the swatch of the background of inline code (golem-driver ADR
    0029); Nothing is no background
    -} lkBackground :: !(Maybe Text),
    -- | the padding before and after a run of code along the line, in sp (golem-driver ADR 0029)
    lkPadding :: !Sp
  }
  deriving stock (Eq, Ord, Show)

{- | One role for both scripts at a size, upright, regular, default colour,
metrics kerning, no tracking, no proportional metrics, no baseline shift,
not code, not a URL, no kenten, no background and no padding.
-}
plainLook :: Text -> Sp -> Look
plainLook role size = Look role role size noSynthetic noSynthetic Nothing KernMetrics 0 False 0 False False Nothing Nothing 0
