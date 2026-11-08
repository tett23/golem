{- | What a PDF paints with, read from its objects before they are written
(docs/adr ADR 0232): every fill and stroke of the content streams of its
pages with the colour space and the colour at that time, the fonts it does
not embed, and the spot colorants of its colour spaces. golem preflight
reads them for G09019 to G09021, the tests of golem-driver for the plates
Golem draws on.
-}
module Golem.Pdf.Paint
  ( Paint (..),
    PaintSource (..),
    PaintSpace (..),
    paintsOf,
    unembeddedFonts,
    spotColorants,
  )
where

import Data.Array (Array, bounds, listArray, (!))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Pdf.Image (inflateUpTo)
import Golem.Pdf.Import (contentOperations, unescapeName)
import Golem.Pdf.Object

-- | Where a paint is: the content stream of a page, or a Form XObject called from it by @Do@.
data PaintSource
  = PageContent
  | -- | the names of the XObject resources, from the one the page calls
    FormXObject ![Text]
  deriving stock (Eq, Ord, Show)

-- | The colour space of a paint.
data PaintSpace
  = PsDeviceGray
  | PsDeviceRgb
  | PsDeviceCmyk
  | -- | ICCBased with its number of components; CalGray is one, CalRGB three
    PsIccBased !Int
  | PsLab
  | -- | Separation and its colorant
    PsSeparation !Text
  | -- | DeviceN and its colorants
    PsDeviceN ![Text]
  | PsPattern
  | PsIndexed
  | -- | a colour space the reading does not know, or a resource not found, by its name
    PsUnknown !Text
  deriving stock (Eq, Ord, Show)

-- | A fill or a stroke (docs/adr ADR 0232).
data Paint = Paint
  { -- | the page of the PDF, from 1
    paPage :: !Int,
    -- | the operator that paints: f, f*, B, B*, b, b*, S, s, Tj, TJ, ', ", sh
    paOperator :: !Text,
    paSource :: !PaintSource,
    paSpace :: !PaintSpace,
    -- | the components of the colour, as the stream writes them
    paComponents :: ![Text]
  }
  deriving stock (Eq, Show)

-- ------------------------------------------------------------------ objects

newtype Objs = Objs (Array Int Obj)

objsOf :: PdfObjects -> Objs
objsOf (PdfObjects _ os _) = Objs (listArray (1, length os) os)

deref :: Objs -> Obj -> Obj
deref (Objs a) = \case
  ORef n | let (lo, hi) = bounds a, n >= lo, n <= hi -> a ! n
  o -> o

dictOf :: Obj -> [(Text, Obj)]
dictOf = \case
  ODict kvs -> kvs
  OStream kvs _ -> kvs
  _ -> []

look :: Objs -> Text -> Obj -> Maybe Obj
look os k o = deref os <$> lookup k (dictOf o)

-- | A name of a PDF as Text: its escapes undone, UTF-8 where it is.
readableName :: Text -> Text
readableName = TE.decodeUtf8Lenient . unescapeName . TE.encodeUtf8

-- | The most bytes a content stream is inflated to.
maxContentBytes :: Int
maxContentBytes = 256 * 1024 * 1024

-- | How deep Form XObjects are followed inside each other.
maxFormDepth :: Int
maxFormDepth = 16

-- | The data of a stream, inflated when it is Flate; nothing for other filters.
streamData :: Objs -> Obj -> Maybe ByteString
streamData os = \case
  OStream kvs b -> case deref os <$> lookup "Filter" kvs of
    Nothing -> Just b
    Just (OName "FlateDecode") -> either (const Nothing) Just (inflateUpTo maxContentBytes b)
    Just (OArr [f]) | deref os f == OName "FlateDecode" -> either (const Nothing) Just (inflateUpTo maxContentBytes b)
    Just (OArr []) -> Just b
    _ -> Nothing
  _ -> Nothing

-- | The pages, in the order of the objects (as 'Golem.Pdf.X4.verify' numbers them).
pagesOf :: PdfObjects -> [Obj]
pagesOf (PdfObjects _ os _) = [o | o <- os, lookup "Type" (dictOf o) == Just (OName "Page")]

-- | The resources of a page, inherited from the page tree when it has none.
pageResources :: Objs -> Obj -> Obj
pageResources os = go (0 :: Int)
  where
    go d p = case look os "Resources" p of
      Just r -> r
      Nothing | d < 64, Just parent <- look os "Parent" p -> go (d + 1) parent
      Nothing -> ODict []

