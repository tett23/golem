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
    Turn (..),
    turnRect,
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
import Golem.Pdf.Drawing
import Golem.Pdf.Image
import Golem.Pdf.Import
import Golem.Pdf.Number
import Golem.Pdf.Object
import Golem.Pdf.Sha256 (sha256)
import Golem.Pdf.Srgb (srgbProfile)
import Golem.Pdf.X4
import Golem.Syntax.Text (tshow)
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
  | -- | a filled disc: the x and y of its centre and its radius (golem-driver ADR 0028)
    Disc !Sp !Sp !Sp
  | {- | a filled closed path of cubic curves: the start and, for each
    curve, its two control points and its end (golem-driver ADR 0028)
    -}
    CurveFill !(Sp, Sp) ![((Sp, Sp), (Sp, Sp), (Sp, Sp))]
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
  | {- | marks wrapped in a marked-content sequence with the replacement
    text, outside BT and ET; not nested (golem-driver ADR 0030)
    -}
    ActualText !Text ![Mark]
  | {- | marks drawn in a frame whose origin is its lower left corner,
    turned and placed in the rectangle, inside q and Q (golem-driver ADR
    0034); the frame is as wide as the rectangle is high
    -}
    Turned !Turn !Rect ![Mark]
  deriving stock (Eq, Show)

{- | How marks are turned onto the page (golem-driver ADR 0034): to the
right (clockwise), the top of their frame at the right of the page; to
the left, at the left.
-}
data Turn = TurnedRight | TurnedLeft
  deriving stock (Eq, Show)

{- | Where a rectangle of the frame of 'Turned' lands on the page, when the
frame is turned into the rectangle @r@ (golem-driver ADR 0034).
-}
turnRect :: Turn -> Rect -> Rect -> Rect
turnRect t (Rect x y w h) (Rect u v a b) = case t of
  TurnedRight -> Rect (x + v) (y + h - u - a) b a
  TurnedLeft -> Rect (x + w - v - b) (y + u) b a

data Page = Page
  { pageMediaBox :: !Rect,
    pageTrimBox :: !Rect,
    pageBleedBox :: !Rect,
    pageContent :: ![Mark]
  }
  deriving stock (Eq, Show)

