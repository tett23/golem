{- | The structure tree of a tagged PDF (docs/adr ADR 0183): structure
elements of the standard types of ISO 32000-1 only, so that no RoleMap is
written, whose leaves are the marked content the pages draw.
-}
module Golem.Pdf.Structure
  ( LeafId (..),
    AnnotId (..),
    StructType (..),
    structTypeName,
    Attribute (..),
    StructElem (..),
    StructKid (..),
    structElem,
    elemLeaves,
  )
where

import Data.Text (Text)
import Golem.Pdf.Object (Obj)

{- | A leaf of the structure tree: the content of one element that the
pages draw as marked content. The caller names leaves; only their equality
and order matter.
-}
newtype LeafId = LeafId [Int]
  deriving stock (Eq, Ord, Show)

-- | A link annotation, by its place among the annotations of the document (docs/adr ADR 0182).
newtype AnnotId = AnnotId Int
  deriving stock (Eq, Ord, Show)

-- | The standard structure types of ISO 32000-1 14.8.4 that Golem writes.
data StructType
  = SDocument
  | SDiv
  | SP
  | SH1
  | SH2
  | SH3
  | SH4
  | SH5
  | SH6
  | SL
  | SLI
  | SLbl
  | SLBody
  | STable
  | STR
  | STH
  | STD
  | SCaption
  | SFigure
  | STOC
  | STOCI
  | SIndex
  | SBibEntry
  | SNote
  | SReference
  | SCode
  | SLink
  | SSpan
  | SRuby
  | SRB
  | SRT
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The name of a structure type, as written after /S.
structTypeName :: StructType -> Text
structTypeName = \case
  SDocument -> "Document"
  SDiv -> "Div"
  SP -> "P"
  SH1 -> "H1"
  SH2 -> "H2"
  SH3 -> "H3"
  SH4 -> "H4"
  SH5 -> "H5"
  SH6 -> "H6"
  SL -> "L"
  SLI -> "LI"
  SLbl -> "Lbl"
  SLBody -> "LBody"
  STable -> "Table"
  STR -> "TR"
  STH -> "TH"
  STD -> "TD"
  SCaption -> "Caption"
  SFigure -> "Figure"
  STOC -> "TOC"
  STOCI -> "TOCI"
  SIndex -> "Index"
  SBibEntry -> "BibEntry"
  SNote -> "Note"
  SReference -> "Reference"
  SCode -> "Code"
  SLink -> "Link"
  SSpan -> "Span"
  SRuby -> "Ruby"
  SRB -> "RB"
  SRT -> "RT"

-- | An attribute object: its owner (Layout, List, Table) and its entries.
data Attribute = Attribute
  { atOwner :: !Text,
    atEntries :: ![(Text, Obj)]
  }
  deriving stock (Eq, Show)

data StructElem = StructElem
  { -- | the standard types of ISO 32000-1 14.8.4 only
    seType :: !StructType,
    seLang :: !(Maybe Text),
    seAlt :: !(Maybe Text),
    seId :: !(Maybe Text),
    seAttrs :: ![Attribute],
    seKids :: ![StructKid]
  }
  deriving stock (Eq, Show)

data StructKid = KidElem !StructElem | KidLeaf !LeafId | KidAnnot !AnnotId
  deriving stock (Eq, Show)

-- | An element of a type with its kids, and nothing else.
structElem :: StructType -> [StructKid] -> StructElem
structElem t = StructElem t Nothing Nothing Nothing []

-- | The leaves of an element and of the elements inside it, in order.
elemLeaves :: StructElem -> [LeafId]
elemLeaves e =
  concat
    [ case k of
        KidElem c -> elemLeaves c
        KidLeaf l -> [l]
        KidAnnot _ -> []
    | k <- seKids e
    ]