-- | The content of a page: its stream, or its array of streams joined by white space.
pageContent :: Objs -> Obj -> ByteString
pageContent os p = case look os "Contents" p of
  Just (OArr xs) -> BS.intercalate "\n" (mapMaybe (streamData os . deref os) xs)
  Just s -> fromMaybe "" (streamData os s)
  Nothing -> ""

-- ------------------------------------------------------------------ colour spaces

-- | A colour space and the colour it starts with after cs or CS.
spaceOf :: Objs -> Obj -> Obj -> (PaintSpace, [Text])
spaceOf os res nameObj = case nameObj of
  OName "DeviceGray" -> (PsDeviceGray, ["0"])
  OName "DeviceRGB" -> (PsDeviceRgb, ["0", "0", "0"])
  OName "DeviceCMYK" -> (PsDeviceCmyk, ["0", "0", "0", "1"])
  OName "Pattern" -> (PsPattern, [])
  OName n -> maybe (PsUnknown n, []) family (look os "ColorSpace" res >>= look os n)
  o -> family o
  where
    family o = case deref os o of
      OName "DeviceGray" -> (PsDeviceGray, ["0"])
      OName "DeviceRGB" -> (PsDeviceRgb, ["0", "0", "0"])
      OName "DeviceCMYK" -> (PsDeviceCmyk, ["0", "0", "0", "1"])
      OName "Pattern" -> (PsPattern, [])
      OArr (f : rest) -> case (deref os f, map (deref os) rest) of
        (OName "ICCBased", s : _) ->
          let n = case look os "N" s of
                Just (OInt k) -> fromInteger k
                _ -> 0
           in (PsIccBased n, replicate n "0")
        (OName "CalGray", _) -> (PsIccBased 1, ["0"])
        (OName "CalRGB", _) -> (PsIccBased 3, ["0", "0", "0"])
        (OName "Lab", _) -> (PsLab, ["0", "0", "0"])
        (OName "Separation", OName c : _) -> (PsSeparation (readableName c), ["1"])
        (OName "DeviceN", OArr cs : _) ->
          let names = [readableName c | OName c <- map (deref os) cs]
           in (PsDeviceN names, map (const "1") names)
        (OName "Indexed", _) -> (PsIndexed, ["0"])
        (OName "Pattern", _) -> (PsPattern, [])
        (OName n, _) -> (PsUnknown n, [])
        _ -> (PsUnknown "", [])
      OName n -> (PsUnknown n, [])
      _ -> (PsUnknown "", [])

-- ------------------------------------------------------------------ paints

data Gs = Gs
  { gsFill :: !(PaintSpace, [Text]),
    gsStroke :: !(PaintSpace, [Text]),
    gsRender :: !Int
  }

initialGs :: Gs
initialGs = Gs (PsDeviceGray, ["0"]) (PsDeviceGray, ["0"]) 0

nameOperand :: ByteString -> Maybe Text
nameOperand b = case BS.uncons b of
  Just (47, n) -> Just (TE.decodeUtf8Lenient n)
  _ -> Nothing