{- | The embedded font program: a TrueType font goes into FontFile2, the
bare CFF table of a font with CFF outlines into FontFile3 with the subtype
CIDFontType0C (golem-pdf ADR 0011).
-}
data FontProgram = TrueTypeProgram !ByteString | CffProgram !ByteString
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
    -- | the pages of PDF figures and the drawings of SVG figures (ADR 0008, 0009)
    docForms :: !(Map FormRef FormContent),
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
      Disc x y r ->
        -- four quarters counterclockwise from the right; the control points 0.5523 of the radius away
        let k = round (toRational r * 5523 / 10000)
         in point (x + r, y)
              <> " m"
              <> nl
              <> curve ((x + r, y + k), (x + k, y + r), (x, y + r))
              <> curve ((x - k, y + r), (x - r, y + k), (x - r, y))
              <> curve ((x - r, y - k), (x - k, y - r), (x, y - r))
              <> curve ((x + k, y - r), (x + r, y - k), (x + r, y))
              <> "f"
              <> nl
      CurveFill start cs -> point start <> " m" <> nl <> mconcat (map curve cs) <> "h f" <> nl
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
      -- a /Span with the replacement text written in the stream, no tag structure (golem-driver ADR 0030)
      ActualText t ms -> "/Span << /ActualText " <> serialize (pdfTextString t) <> " >> BDC" <> nl <> mconcat (map mark ms) <> "EMC" <> nl
      Translated x y ms -> "q 1 0 0 1 " <> num x <> sp <> num y <> " cm" <> nl <> mconcat (map mark ms) <> "Q" <> nl
      -- the frame's (u, v) goes to (x + v, y + h - u), or to (x + w - v, y + u)
      Turned TurnedRight (Rect x y _ h) ms -> "q 0 -1 1 0 " <> num x <> sp <> num (y + h) <> " cm" <> nl <> mconcat (map mark ms) <> "Q" <> nl
      Turned TurnedLeft (Rect x y w _) ms -> "q 0 1 -1 0 " <> num (x + w) <> sp <> num y <> " cm" <> nl <> mconcat (map mark ms) <> "Q" <> nl
      RegistrationRules rs -> "q" <> nl <> "/Reg cs 1 scn" <> nl <> mconcat (map (mark . Rule) rs) <> "Q" <> nl
      -- the form maps its crop box to the unit square (its Matrix), so it is placed as an image is
      Form f (Rect x y w h) ->
        "q " <> num w <> " 0 0 " <> num h <> sp <> num x <> sp <> num y <> " cm /Fm" <> B.intDec (Map.findWithDefault 0 f formNames) <> " Do Q" <> nl
    hex4 g = B.string7 (printf "%04X" g)
    point (x, y) = num x <> sp <> num y
    curve (a, b, c) = point a <> sp <> point b <> sp <> point c <> " c" <> nl

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
      forms = [(f, fc) | f <- formOrder, Just fc <- [Map.lookup f (docForms doc)]]
      -- one sRGB profile for images without a profile, PDF figures and drawings (ADR 0009)
      needSrgb =
        any defaultSrgb [img | i <- imageOrder, Just img <- [Map.lookup i (docImages doc)]]
          || any (\case (_, DrawnForm _) -> True; (_, ImportedForm ip) -> any ((== 0) . fst) (ipObjects ip)) forms
      srgbRef = afterImages0
      srgbObjs = [OStream [("N", OInt 3), ("Filter", OName "FlateDecode")] (flate srgbProfile) | needSrgb]
      -- the Form XObjects of PDF figures and drawings, each followed by the objects it brings that are not yet written (ADR 0008)
      (formBase, formObjsAll, afterImages) = formObjects srgbRef (afterImages0 + length srgbObjs) forms
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
      imageObjCount i = case Map.lookup i (docImages doc) of
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
      imageObjsAll = concat [imageObjects srgbRef (imageBase Map.! i) img | i <- imageOrder, Just img <- [Map.lookup i (docImages doc)]]
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
      objects = [catalog, pageTree] <> pageObjs <> fontObjsAll <> imageObjsAll <> srgbObjs <> formObjsAll <> xObjs <> [info]
      size = length objects + 1
   in PdfObjects "1.6" objects (ODict [("Size", OInt (fromIntegral size)), ("Root", ORef 1), ("Info", ORef infoObj), ("ID", OArr [OHex (docId doc), OHex (docInstanceId doc)])])
  where
    fontsOf = \case
      GlyphRun f _ _ -> [f]
      ScaledGlyphRun f _ _ _ -> [f]
      RotatedGlyphRun f _ _ -> [f]
      StyledGlyphRun _ f _ _ -> [f]
      Saved ms -> concatMap fontsOf ms
      ActualText _ ms -> concatMap fontsOf ms
      Translated _ _ ms -> concatMap fontsOf ms
      Turned _ _ ms -> concatMap fontsOf ms
      _ -> []
    imagesOf = \case
      Image i _ -> [i]
      Saved ms -> concatMap imagesOf ms
      ActualText _ ms -> concatMap imagesOf ms
      Translated _ _ ms -> concatMap imagesOf ms
      Turned _ _ ms -> concatMap imagesOf ms
      _ -> []
    formsOf = \case
      Form f _ -> [f]
      Saved ms -> concatMap formsOf ms
      ActualText _ ms -> concatMap formsOf ms
      Translated _ _ ms -> concatMap formsOf ms
      Turned _ _ ms -> concatMap formsOf ms
      _ -> []

