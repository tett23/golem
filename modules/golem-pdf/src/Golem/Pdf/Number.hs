{- | Numbers in PDF syntax (golem-pdf ADR 0001): sp converted to pt,
rounded to four decimals half to even with integer arithmetic, trailing
zeros removed. 'showRationalDigits' also writes the matrices of PDF
figures, whose entries are small (golem-pdf ADR 0008).
-}
module Golem.Pdf.Number
  ( spToPt,
    showRational4,
    showRationalDigits,
  )
where

import Data.Text (Text)
import Golem.Syntax.Length (Sp, ptText)
import Golem.Syntax.Text (showRationalDigits)

-- | Sp as pt, at most four decimals (docs/adr ADR 0103).
spToPt :: Sp -> Text
spToPt = ptText

showRational4 :: Rational -> Text
showRational4 = showRationalDigits 4
