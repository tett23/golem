{- | The deterministic PDF writer (golem-pdf ADR 0001): PDF 1.6, objects
numbered in a fixed order, sorted dictionary keys, a classic xref table,
numbers rounded with integer arithmetic, Flate by the bundled zlib.
-}
module Golem.Pdf.Writer
  ( Sp,
    GlyphId,
    FontRef (..),
    ImageRef (..),
    FormRef (..),
    Swatch (..),
    RunStyle (..),
    Mark (..),
    Page (..),
    FontProgram (..),
    Font (..),
    Document (..),
    Obj (..),
    PdfObjects (..),
    documentObjects,
    writePdf,
    contentStream,
    pdfTextString,
    documentId,
    instanceId,
    pdfDate,
  )
where

import Codec.Compression.Zlib qualified as Z
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.List (nub, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, isJust)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.UUID qualified as UUID
import Data.UUID.V5 qualified as V5
import Golem.LayoutSpec (Rect (..))
import Golem.Pdf.Image
import Golem.Pdf.Import
import Golem.Pdf.Number
import Golem.Pdf.Object
import Golem.Pdf.Sha256 (sha256)
import Golem.Pdf.Srgb (srgbProfile)
import Golem.Pdf.X4
import Text.Printf (printf)

type Sp = Integer

type GlyphId = Int

newtype FontRef = FontRef Int
  deriving stock (Eq, Ord, Show)

newtype ImageRef = ImageRef Int
  deriving stock (Eq, Ord, Show)

-- | A Form XObject: a page of a PDF figure (ADR 0008).
newtype FormRef = FormRef Int
  deriving stock (Eq, Ord, Show)

-- | Process colour in percent.
data Swatch = Swatch !Int !Int !Int !Int
  deriving stock (Eq, Show)

{- | How a styled glyph run is drawn (golem-driver ADR 0004): horizontal
scaling in permille, turned for vertical writing, a slant (0 for none)
and the width of the outline stroke of synthetic bold (0 for none).
-}
data RunStyle = RunStyle
  { rsScale :: !Int,
    rsRotated :: !Bool,
    rsSlant :: !Rational,
    rsEmbolden :: !Sp
  }
  deriving stock (Eq, Show)

data Mark
  = -- | font, size, glyphs with their origins
    GlyphRun !FontRef !Sp ![(GlyphId, Sp, Sp)]
  | -- | a glyph run drawn with horizontal scaling in permille (golem-layout ADR 0005)
    ScaledGlyphRun !FontRef !Sp !Int ![(GlyphId, Sp, Sp)]
  | {- | Latin text in vertical writing: glyphs turned 90° clockwise, each
    origin given (golem-layout ADR 0002)
    -}
    RotatedGlyphRun !FontRef !Sp ![(GlyphId, Sp, Sp)]
  | Rule !Rect
  | Image !ImageRef !Rect
  | SetColor !Swatch
  | -- | a glyph run slanted or emboldened (golem-driver ADR 0004)
    StyledGlyphRun !RunStyle !FontRef !Sp ![(GlyphId, Sp, Sp)]
  | -- | marks drawn inside q and Q, so the graphics state is restored
    Saved ![Mark]
  | -- | marks drawn with the origin moved, inside q and Q (ADR 0004)
    Translated !Sp !Sp ![Mark]
  | {- | crop mark lines filled in the registration colour, the Separation
    of the colorant All, inside q and Q (ADR 0007). The only mark that
    writes a Separation; Golem.Pdf does not export it.
    -}
    RegistrationRules ![Rect]
  | {- | a page of a PDF figure, its crop box fitted to the rectangle
    without keeping its proportions (ADR 0008)
    -}
    Form !FormRef !Rect
  deriving stock (Eq, Show)

data Page = Page
  { pageMediaBox :: !Rect,
    pageTrimBox :: !Rect,
    pageBleedBox :: !Rect,
    pageContent :: ![Mark]
  }
  deriving stock (Eq, Show)

