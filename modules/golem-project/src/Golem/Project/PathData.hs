{- | The paths of @style.toml@ (root ADR 0437): a string of the path data
of SVG (M, L, C and Z, absolute coordinates), read by golem-geometry,
and the unit of its coordinates by the key @unit@: @mm@ (the default),
@pt@ or @Q@. Each coordinate becomes sp once, from its exact decimal.
The keys that hold a path are those of the text frames (root ADR 0438).

The outlines of figures (root ADR 0464) are paths of no unit, in the
coordinates of their image: 'readOutlinePath' keeps each coordinate as an
integer, 'outlineScale' times its value, rounded once half to even, so
the outline is scaled to the size of the placed image from exact
integers.
-}
module Golem.Project.PathData
  ( Path (..),
    SubPath (..),
    Segment (..),
    PathDataError (..),
    PathUnitError (..),
    pathUnit,
    readStylePath,
    outlineScale,
    readOutlinePath,
  )
where

import Data.Text (Text)
import Golem.Geometry (Path (..), PathDataError (..), Segment (..), SubPath (..), parsePathData)
import Golem.Length (Sp (..), Unit (..), toSp)

-- | The value of @unit@ is not one of @mm@, @pt@ and @Q@.
newtype PathUnitError = PathUnitError Text
  deriving stock (Eq, Show)

-- | The unit of the coordinates: mm when there is no @unit@.
pathUnit :: Maybe Text -> Either PathUnitError Unit
pathUnit = \case
  Nothing -> Right Mm
  Just "mm" -> Right Mm
  Just "pt" -> Right Pt
  Just "Q" -> Right Q
  Just other -> Left (PathUnitError other)

-- | A path of @style.toml@ in its unit.
readStylePath :: Unit -> Text -> Either PathDataError Path
readStylePath unit = parsePathData (toSp unit)

-- | How many units of a stored outline make one unit of its image: 65536, as sp to pt.
outlineScale :: Integer
outlineScale = 65536

-- | A path of no unit (root ADR 0464), each coordinate kept as 'outlineScale' times its value.
readOutlinePath :: Text -> Either PathDataError Path
readOutlinePath = parsePathData (\r -> Sp (round (r * fromInteger outlineScale)))
