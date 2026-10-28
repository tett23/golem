-- | The constants and helpers that the tests of golem-layout-spec share.
module Fixtures
  ( pt,
    mm18,
    mm20,
    grid,
    geom,
  )
where

import Golem.LayoutSpec
import Golem.Project.Style
import Golem.Syntax

pt :: Integer -> Sp
pt = Sp . (* 65536)

-- | 18mm and 20mm, rounded once from exact rationals.
mm18, mm20 :: Sp
mm18 = 3343884
mm20 = 3715427

-- | 10pt characters on a 17pt pitch, 18mm from the top, 20mm from the gutter.
grid :: Int -> Int -> Int -> Maybe Dim -> Grid
grid chars ls cols gap = Grid (Abs (pt 10)) chars ls (Abs (pt 17)) cols gap (Abs mm18) (Abs mm20)

-- | The geometry of a style that has no errors.
geom :: Style -> PageGeometry
geom s = either (error . show) id (pageGeometry (FileId 0) False s)
