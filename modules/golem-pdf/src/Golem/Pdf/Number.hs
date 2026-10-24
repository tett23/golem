{- | Numbers in PDF syntax (golem-pdf ADR 0001): sp converted to pt,
rounded to four decimals half to even with integer arithmetic, trailing
zeros removed. 'showRationalDigits' also writes the matrices of PDF
figures, whose entries are small (golem-pdf ADR 0008).
-}
module Golem.Pdf.Number
  ( spToPt,
    showDecimal4,
    showRational4,
    showRationalDigits,
  )
where

import Data.Ratio ((%))
import Data.Text (Text)
import Golem.Syntax.Text (showRationalDigits)

-- | 1pt = 65536sp.
spToPt :: Integer -> Text
spToPt sp = showRational4 (sp % 65536)

showRational4 :: Rational -> Text
showRational4 = showRationalDigits 4

-- | An integer number of ten-thousandths.
showDecimal4 :: Integer -> Text
showDecimal4 q = showRationalDigits 4 (q % 10000)
