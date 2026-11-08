{- | The glyph runs of a box (docs/adr ADR 0227): its glyphs in the order
of its text, a new run wherever the key of the font (its face, synthetic
bold and slant, and whether the glyph is turned) changes.
-}
module Golem.Typeset.GlyphRuns
  ( glyphRuns,
  )
where

import Data.Function (on)
import Data.List (groupBy)

{- | The glyphs in their order, grouped by the key of their font: the
glyphs of one key in a row are one run; two runs of the same key with
another between them stay two (docs/adr ADR 0227, R2).
-}
glyphRuns :: (Eq k) => [(k, a)] -> [(k, [a])]
glyphRuns xs = [(k, map snd run) | run@((k, _) : _) <- groupBy ((==) `on` fst) xs]