{- | The embedded font program. An OpenType font with CFF outlines goes
into FontFile3 with the OpenType subtype (PDF 1.6).
-}
data FontProgram = TrueTypeProgram !ByteString | CffProgram !ByteString | OpenTypeProgram !ByteString
  deriving stock (Eq, Show)

{- | An embedded CID-keyed font, prepared by golem-font. Metrics are in
1/1000 of the em.
-}
data Font = Font
  { fontName :: !Text,
    fontProgram :: !FontProgram,
    fontVertical :: !Bool,
    fontWidths :: ![(GlyphId, Int)],
    fontVerticalAdvances :: ![(GlyphId, Int)],
    fontAscent :: !Int,
    fontDescent :: !Int,
    fontCapHeight :: !Int,
    fontStemV :: !Int,
    fontBBox :: !(Int, Int, Int, Int),
    fontItalicAngle :: !Int,
    fontToUnicode :: ![(GlyphId, Text)],
    -- | Registry, Ordering and Supplement of the CIDFont (ADR 0006)
    fontCidSystemInfo :: !(Text, Text, Int)
  }
  deriving stock (Eq, Show)

data Document = Document
  { docPages :: ![Page],
    docFonts :: !(Map FontRef Font),
    docImages :: !(Map ImageRef ImageData),
    -- | the pages of PDF figures (ADR 0008)
    docForms :: !(Map FormRef ImportedPage),
    docTitle :: !Text,
    -- | year, month, day of metadata.date
    docDate :: !(Integer, Int, Int),
    docId :: !ByteString,
    docInstanceId :: !ByteString,
    -- | the Producer, such as @Golem 0.1.0@ (ADR 0005); written as given
    docProducer :: !Text,
    -- | PDF/X-4 (golem-pdf ADR 0002)
    docPdfX :: !(Maybe PdfX)
  }

-- ------------------------------------------------------------------ identifiers

-- | The document ID: a name-based UUID (v5) of the book's identifier.
documentId :: Text -> ByteString
documentId bookId = BL.toStrict (UUID.toByteString (V5.generateNamed V5.namespaceURL (BS.unpack (TE.encodeUtf8 bookId))))

{- | The instance ID: the first 16 bytes of the SHA-256 of all inputs, each
prefixed by its length.
-}
instanceId :: [ByteString] -> ByteString
instanceId parts = BS.take 16 (sha256 (BS.concat [BL.toStrict (B.toLazyByteString (B.word64BE (fromIntegral (BS.length p)))) <> p | p <- parts]))

pdfDate :: (Integer, Int, Int) -> ByteString
pdfDate (y, m, d) = BC.pack (printf "D:%04d%02d%02d000000Z" y m d)

-- ------------------------------------------------------------------ content

num :: Sp -> B.Builder
num = B.byteString . TE.encodeUtf8 . spToPt

ratio :: Rational -> B.Builder
ratio = B.byteString . TE.encodeUtf8 . showRational4

-- | The content stream of a page, with resource names already assigned.
contentStream :: Map FontRef Int -> Map ImageRef Int -> [Mark] -> ByteString
contentStream fontNames imageNames = contentStreamWith fontNames imageNames Map.empty

