{- | The paths of @style.toml@ (root ADR 0437): a string of the path data
of SVG (M, L, C and Z, absolute coordinates), read by golem-geometry,
and the unit of its coordinates by the key @unit@: @mm@ (the default),
@pt@ or @Q@. Each coordinate becomes sp once, from its exact decimal.
The keys that hold a path are those of the text frames (root ADR 0438).
-}
module Golem.Project.PathData
  ( Path (..),
    SubPath (..),
    Segment (..),
    PathDataError (..),
    PathUnitError (..),
    pathUnit,
    readStylePath,
  )
where

import Data.Text (Text)
import Golem.Geometry (Path (..), PathDataError (..), Segment (..), SubPath (..), parsePathData)
import Golem.Length (Unit (..), toSp)

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
