{- | PDF/X-4 (golem-pdf ADR 0002): the output intent, XMP metadata,
Trapped, and the checks of the requirements Golem can verify itself.
-}
module Golem.Pdf.X4
  ( PdfX (..),
    xmpPacket,
    checkPdfX,
    uuidText,
    X4Problem (..),
    verify,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isDigit)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.LayoutSpec (Rect (..))
import Golem.Pdf.Object
import Golem.Syntax.Text (escapeXml)
import Text.Printf (printf)

data PdfX = PdfX
  { -- | the ICC profile of color.intent (Japan Color 2001 Coated in v1)
    pxProfile :: !ByteString,
    pxCondition :: !Text,
    pxCreators :: ![Text],
    -- | dc:contributor, names without roles (docs/adr ADR 0033)
    pxContributors :: ![Text]
  }
  deriving stock (Eq, Show)

-- | 16 bytes as a UUID string.
uuidText :: ByteString -> Text
uuidText b =
  let h = T.pack (concatMap (printf "%02x") (BS.unpack b))
   in T.intercalate "-" [T.take 8 h, T.take 4 (T.drop 8 h), T.take 4 (T.drop 12 h), T.take 4 (T.drop 16 h), T.drop 20 h]

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
          <> [ "   <dc:contributor><rdf:Bag>" <> T.concat ["<rdf:li>" <> escapeXml c <> "</rdf:li>" | c <- pxContributors px] <> "</rdf:Bag></dc:contributor>"
             | not (null (pxContributors px))
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

-- ------------------------------------------------------------------ verify

-- | A PDF/X-4 requirement a PDF does not meet (golem-cli ADR 0006).
data X4Problem = X4Problem
  { x4Requirement :: !Text,
    x4Detail :: !Text
  }
  deriving stock (Eq, Ord, Show)

{- | The requirements of golem-pdf ADR 0002 that Golem checks itself, on
the objects before they are written (golem-cli ADR 0006): the version,
the output intent and its profile, GTS_PDFXVersion and Trapped in XMP,
the page boxes, embedded fonts, no RGB without an ICC profile, and no
encryption, JavaScript or external references. Not a judgement of
conformance (golem-pdf ADR 0003).
-}
verify :: PdfObjects -> [X4Problem]
verify (PdfObjects version objects trailer) =
  concat
    [ [X4Problem "PDF のバージョン" (version <> "（1.6 以下にします）") | not (versionOk version)],
      intentProblems,
      [X4Problem "GTS_PDFXVersion" "XMP に PDF/X-4 のバージョンがありません" | not ("<pdfxid:GTS_PDFXVersion>PDF/X-4</pdfxid:GTS_PDFXVersion>" `BS.isInfixOf` xmp)],
      [X4Problem "Trapped" "XMP と文書情報の両方に Trapped が要ります" | not (trappedInXmp && trappedInInfo)],
      [X4Problem "TrimBox" (pagesText noTrim <> " ページ目に TrimBox がありません") | not (null noTrim)],
      [X4Problem "ページのボックス" (pagesText badBoxes <> " ページ目の TrimBox が BleedBox の、BleedBox が MediaBox の外にはみ出しています") | not (null badBoxes)],
      [X4Problem "フォントの埋め込み" (T.intercalate "、" unembedded <> " を埋め込んでいません") | not (null unembedded)],
      [X4Problem "ICC プロファイルのない RGB" "DeviceRGB の色空間があります" | any usesDeviceRgb objects],
      [X4Problem "暗号化" "Encrypt があります" | hasKey "Encrypt" trailer],
      [X4Problem "JavaScript と外部への参照" (T.intercalate "、" forbidden <> " があります") | not (null forbidden)]
    ]
  where
    deref = \case
      ORef n | n >= 1, (o : _) <- drop (n - 1) objects -> o
      o -> o
    dictOf = \case
      ODict kvs -> kvs
      OStream kvs _ -> kvs
      _ -> []
    look k o = lookup k (dictOf o)
    hasKey k o = isJust (look k o)
    catalog = maybe (ODict []) deref (look "Root" trailer)
    info = maybe (ODict []) deref (look "Info" trailer)
    intents = case deref <$> look "OutputIntents" catalog of
      Just (OArr xs) -> [d | x <- xs, let d = deref x, look "S" d == Just (OName "GTS_PDFX")]
      _ -> []
    intentProblems = case intents of
      [] -> [X4Problem "出力インテント" "カタログに GTS_PDFX の出力インテントがありません"]
      (i : _) -> case deref <$> look "DestOutputProfile" i of
        Just (OStream _ b) | not (BS.null b) -> []
        _ -> [X4Problem "DestOutputProfile" "出力インテントに ICC プロファイルがありません"]
    xmp = case deref <$> look "Metadata" catalog of
      Just (OStream _ b) -> b
      _ -> ""
    trappedInXmp = any (`BS.isInfixOf` xmp) ["<pdf:Trapped>True</pdf:Trapped>", "<pdf:Trapped>False</pdf:Trapped>"]
    trappedInInfo = look "Trapped" info `elem` [Just (OName "True"), Just (OName "False")]
    pages = [o | o <- objects, look "Type" o == Just (OName "Page")]
    numbered = zip [1 :: Int ..] pages
    noTrim = [i | (i, p) <- numbered, not (hasKey "TrimBox" p)]
    badBoxes =
      [ i
      | (i, p) <- numbered,
        Just media <- [boxOf =<< look "MediaBox" p],
        let bleed = fromMaybe media (boxOf =<< look "BleedBox" p),
        Just trim <- [boxOf =<< look "TrimBox" p],
        not (inside bleed media && inside trim bleed)
      ]
    boxOf = \case
      OArr [a, b, c, d] -> (,,,) <$> numberOf a <*> numberOf b <*> numberOf c <*> numberOf d
      _ -> Nothing
    inside (x0, y0, x1, y1) (ox0, oy0, ox1, oy1) = x0 >= ox0 && y0 >= oy0 && x1 <= ox1 && y1 <= oy1
    pagesText = T.intercalate "、" . map (T.pack . show)
    unembedded =
      [ maybe "名前のないフォント" nameText (look "FontName" o)
      | o <- objects,
        look "Type" o == Just (OName "FontDescriptor"),
        not (any (`hasKey` o) ["FontFile", "FontFile2", "FontFile3"])
      ]
    nameText = \case
      OName n -> n
      _ -> "名前のないフォント"
    usesDeviceRgb = \case
      OName "DeviceRGB" -> True
      ODict kvs -> any (usesDeviceRgb . snd) kvs
      OArr xs -> any usesDeviceRgb xs
      OStream kvs _ -> any (usesDeviceRgb . snd) kvs
      _ -> False
    forbiddenNames = ["JavaScript", "JS", "URI", "Launch", "GoToR"]
    forbidden = nubOrd' (concatMap namesIn (trailer : objects))
    namesIn = \case
      ODict kvs -> [k | (k, _) <- kvs, k `elem` forbiddenNames] <> concatMap (namesIn . snd) kvs
      OStream kvs _ -> [k | (k, _) <- kvs, k `elem` forbiddenNames] <> concatMap (namesIn . snd) kvs
      OArr xs -> concatMap namesIn xs
      OName n | n `elem` forbiddenNames -> [n]
      _ -> []
    -- each name once, in the order first found (golem-pdf ADR 0012)
    nubOrd' = reverse . foldl' (\acc x -> if x `elem` acc then acc else x : acc) []

-- | Whether a version is at most 1.6, as PDF/X-4 is based on PDF 1.6.
versionOk :: Text -> Bool
versionOk v = case T.splitOn "." v of
  [a, b] | Just x <- readInt a, Just y <- readInt b -> (x, y) <= (1 :: Int, 6 :: Int)
  _ -> False
  where
    readInt t = if not (T.null t) && T.all isDigit t then Just (read (T.unpack t)) else Nothing

-- | A number of a PDF as written: an integer or a decimal.
numberOf :: Obj -> Maybe Rational
numberOf = \case
  OInt i -> Just (fromInteger i)
  OReal t ->
    let (sign, digits) = maybe (1, t) (-1,) (T.stripPrefix "-" t)
     in case T.splitOn "." digits of
          [i] | ok i -> Just (sign * fromInteger (read (T.unpack i)))
          [i, f] | ok i, ok f -> Just (sign * (fromInteger (read (T.unpack (i <> f))) / 10 ^ T.length f))
          _ -> Nothing
  _ -> Nothing
  where
    ok x = not (T.null x) && T.all isDigit x
