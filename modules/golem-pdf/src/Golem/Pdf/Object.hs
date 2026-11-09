{- | The objects of a PDF before they are written (golem-pdf ADR 0001), so
that Golem.Pdf.X4.verify can check them (golem-cli ADR 0006).
-}
module Golem.Pdf.Object
  ( Obj,
    ObjOf (..),
    PdfObjects (..),
  )
where

import Data.ByteString (ByteString)
import Data.Text (Text)

{- | An object whose references are @r@: the numbers of the PDF written
('Obj'), or the keys of the objects of an imported PDF
('Golem.Pdf.Import.ImportedPage', docs/adr ADR 0247).
-}
data ObjOf r
  = ODict ![(Text, ObjOf r)]
  | OArr ![ObjOf r]
  | OName !Text
  | OInt !Integer
  | OReal !Text
  | OStr !ByteString
  | OHex !ByteString
  | ORef !r
  | OBool !Bool
  | OStream ![(Text, ObjOf r)] !ByteString
  | ONull
  deriving stock (Eq, Show)

-- | An object of the PDF written, its references numbered from 1.
type Obj = ObjOf Int

{- | A whole PDF as objects: the version of the header, the objects
numbered from 1 in order, and the trailer dictionary.
-}
data PdfObjects = PdfObjects
  { pdfVersion :: !Text,
    pdfObjects :: ![Obj],
    pdfTrailer :: !Obj
  }
  deriving stock (Eq, Show)