-- | 'contentStream' with the names of the Form XObjects of PDF figures (ADR 0008).
contentStreamWith :: Map FontRef Int -> Map ImageRef Int -> Map FormRef Int -> [Mark] -> ByteString
contentStreamWith fontNames imageNames formNames marks = BL.toStrict (B.toLazyByteString (mconcat (map mark marks)))
  where
    sp = B.char7 ' '
    nl = B.char7 '\n'
    fontName' f = "/F" <> B.intDec (Map.findWithDefault 0 f fontNames)
    glyphs gs = mconcat ["1 0 0 1 " <> num x <> sp <> num y <> " Tm <" <> hex4 g <> "> Tj" <> nl | (g, x, y) <- gs]
    mark = \case
      GlyphRun f size gs -> "BT " <> fontName' f <> sp <> num size <> " Tf" <> nl <> glyphs gs <> "ET" <> nl
      ScaledGlyphRun f size scale gs ->
        "BT " <> fontName' f <> sp <> num size <> " Tf " <> ratio (toInteger scale % 10) <> " Tz" <> nl <> glyphs gs <> "ET" <> nl
      RotatedGlyphRun f size gs ->
        "BT " <> fontName' f <> sp <> num size <> " Tf" <> nl <> mconcat ["0 -1 1 0 " <> num x <> sp <> num y <> " Tm <" <> hex4 g <> "> Tj" <> nl | (g, x, y) <- gs] <> "ET" <> nl
      Rule (Rect x y w h) -> num x <> sp <> num y <> sp <> num w <> sp <> num h <> " re f" <> nl
      Image i (Rect x y w h) ->
        "q " <> num w <> " 0 0 " <> num h <> sp <> num x <> sp <> num y <> " cm /Im" <> B.intDec (Map.findWithDefault 0 i imageNames) <> " Do Q" <> nl
      SetColor (Swatch c m y k) ->
        let vs = mconcat [ratio (toInteger v % 100) <> sp | v <- [c, m, y, k]]
         in vs <> "k " <> vs <> "K" <> nl
      StyledGlyphRun (RunStyle scale rotated slant stroke) f size gs ->
        let matrix
              | rotated = "0 -1 1 " <> ratio (negate slant) <> sp
              | otherwise = "1 0 " <> ratio slant <> " 1 "
         in "q BT "
              <> fontName' f
              <> sp
              <> num size
              <> " Tf"
              <> (if scale /= 1000 then sp <> ratio (toInteger scale % 10) <> " Tz" else "")
              <> (if stroke > 0 then " 2 Tr " <> num stroke <> " w" else "")
              <> nl
              <> mconcat [matrix <> num x <> sp <> num y <> " Tm <" <> hex4 g <> "> Tj" <> nl | (g, x, y) <- gs]
              <> "ET Q"
              <> nl
      Saved ms -> "q" <> nl <> mconcat (map mark ms) <> "Q" <> nl
      Translated x y ms -> "q 1 0 0 1 " <> num x <> sp <> num y <> " cm" <> nl <> mconcat (map mark ms) <> "Q" <> nl
      RegistrationRules rs -> "q" <> nl <> "/Reg cs 1 scn" <> nl <> mconcat (map (mark . Rule) rs) <> "Q" <> nl
      -- the form maps its crop box to the unit square (its Matrix), so it is placed as an image is
      Form f (Rect x y w h) ->
        "q " <> num w <> " 0 0 " <> num h <> sp <> num x <> sp <> num y <> " cm /Fm" <> B.intDec (Map.findWithDefault 0 f formNames) <> " Do Q" <> nl
    hex4 g = B.string7 (printf "%04X" g)

-- ------------------------------------------------------------------ serialization

flate :: ByteString -> ByteString
flate = BL.toStrict . Z.compressWith Z.defaultCompressParams {Z.compressLevel = Z.compressionLevel 9} . BL.fromStrict

serialize :: Obj -> B.Builder
serialize = \case
  ODict kvs -> "<<" <> mconcat [" /" <> B.byteString (TE.encodeUtf8 k) <> " " <> serialize v | (k, v) <- sortOn fst kvs] <> " >>"
  OArr xs -> "[" <> mconcat (zipWith (\i x -> (if i == (0 :: Int) then "" else " ") <> serialize x) [0 ..] xs) <> "]"
  OName n -> "/" <> B.byteString (TE.encodeUtf8 n)
  OInt i -> B.integerDec i
  OReal t -> B.byteString (TE.encodeUtf8 t)
  OStr s -> "(" <> B.byteString (escape s) <> ")"
  OHex s -> "<" <> mconcat [B.word8HexFixed w | w <- BS.unpack s] <> ">"
  ORef n -> B.intDec n <> " 0 R"
  OBool b -> if b then "true" else "false"
  ONull -> "null"
  OStream d body -> serialize (ODict (("Length", OInt (fromIntegral (BS.length body))) : d)) <> "\nstream\n" <> B.byteString body <> "\nendstream"
  where
    escape = BS.concatMap (\w -> if w `elem` [40, 41, 92] then BS.pack [92, w] else BS.singleton w)

