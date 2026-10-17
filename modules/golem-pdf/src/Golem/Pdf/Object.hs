{- | The objects of a PDF before they are written (golem-pdf ADR 0001), so
that Golem.Pdf.X4.verify can check them (golem-cli ADR 0006).
-}
module Golem.Pdf.Object
  ( Obj (..),
    PdfObjects (..),
  )
where

import Data.ByteString (ByteString)
import Data.Text (Text)

data Obj
  = ODict ![(Text, Obj)]
  | OArr ![Obj]
  | OName !Text
  | OInt !Integer
  | OReal !Text
  | OStr !ByteString
  | OHex !ByteString
  | ORef !Int
  | OBool !Bool
  | OStream ![(Text, Obj)] !ByteString
  | ONull
  deriving stock (Eq, Show)

{- | A whole PDF as objects: the version of the header, the objects
numbered from 1 in order, and the trailer dictionary.
-}
data PdfObjects = PdfObjects
  { pdfVersion :: !Text,
    pdfObjects :: ![Obj],
    pdfTrailer :: !Obj
  }
  deriving stock (Eq, Show)