{- | Every fill and stroke of the pages, in the order they are painted
(docs/adr ADR 0232). q and Q save and restore the colours and the text
rendering mode; a Form XObject is read with the colours of its caller,
which come back after its Do. Images paint nothing here; a text rendering
mode of 3 or 7 neither.
-}
paintsOf :: PdfObjects -> [Paint]
paintsOf pdf =
  concat
    [ snd (run i PageContent 0 (pageResources os p) initialGs (pageContent os p))
    | (i, p) <- zip [1 ..] (pagesOf pdf)
    ]
  where
    os = objsOf pdf
    run :: Int -> PaintSource -> Int -> Obj -> Gs -> ByteString -> (Gs, [Paint])
    run page src depth res gs0 content = case contentOperations content of
      Nothing -> (gs0, [])
      Just ops -> let (gs', _, out) = foldl' step (gs0, [], []) ops in (gs', concat (reverse out))
      where
        paint op (sp, cs) = Paint page op src sp cs
        fillAndStroke op gs = [paint op (gsFill gs), paint op (gsStroke gs)]
        textPaints op gs = case gsRender gs of
          m | m `elem` [0, 4] -> [paint op (gsFill gs)]
          m | m `elem` [1, 5] -> [paint op (gsStroke gs)]
          m | m `elem` [2, 6] -> fillAndStroke op gs
          _ -> []
        step (gs, stack, out) (opB, args) =
          let op = TE.decodeLatin1 opB
              argsT = map TE.decodeLatin1 args
              same = (gs, stack, out)
              with gs' = (gs', stack, out)
              emit ps = (gs, stack, ps : out)
           in case op of
                "q" -> (gs, gs : stack, out)
                "Q" -> case stack of
                  g : rest -> (g, rest, out)
                  [] -> same
                "g" -> with gs {gsFill = (PsDeviceGray, argsT)}
                "G" -> with gs {gsStroke = (PsDeviceGray, argsT)}
                "rg" -> with gs {gsFill = (PsDeviceRgb, argsT)}
                "RG" -> with gs {gsStroke = (PsDeviceRgb, argsT)}
                "k" -> with gs {gsFill = (PsDeviceCmyk, argsT)}
                "K" -> with gs {gsStroke = (PsDeviceCmyk, argsT)}
                "cs" | [a] <- args, Just n <- nameOperand a -> with gs {gsFill = spaceOf os res (OName n)}
                "CS" | [a] <- args, Just n <- nameOperand a -> with gs {gsStroke = spaceOf os res (OName n)}
                _ | op `elem` ["sc", "scn"] -> with gs {gsFill = (fst (gsFill gs), argsT)}
                _ | op `elem` ["SC", "SCN"] -> with gs {gsStroke = (fst (gsStroke gs), argsT)}
                "Tr" | [a] <- args, [(m, "")] <- reads (show' a) -> with gs {gsRender = m}
                _ | op `elem` ["f", "F", "f*"] -> emit [paint op (gsFill gs)]
                _ | op `elem` ["S", "s"] -> emit [paint op (gsStroke gs)]
                _ | op `elem` ["B", "B*", "b", "b*"] -> emit (fillAndStroke op gs)
                _ | op `elem` ["Tj", "TJ", "'", "\""] -> emit (textPaints op gs)
                "sh"
                  | [a] <- args,
                    Just n <- nameOperand a ->
                      emit [paint op (maybe (gsFill gs) (spaceOf os res) (look os "Shading" res >>= look os n >>= look os "ColorSpace"))]
                "Do"
                  | [a] <- args,
                    Just n <- nameOperand a,
                    depth < maxFormDepth,
                    Just x <- look os "XObject" res >>= look os n,
                    look os "Subtype" x == Just (OName "Form") ->
                      let inner = case src of
                            PageContent -> FormXObject [n]
                            FormXObject ns -> FormXObject (ns <> [n])
                          res' = fromMaybe res (look os "Resources" x)
                          (_, ps) = run page inner (depth + 1) res' gs (fromMaybe "" (streamData os x))
                       in emit ps
                _ -> same
        show' = T.unpack . TE.decodeLatin1

-- ------------------------------------------------------------------ fonts and spot colours

{- | The FontName of each font descriptor with none of FontFile, FontFile2
and FontFile3, in the order of the objects (golem-cli ADR 0006, docs/adr
ADR 0232).
-}
unembeddedFonts :: PdfObjects -> [Text]
unembeddedFonts (PdfObjects _ objects _) =
  [ case lookup "FontName" (dictOf o) of
      Just (OName n) -> n
      _ -> "名前のないフォント"
  | o <- objects,
    lookup "Type" (dictOf o) == Just (OName "FontDescriptor"),
    not (any (\k -> any ((== k) . fst) (dictOf o)) ["FontFile", "FontFile2", "FontFile3"])
  ]

{- | The colorants of the Separation and DeviceN colour spaces of all the
objects, used or not, each once in the order found (docs/adr ADR 0232):
not All and None, and not the process colorants Cyan, Magenta, Yellow
and Black, which are no plate of their own.
-}
spotColorants :: PdfObjects -> [Text]
spotColorants (PdfObjects _ objects trailer) = nubOrdered (concatMap colorants (trailer : objects))
  where
    colorants = \case
      OArr (OName "Separation" : OName c : rest) -> spot c <> concatMap colorants rest
      OArr (OName "DeviceN" : OArr cs : rest) -> concat [spot c | OName c <- cs] <> concatMap colorants rest
      OArr xs -> concatMap colorants xs
      ODict kvs -> concatMap (colorants . snd) kvs
      OStream kvs _ -> concatMap (colorants . snd) kvs
      _ -> []
    spot c =
      let n = readableName c
       in [n | n `notElem` ["All", "None", "Cyan", "Magenta", "Yellow", "Black"]]
    nubOrdered = reverse . foldl' (\acc x -> if x `elem` acc then acc else x : acc) []