rectObj :: Rect -> Obj
rectObj (Rect x y w h) = OArr (map (OReal . spToPt) [x, y, x + w, y + h])

utf16Hex :: Text -> Obj
utf16Hex t = OHex (BS.pack [0xFE, 0xFF] <> TE.encodeUtf16BE t)

{- | A text string: printable ASCII as a literal string, otherwise UTF-16BE
with the byte order mark, as the Title (ADR 0005).
-}
pdfTextString :: Text -> Obj
pdfTextString t
  | T.all (\c -> c >= ' ' && c <= '~') t = OStr (TE.encodeUtf8 t)
  | otherwise = utf16Hex t

-- | Writes the document: 'documentObjects', serialized.
writePdf :: Document -> ByteString
writePdf = serializePdf . documentObjects

-- | The header, the objects, a classic xref table and the trailer.
serializePdf :: PdfObjects -> ByteString
serializePdf (PdfObjects version objects trailerDict) =
  let header = "%PDF-" <> B.byteString (TE.encodeUtf8 version) <> "\n%" <> B.word8 0xE2 <> B.word8 0xE3 <> B.word8 0xCF <> B.word8 0xD3 <> "\n"
      headerLen = 12 + BS.length (TE.encodeUtf8 version)
      bodies = [BL.toStrict (B.toLazyByteString (B.intDec n <> " 0 obj\n" <> serialize o <> "\nendobj\n")) | (n, o) <- zip [1 :: Int ..] objects]
      offsets = scanl (+) headerLen (map BS.length bodies)
      xrefAt = last offsets
      size = length objects + 1
      xref =
        "xref\n0 "
          <> B.intDec size
          <> "\n0000000000 65535 f \n"
          <> mconcat [B.string7 (printf "%010d 00000 n \n" o) | o <- init offsets]
      trailer =
        "trailer\n"
          <> serialize trailerDict
          <> "\nstartxref\n"
          <> B.intDec xrefAt
          <> "\n%%EOF\n"
   in BL.toStrict (B.toLazyByteString (header <> mconcat (map B.byteString bodies) <> xref <> trailer))

