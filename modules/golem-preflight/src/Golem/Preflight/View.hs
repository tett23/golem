{- | What the checks of golem preflight read (golem-cli ADR 0006): the PDF
as laid out, page by page, made by golem-driver while it writes the PDF.
Lengths are in sp, in the coordinates of the trimmed page (the origin at
its lower left), so crop marks are not in a view.
-}
module Golem.Preflight.View
  ( Cmyk,
    View (..),
    FontView (..),
    PageView (..),
    ImageView (..),
    LineView (..),
    GlyphView (..),
    GlyphPart (..),
    -- where the size of a glyph was decided, re-exported for the tests
    -- and the callers of this module (golem-cli ADR 0008)
    SizeSource (..),
    RuleView (..),
  )
where

import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Golem.LayoutSpec (Rect (..))
import Golem.Pdf (FigureContent, X4Problem)
import Golem.Project.Style (SizeSource (..), Sp)
import Golem.Syntax (SrcSpan)

-- | Process colour in percent.
type Cmyk = (Int, Int, Int, Int)

data View = View
  { vwPages :: ![PageView],
    -- | the embedded fonts: path and form
    vwFonts :: ![FontView],
    -- | the swatches used on the pages (text, rules, backgrounds)
    vwSwatchesUsed :: !(Map Text Cmyk),
    -- | [page] bleed of style.toml
    vwBleed :: !Sp,
    -- | the ICC profile of [color] intent, when there is one
    vwIntentProfile :: !(Maybe ByteString),
    -- | the PDF/X-4 requirements the PDF does not meet (Golem.Pdf.X4.verify)
    vwX4 :: ![X4Problem],
    -- | the bytes of the PDF
    vwPdf :: !ByteString,
    -- | where diagnostics about style.toml point: its top, or the manifest's
    vwStyleSpan :: !SrcSpan,
    -- | the top of manifest.toml
    vwManifestSpan :: !SrcSpan
  }
  deriving stock (Eq, Show)

-- | An embedded font: its path in style.toml and its form (@cff@, @cff2@ or @truetype@).
data FontView = FontView
  { fvPath :: !Text,
    fvFormat :: !Text
  }
  deriving stock (Eq, Show)

data PageView = PageView
  { -- | the page of the PDF, from 1
    pvIndex :: !Int,
    -- | the trimmed page
    pvTrim :: !Rect,
    pvImages :: ![ImageView],
    pvLines :: ![LineView],
    pvGlyphs :: ![GlyphView],
    pvRules :: ![RuleView],
    -- | nothing but the master page (running head, folio)
    pvBlank :: !Bool,
    -- | the gutter (のど) is on the left of the page
    pvGutterLeft :: !Bool
  }
  deriving stock (Eq, Show)

data ImageView = ImageView
  { ivRect :: !Rect,
    -- | the image, or the page of a PDF figure (golem-pdf ADR 0008)
    ivContent :: !FigureContent,
    -- | the @figure block
    ivSpan :: !SrcSpan,
    ivPath :: !Text,
    -- | whether the figure is turned onto its page (golem-driver ADR 0034): its pixel width lies along the height of the rectangle
    ivTurned :: !Bool
  }
  deriving stock (Eq, Show)

-- | A line of text: its face (from the line start to the line end, the height of the size).
data LineView = LineView
  { lvRect :: !Rect,
    -- | what the line is, as messages name it: 本文の行, 柱, ノンブル…
    lvKind :: !Text,
    lvSpan :: !SrcSpan,
    -- | how far an overfull line sticks out
    lvOverfull :: !(Maybe Sp)
  }
  deriving stock (Eq, Show)

data GlyphView = GlyphView
  { -- | the characters the glyph stands for
    gvText :: !Text,
    -- | the path of the font
    gvFont :: !Text,
    gvGlyph :: !Int,
    gvSize :: !Sp,
    -- | the swatch of the text, when it has one
    gvColor :: !(Maybe (Text, Cmyk)),
    -- | the definition of style.toml that decided the size (golem-cli ADR 0008)
    gvSizeSource :: !SizeSource,
    -- | a character of the text, of a ruby or a kenten mark
    gvPart :: !GlyphPart,
    -- | where the character is in the source: the inline text, or the element that made it
    gvSpan :: !SrcSpan,
    -- | the block of the line the glyph is on, where G09002 reports it
    gvLineSpan :: !SrcSpan
  }
  deriving stock (Eq, Show)

{- | What a glyph is (golem-cli ADR 0008): a ruby and a kenten mark take a
size from the character they are on, so small ones are a cause of their own.
-}
data GlyphPart = PartBase | PartRuby | PartKenten
  deriving stock (Eq, Ord, Show)

-- | A rule Golem draws (table rules); crop marks are not in a view.
data RuleView = RuleView
  { rvKind :: !Text,
    rvWeight :: !Sp,
    rvRect :: !Rect
  }
  deriving stock (Eq, Show)
