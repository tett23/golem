-- | Monochrome figure colours shared by raster and PDF import (root ADR 0403).
module Golem.Typeset.FigureColor
  ( Cmyk,
    RasterKind (..),
    RasterAnalysis (..),
    analyzeRaster,
  )
where

import Data.Text (Text)
import Golem.Pdf qualified as P

-- | The selected swatch, each component as a percentage from zero to one hundred.
type Cmyk = (Int, Int, Int, Int)

data RasterKind
  = Unpainted
  | Grayscale
  | SolidRgb !(Rational, Rational, Rational)
  | SolidCmyk !(Rational, Rational, Rational, Rational)
  | Multicolor
  deriving stock (Eq, Show)

data RasterAnalysis = RasterAnalysis
  { raKind :: !RasterKind,
    -- | Converted uncompressed DeviceCMYK pixels, with dimensions and alpha unchanged.
    raImage :: !(Maybe P.ImageData)
  }
  deriving stock (Eq, Show)

analyzeRaster :: Cmyk -> P.ImageData -> Either Text RasterAnalysis
analyzeRaster _ _ = Right (RasterAnalysis Multicolor Nothing)