{- | The objects of the document. Objects are numbered: catalog, page tree,
each page (with its content), fonts and images in order of first
reference, then the document information.
-}
documentObjects :: Document -> PdfObjects
documentObjects doc =
  let pages = docPages doc
      fontOrder = nub [f | p <- pages, m <- pageContent p, f <- fontsOf m]
      imageOrder = nub [i | p <- pages, m <- pageContent p, i <- imagesOf m]
      fontNames = Map.fromList (zip fontOrder [1 ..])
      imageNames = Map.fromList (zip imageOrder [1 ..])
      formOrder = filter (`Map.member` docForms doc) (nub [f | p <- pages, m <- pageContent p, f <- formsOf m])
      formNames = Map.fromList (zip formOrder [1 ..])
      nPages = length pages
      pageObj i = 3 + 2 * i
      afterPages = 3 + 2 * nPages
      fontObjs = 5 -- Type0, CIDFont, descriptor, program, ToUnicode
      fontBase = Map.fromList (zip fontOrder [afterPages, afterPages + fontObjs ..])
      afterFonts = afterPages + fontObjs * length fontOrder
      imageSizes = [(i, imageObjCount i) | i <- imageOrder]
      imageBase = Map.fromList (zip imageOrder (scanl (+) afterFonts (map snd imageSizes)))
      afterImages0 = afterFonts + sum (map snd imageSizes)
      -- the Form XObjects of PDF figures, each followed by the objects it brings that are not yet written (ADR 0008)
      (formBase, formObjsAll, afterImages) = formObjects afterImages0 [(f, ip) | f <- formOrder, Just ip <- [Map.lookup f (docForms doc)]]
      -- PDF/X-4: the output profile and the XMP metadata come last before the information dictionary
      (xObjs, xCatalog) = case docPdfX doc of
        Nothing -> ([], [])
        Just px ->
          ( [ OStream [("N", OInt 4), ("Filter", OName "FlateDecode")] (flate (pxProfile px)),
              OStream [("Type", OName "Metadata"), ("Subtype", OName "XML")] (xmpPacket px (docTitle doc) (docProducer doc) (docDate doc) (docId doc) (docInstanceId doc))
            ],
            [ ( "OutputIntents",
                OArr
                  [ ODict
                      [ ("Type", OName "OutputIntent"),
                        ("S", OName "GTS_PDFX"),
                        ("OutputConditionIdentifier", OStr (TE.encodeUtf8 (pxCondition px))),
                        ("DestOutputProfile", ORef afterImages)
                      ]
                  ]
              ),
              ("Metadata", ORef (afterImages + 1))
            ]
          )
      infoObj = afterImages + length xObjs
      imageObjCount i = case withDefaultProfile <$> Map.lookup i (docImages doc) of
        Just img -> 1 + maybe 0 (const 1) (imgIcc img) + maybe 0 (const 1) (imgAlpha img)
        Nothing -> 1
      resources =
        ODict
          ( [("Font", ODict [("F" <> tshow n, ORef (fontBase Map.! f)) | (f, n) <- Map.toList fontNames]) | not (null fontOrder)]
              <> [ ( "XObject",
                     ODict
                       ( [("Im" <> tshow n, ORef (imageBase Map.! i)) | (i, n) <- Map.toList imageNames]
                           <> [("Fm" <> tshow n, ORef (formBase Map.! f)) | (f, n) <- Map.toList formNames]
                       )
                   )
                 | not (null imageOrder && null formOrder)
                 ]
              <> [("ColorSpace", ODict [("Reg", registrationColorSpace)]) | any usesRegistration [m | p <- pages, m <- pageContent p]]
          )
      catalog = ODict ([("Type", OName "Catalog"), ("Pages", ORef 2)] <> xCatalog)
      pageTree = ODict [("Type", OName "Pages"), ("Kids", OArr [ORef (pageObj i) | i <- [0 .. nPages - 1]]), ("Count", OInt (fromIntegral nPages))]
      pageObjs =
        concat
          [ [ ODict
                [ ("Type", OName "Page"),
                  ("Parent", ORef 2),
                  ("MediaBox", rectObj (pageMediaBox p)),
                  ("TrimBox", rectObj (pageTrimBox p)),
                  ("BleedBox", rectObj (pageBleedBox p)),
                  ("Resources", resources),
                  ("Contents", ORef (pageObj i + 1))
                ],
              OStream [("Filter", OName "FlateDecode")] (flate (contentStreamWith fontNames imageNames formNames (pageContent p)))
            ]
          | (i, p) <- zip [0 ..] pages
          ]
      fontObjsAll = concat [fontObjects (fontBase Map.! f) (docFonts doc Map.! f) | f <- fontOrder, Map.member f (docFonts doc)]
      imageObjsAll = concat [imageObjects (imageBase Map.! i) img | i <- imageOrder, Just img <- [Map.lookup i (docImages doc)]]
      info =
        ODict
          [ ("Title", utf16Hex (docTitle doc)),
            ("CreationDate", OStr (pdfDate (docDate doc))),
            ("ModDate", OStr (pdfDate (docDate doc))),
            ("Producer", pdfTextString (docProducer doc))
          ]
          `addInfo` [("Trapped", OName "False"), ("GTS_PDFXVersion", OStr "PDF/X-4")]
      addInfo (ODict kvs) extra = ODict (kvs <> (if isJust (docPdfX doc) then extra else []))
      addInfo o _ = o
      objects = [catalog, pageTree] <> pageObjs <> fontObjsAll <> imageObjsAll <> formObjsAll <> xObjs <> [info]
      size = length objects + 1
   in PdfObjects "1.6" objects (ODict [("Size", OInt (fromIntegral size)), ("Root", ORef 1), ("Info", ORef infoObj), ("ID", OArr [OHex (docId doc), OHex (docInstanceId doc)])])
  where
    tshow :: Int -> Text
    tshow = T.pack . show
    fontsOf = \case
      GlyphRun f _ _ -> [f]
      ScaledGlyphRun f _ _ _ -> [f]
      RotatedGlyphRun f _ _ -> [f]
      StyledGlyphRun _ f _ _ -> [f]
      Saved ms -> concatMap fontsOf ms
      Translated _ _ ms -> concatMap fontsOf ms
      _ -> []
    imagesOf = \case
      Image i _ -> [i]
      Saved ms -> concatMap imagesOf ms
      Translated _ _ ms -> concatMap imagesOf ms
      _ -> []
    formsOf = \case
      Form f _ -> [f]
      Saved ms -> concatMap formsOf ms
      Translated _ _ ms -> concatMap formsOf ms
      _ -> []

