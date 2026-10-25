{- | A rectangle in PDF coordinates (docs/adr ADR 0088): the lower left
corner and the size, in sp, with the origin at the bottom-left corner of
the page. The page boxes and the marks of Golem.Pdf.Writer are written
with it, and golem-layout-spec re-exports it for the page geometry.
-}
module Golem.Pdf.Rect (Rect (..)) where

data Rect = Rect {rectX :: !Integer, rectY :: !Integer, rectW :: !Integer, rectH :: !Integer}
  deriving stock (Eq, Show)