{- | The Form XObjects of PDF figures from object @base@ (ADR 0008): each
form, then the objects of its page not yet written, in the order of the
page. Pages of one file share their objects (by the key of each object in
the file). Returns the number of each form, the objects and the next
number.
-}
formObjects :: Int -> Int -> [(FormRef, FormContent)] -> (Map FormRef Int, [Obj], Int)
formObjects srgbRef base forms =
  let step (fm, nums, acc, next) (f, DrawnForm d) = (Map.insert f next fm, nums, acc <> [[drawnObject srgbRef d]], next + 1)
      step (fm, nums, acc, next) (f, ImportedForm ip) =
        -- key 0 is the sRGB profile, written once for the whole document
        let new = nub [k | (k, _) <- ipObjects ip, k /= 0, Map.notMember (ipFile ip, k) nums]
            nums' = Map.union nums (Map.fromList [((ipFile ip, k), i) | (k, i) <- zip new [next + 1 ..]])
            remap = renumber (\k -> if k == 0 then Just srgbRef else Map.lookup (ipFile ip, k) nums')
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

{- | The Form XObject of a drawing (ADR 0009): its size as BBox, a Matrix
that maps it to the unit square, and GolemSRGB as its only resource.
-}
drawnObject :: Int -> Drawing -> Obj
drawnObject srgbRef d =
  let (w, h) = drSize d
   in OStream
        [ ("Type", OName "XObject"),
          ("Subtype", OName "Form"),
          ("BBox", OArr [OInt 0, OInt 0, OReal (showRationalDigits 6 w), OReal (showRationalDigits 6 h)]),
          ("Matrix", OArr [OReal (showRationalDigits 10 v) | v <- [1 / w, 0, 0, 1 / h, 0, 0]]),
          ("Resources", ODict [("ColorSpace", ODict [("GolemSRGB", OArr [OName "ICCBased", ORef srgbRef])])]),
          ("Filter", OName "FlateDecode")
        ]
        (flate (drawingContent d))

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
  ActualText _ ms -> any usesRegistration ms
  Translated _ _ ms -> any usesRegistration ms
  Turned _ _ ms -> any usesRegistration ms
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
      isCff = case fontProgram f of TrueTypeProgram _ -> False; CffProgram _ -> True
      programBytes = case fontProgram f of CffProgram b -> b; TrueTypeProgram b -> b
      programSubtype = case fontProgram f of
        CffProgram _ -> [("Subtype", OName "CIDFontType0C")]
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
converted. The profile is the document's one sRGB profile (ADR 0009).
-}
defaultSrgb :: ImageData -> Bool
defaultSrgb img = case (imgIcc img, imgColor img) of
  (Nothing, CsRgb) -> True
  (Nothing, CsIndexed _) -> True
  _ -> False

imageObjects :: Int -> Int -> ImageData -> [Obj]
imageObjects srgbRef base img =
  let iccObj = OStream [("N", OInt (components img)), ("Filter", OName "FlateDecode")] . flate <$> imgIcc img
      iccRef = base + 1
      smaskRef = base + 1 + maybe 0 (const 1) (imgIcc img)
      colorSpace = case (imgIcc img, imgColor img) of
        (Just _, CsIndexed p) -> OArr [OName "Indexed", OArr [OName "ICCBased", ORef iccRef], OInt (fromIntegral (BS.length p `div` 3 - 1)), OHex p]
        (Just _, _) -> OArr [OName "ICCBased", ORef iccRef]
        (Nothing, CsGray) -> OName "DeviceGray"
        (Nothing, CsRgb) -> OArr [OName "ICCBased", ORef srgbRef]
        (Nothing, CsCmyk) -> OName "DeviceCMYK"
        (Nothing, CsIndexed p) -> OArr [OName "Indexed", OArr [OName "ICCBased", ORef srgbRef], OInt (fromIntegral (BS.length p `div` 3 - 1)), OHex p]
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