{- | The Form XObjects of PDF figures from object @base@ (ADR 0008): each
form, then the objects of its page not yet written, in the order of the
page. Pages of one file share their objects (by the key of each object in
the file). Returns the number of each form, the objects and the next
number.
-}
formObjects :: Int -> [(FormRef, ImportedPage)] -> (Map FormRef Int, [Obj], Int)
formObjects base forms =
  let step (fm, nums, acc, next) (f, ip) =
        let new = nub [k | (k, _) <- ipObjects ip, Map.notMember (ipFile ip, k) nums]
            nums' = Map.union nums (Map.fromList [((ipFile ip, k), i) | (k, i) <- zip new [next + 1 ..]])
            remap = renumber (\k -> Map.lookup (ipFile ip, k) nums')
            objs = formObject remap ip : [remap o | k <- new, Just o <- [lookup k (ipObjects ip)]]
         in (Map.insert f next fm, nums', acc <> [objs], next + 1 + length new)
      (formNums, _, objss, after) = foldl step (Map.empty, Map.empty :: Map (ByteString, Int) Int, [], base) forms
   in (formNums, concat objss, after)

-- | The references of an object renumbered; one with no number becomes null.
renumber :: (Int -> Maybe Int) -> Obj -> Obj
renumber f = \case
  ORef k -> maybe ONull ORef (f k)
  ODict kvs -> ODict [(k, renumber f v) | (k, v) <- kvs]
  OArr xs -> OArr (map (renumber f) xs)
  OStream kvs b -> OStream [(k, renumber f v) | (k, v) <- kvs] b
  o -> o

{- | The Form XObject of a page of a PDF figure (ADR 0008): its crop box as
BBox, and a Matrix that turns it by Rotate and maps it to the unit square.
-}
formObject :: (Obj -> Obj) -> ImportedPage -> Obj
formObject remap ip =
  let (x0, y0, x1, y1) = ipBox ip
      w = x1 - x0
      h = y1 - y0
      matrix = case ipRotate ip of
        90 -> [0, -(1 / w), 1 / h, 0, -(y0 / h), x1 / w]
        180 -> [-(1 / w), 0, 0, -(1 / h), x1 / w, y1 / h]
        270 -> [0, 1 / w, -(1 / h), 0, y1 / h, -(x0 / w)]
        _ -> [1 / w, 0, 0, 1 / h, -(x0 / w), -(y0 / h)]
   in OStream
        ( [ ("Type", OName "XObject"),
            ("Subtype", OName "Form"),
            ("BBox", OArr [OReal (showRationalDigits 6 v) | v <- [x0, y0, x1, y1]]),
            ("Matrix", OArr [OReal (showRationalDigits 10 v) | v <- matrix]),
            ("Resources", remap (ipResources ip)),
            ("Filter", OName "FlateDecode")
          ]
            <> [("Group", remap g) | Just g <- [ipGroup ip]]
        )
        (flate (ipContent ip))

{- | Whether a mark is or contains 'RegistrationRules', which needs the
@/Reg@ colour space resource (ADR 0007).
-}
usesRegistration :: Mark -> Bool
usesRegistration = \case
  RegistrationRules _ -> True
  Saved ms -> any usesRegistration ms
  Translated _ _ ms -> any usesRegistration ms
  _ -> False

{- | The registration colour (ADR 0007): the Separation of the colorant
All, with DeviceCMYK as the alternate space and a tint transform from 0%
to 100% of each process colour. Written as a direct value, so that the
object numbers do not change.
-}
registrationColorSpace :: Obj
registrationColorSpace =
  OArr
    [ OName "Separation",
      OName "All",
      OName "DeviceCMYK",
      ODict
        [ ("FunctionType", OInt 2),
          ("Domain", OArr [OInt 0, OInt 1]),
          ("C0", OArr (replicate 4 (OInt 0))),
          ("C1", OArr (replicate 4 (OInt 1))),
          ("N", OInt 1)
        ]
    ]

fontObjects :: Int -> Font -> [Obj]
fontObjects base f =
  let (bx0, by0, bx1, by1) = fontBBox f
      isCff = case fontProgram f of TrueTypeProgram _ -> False; _ -> True
      programBytes = case fontProgram f of CffProgram b -> b; TrueTypeProgram b -> b; OpenTypeProgram b -> b
      programSubtype = case fontProgram f of
        CffProgram _ -> [("Subtype", OName "CIDFontType0C")]
        OpenTypeProgram _ -> [("Subtype", OName "OpenType")]
        TrueTypeProgram _ -> []
      type0 =
        ODict
          [ ("Type", OName "Font"),
            ("Subtype", OName "Type0"),
            ("BaseFont", OName (fontName f)),
            ("Encoding", OName (if fontVertical f then "Identity-V" else "Identity-H")),
            ("DescendantFonts", OArr [ORef (base + 1)]),
            ("ToUnicode", ORef (base + 4))
          ]
      cid =
        ODict
          ( [ ("Type", OName "Font"),
              ("Subtype", OName (if isCff then "CIDFontType0" else "CIDFontType2")),
              ("BaseFont", OName (fontName f)),
              ("CIDSystemInfo", let (r, o, s) = fontCidSystemInfo f in ODict [("Registry", OStr (TE.encodeUtf8 r)), ("Ordering", OStr (TE.encodeUtf8 o)), ("Supplement", OInt (fromIntegral s))]),
              ("FontDescriptor", ORef (base + 2)),
              ("W", OArr (concat [[OInt (fromIntegral g), OArr [OInt (fromIntegral w)]] | (g, w) <- sortOn fst (fontWidths f)]))
            ]
              <> [("CIDToGIDMap", OName "Identity") | not isCff]
              <> [("DW2", OArr [OInt 880, OInt (-1000)]) | fontVertical f]
              <> [ ("W2", OArr (concat [[OInt (fromIntegral g), OInt (fromIntegral g), OInt (fromIntegral (negate v)), OInt 500, OInt 880] | (g, v) <- sortOn fst (fontVerticalAdvances f)]))
                 | fontVertical f,
                   not (null (fontVerticalAdvances f))
                 ]
          )
      descriptor =
        ODict
          [ ("Type", OName "FontDescriptor"),
            ("FontName", OName (fontName f)),
            ("Flags", OInt 4),
            ("FontBBox", OArr (map (OInt . fromIntegral) [bx0, by0, bx1, by1])),
            ("ItalicAngle", OInt (fromIntegral (fontItalicAngle f))),
            ("Ascent", OInt (fromIntegral (fontAscent f))),
            ("Descent", OInt (fromIntegral (fontDescent f))),
            ("CapHeight", OInt (fromIntegral (fontCapHeight f))),
            ("StemV", OInt (fromIntegral (fontStemV f))),
            (if isCff then "FontFile3" else "FontFile2", ORef (base + 3))
          ]
      program = OStream (("Filter", OName "FlateDecode") : programSubtype) (flate programBytes)
      toUnicode = OStream [("Filter", OName "FlateDecode")] (flate (toUnicodeCMap (fontToUnicode f)))
   in [type0, cid, descriptor, program, toUnicode]

toUnicodeCMap :: [(GlyphId, Text)] -> ByteString
toUnicodeCMap entries =
  let chunk xs = if null xs then [] else take 100 xs : chunk (drop 100 xs)
      hexText t = mconcat [B.word8HexFixed w | w <- BS.unpack (TE.encodeUtf16BE t)]
      body =
        mconcat
          [ B.intDec (length c) <> " beginbfchar\n" <> mconcat ["<" <> B.string7 (printf "%04X" g) <> "> <" <> hexText t <> ">\n" | (g, t) <- c] <> "endbfchar\n"
          | c <- chunk (sortOn fst entries)
          ]
   in BL.toStrict . B.toLazyByteString $
        "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n"
          <> body
          <> "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"

{- | RGB without a profile gets sRGB (ADR 0001); colours are never
converted. Both the object count and the objects use it, so that the
profile has its own object number.
-}
withDefaultProfile :: ImageData -> ImageData
withDefaultProfile img = case (imgIcc img, imgColor img) of
  (Nothing, CsRgb) -> img {imgIcc = Just srgbProfile}
  (Nothing, CsIndexed _) -> img {imgIcc = Just srgbProfile}
  _ -> img

imageObjects :: Int -> ImageData -> [Obj]
imageObjects base img0 =
  let img = withDefaultProfile img0
      iccObj = OStream [("N", OInt (components img)), ("Filter", OName "FlateDecode")] . flate <$> imgIcc img
      iccRef = base + 1
      smaskRef = base + 1 + maybe 0 (const 1) (imgIcc img)
      colorSpace = case (imgIcc img, imgColor img) of
        (Just _, CsIndexed p) -> OArr [OName "Indexed", OArr [OName "ICCBased", ORef iccRef], OInt (fromIntegral (BS.length p `div` 3 - 1)), OHex p]
        (Just _, _) -> OArr [OName "ICCBased", ORef iccRef]
        (Nothing, CsGray) -> OName "DeviceGray"
        (Nothing, CsRgb) -> OName "DeviceRGB"
        (Nothing, CsCmyk) -> OName "DeviceCMYK"
        (Nothing, CsIndexed p) -> OArr [OName "Indexed", OName "DeviceRGB", OInt (fromIntegral (BS.length p `div` 3 - 1)), OHex p]
      common =
        [ ("Type", OName "XObject"),
          ("Subtype", OName "Image"),
          ("Width", OInt (fromIntegral (imgWidth img))),
          ("Height", OInt (fromIntegral (imgHeight img))),
          ("BitsPerComponent", OInt (fromIntegral (imgBits img))),
          ("ColorSpace", colorSpace)
        ]
          <> [("Decode", OArr (concat (replicate 4 [OInt 1, OInt 0]))) | imgInvertedCmyk img]
          <> [("SMask", ORef smaskRef) | Just _ <- [imgAlpha img]]
      main' =
        if imgDct img
          then OStream (("Filter", OName "DCTDecode") : common) (imgData img)
          else OStream (("Filter", OName "FlateDecode") : common) (flate (imgData img))
      smask =
        OStream
          [ ("Type", OName "XObject"),
            ("Subtype", OName "Image"),
            ("Width", OInt (fromIntegral (imgWidth img))),
            ("Height", OInt (fromIntegral (imgHeight img))),
            ("BitsPerComponent", OInt (fromIntegral (imgBits img))),
            ("ColorSpace", OName "DeviceGray"),
            ("Filter", OName "FlateDecode")
          ]
          . flate
          <$> imgAlpha img
   in main' : catMaybes [iccObj, smask]
  where
    components i = case imgColor i of
      CsGray -> 1
      CsRgb -> 3
      CsCmyk -> 4
      CsIndexed _ -> 3
