{- | A rectangle in PDF coordinates (docs/adr ADR 0088): the lower left
corner and the size, in sp, with the origin at the bottom-left corner of
the page. The page boxes and the marks of Golem.Pdf.Writer are written
with it, and golem-layout-spec re-exports it for the page geometry. It
is golem-geometry's, re-exported here (root ADR 0437).
-}
module Golem.Pdf.Rect (Rect (..)) where

import Golem.Geometry (Rect (..))
