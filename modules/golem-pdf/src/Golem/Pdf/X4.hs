{- | PDF/X-4 (golem-pdf ADR 0002): the output intent, XMP metadata,
Trapped, and the checks of the requirements Golem can verify itself.
-}
module Golem.Pdf.X4
  ( PdfX (..),
    xmpPacket,
    checkPdfX,
    uuidText,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.LayoutSpec (Rect (..))
import Text.Printf (printf)

data PdfX = PdfX
  { -- | the ICC profile of color.intent (Japan Color 2001 Coated in v1)
    pxProfile :: !ByteString,
    pxCondition :: !Text,
    pxCreators :: ![Text]
  }
  deriving stock (Eq, Show)

-- | 16 bytes as a UUID string.
uuidText :: ByteString -> Text
uuidText b =
  let h = T.pack (concatMap (printf "%02x") (BS.unpack b))
   in T.intercalate "-" [T.take 8 h, T.take 4 (T.drop 8 h), T.take 4 (T.drop 12 h), T.take 4 (T.drop 16 h), T.drop 20 h]

escapeXml :: Text -> Text
escapeXml = T.concatMap (\case '<' -> "&lt;"; '>' -> "&gt;"; '&' -> "&amp;"; '"' -> "&quot;"; c -> T.singleton c)

{- | The XMP packet: title, Producer (ADR 0005), date, document and instance
IDs. Fixed key order and layout, so it is deterministic.
-}
xmpPacket :: PdfX -> Text -> Text -> (Integer, Int, Int) -> ByteString -> ByteString -> ByteString
xmpPacket px title producer (y, m, d) docId inst =
  let date = T.pack (printf "%04d-%02d-%02dT00:00:00Z" y m d)
      creators =
        [ "   <dc:creator><rdf:Seq>" <> T.concat ["<rdf:li>" <> escapeXml c <> "</rdf:li>" | c <- pxCreators px] <> "</rdf:Seq></dc:creator>"
        | not (null (pxCreators px))
        ]
   in TE.encodeUtf8 . T.unlines $
        [ "<?xpacket begin=\"\xFEFF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>",
          "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">",
          " <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">",
          "  <rdf:Description rdf:about=\"\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" xmlns:xmpMM=\"http://ns.adobe.com/xap/1.0/mm/\" xmlns:pdf=\"http://ns.adobe.com/pdf/1.3/\" xmlns:pdfxid=\"http://www.npes.org/pdfx/ns/id/\">",
          "   <dc:format>application/pdf</dc:format>",
          "   <dc:title><rdf:Alt><rdf:li xml:lang=\"x-default\">" <> escapeXml title <> "</rdf:li></rdf:Alt></dc:title>"
        ]
          <> creators
          <> [ "   <xmp:CreateDate>" <> date <> "</xmp:CreateDate>",
               "   <xmp:ModifyDate>" <> date <> "</xmp:ModifyDate>",
               "   <xmp:MetadataDate>" <> date <> "</xmp:MetadataDate>",
               "   <xmpMM:DocumentID>uuid:" <> uuidText docId <> "</xmpMM:DocumentID>",
               "   <xmpMM:InstanceID>uuid:" <> uuidText inst <> "</xmpMM:InstanceID>",
               "   <xmpMM:VersionID>1</xmpMM:VersionID>",
               "   <xmpMM:RenditionClass>default</xmpMM:RenditionClass>",
               "   <pdf:Producer>" <> escapeXml producer <> "</pdf:Producer>",
               "   <pdf:Trapped>False</pdf:Trapped>",
               "   <pdfxid:GTS_PDFXVersion>PDF/X-4</pdfxid:GTS_PDFXVersion>",
               "  </rdf:Description>",
               " </rdf:RDF>",
               "</x:xmpmeta>",
               "<?xpacket end=\"w\"?>"
             ]

{- | The page box requirements: a TrimBox on every page, the BleedBox
inside the MediaBox, the TrimBox inside the BleedBox. Returns the
numbers (from 1) of the pages that break them.
-}
checkPdfX :: [(Rect, Rect, Rect)] -> [Int]
checkPdfX boxes =
  [ i
  | (i, (media, trim, bleed)) <- zip [1 ..] boxes,
    not (inside bleed media && inside trim bleed)
  ]
  where
    inside (Rect x y w h) (Rect ox oy ow oh) = x >= ox && y >= oy && x + w <= ox + ow && y + h <= oy + oh
