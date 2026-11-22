-- | Process-colour conversion of imported figures (root ADR 0403).
module Golem.Typeset.PdfColor (recolorImportedPage) where

import Control.Monad (foldM)
import Data.Bits (shiftR, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (isDigit)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P
import Golem.Typeset.FigureColor (Cmyk, RasterAnalysis (..), RasterKind (..))

-- A colour is kept in the source space until an operator actually paints it.
data Color = Gray !Rational | Rgb !Rational !Rational !Rational | CmykColor !Rational !Rational !Rational !Rational
  deriving stock (Eq, Ord, Show)

data Space = GraySpace | RgbSpace | CmykSpace
  deriving stock (Eq, Ord, Show)

data Graphics = Graphics
  { fillColor :: !Color,
    strokeColor :: !Color,
    fillSpace :: !Space,
    strokeSpace :: !Space,
    textMode :: !Int,
    fillAlpha :: !Rational,
    strokeAlpha :: !Rational
  }
  deriving stock (Eq, Ord, Show)

data Scan = Scan !Graphics ![Graphics] !RasterKind ![ByteString] !(Maybe Int)

{- | Nothing means that actual painting uses multiple colours, or paints nothing.
Form resources are cloned so that references from soft masks remain unchanged.
-}
recolorImportedPage :: Cmyk -> (P.ImageData -> Either Text RasterAnalysis) -> P.ImportedPage -> Either Text (Maybe P.ImportedPage)
recolorImportedPage swatch analyze page = do
  if P.ipDecodedBytes page < 0 || P.ipDecodedBytes page > P.maxDecodedBytes
    then Left "PDF 図版の展開済みサイズが不正です"
    else Right ()
  let source = Map.fromList (P.ipObjects page)
      initialState = Resources {sourceObjects = source, decodedStreams = Map.empty, formSummaries = Map.empty, convertedForms = Map.empty, convertedObjects = Map.empty, scopeBindings = Map.empty, sourceTables = Map.empty, clonedResources = Map.empty, rasterAnalyzer = analyze, rasterResults = Map.empty, convertedImages = Map.empty, remainingBytes = P.maxDecodedBytes - P.ipDecodedBytes page}
  scope <- resourceScope PageResources (P.ipResources page) initialState
  (Scan _ _ kind _ _, analyzed) <- scanForms swatch False Set.empty scope (P.ipResources page) initial (P.ipContent page) initialState
  case kind of
    Multicolor -> Right Nothing
    Unpainted -> Right Nothing
    _ -> do
      let prefix = BC.unlines [paint swatch (Gray 0) False, paint swatch (Gray 0) True]
      charged <- charge (BS.length prefix) analyzed
      (content, _, rendered) <- renderForms swatch Set.empty scope (P.ipResources page) initial (P.ipContent page) charged
      finalized <- cloneResourceDictionaries rendered
      resources <- bindScope scope (P.ipResources page) finalized
      let scopes = Map.fromList [(clone, childScope) | ((_, childScope), clone) <- Map.toList (convertedForms rendered)]
      objects <- traverse (finalizeClone scopes finalized) (Map.toAscList (convertedObjects finalized))
      let result = prefix <> content
          identity = P.sha256 (P.ipFile page <> BC.pack (show (P.ipPage page, swatch)) <> P.sha256 result)
      Right (Just page {P.ipContent = result, P.ipResources = resources, P.ipObjects = P.ipObjects page <> objects, P.ipFile = identity, P.ipColors = [P.UseCmyk], P.ipDecodedBytes = P.maxDecodedBytes - remainingBytes rendered})
  where
    initial = Graphics (Gray 0) (Gray 0) GraySpace GraySpace 0 1 1

data Scope = PageResources | InlineResources !P.ObjNum | IndirectResources !P.ObjNum
  deriving stock (Eq, Ord, Show)

-- Original objects remain intact: a paint resource may also be a soft mask.
data Resources = Resources
  { sourceObjects :: !(Map.Map P.ObjNum (P.ObjOf P.ObjNum)),
    decodedStreams :: !(Map.Map P.ObjNum ByteString),
    formSummaries :: !(Map.Map (P.ObjNum, Scope, Graphics) RasterKind),
    convertedForms :: !(Map.Map (P.ObjNum, Scope) P.ObjNum),
    convertedObjects :: !(Map.Map P.ObjNum (P.ObjOf P.ObjNum)),
    scopeBindings :: !(Map.Map Scope (Map.Map Text P.ObjNum)),
    sourceTables :: !(Map.Map Scope (Map.Map Text (P.ObjOf P.ObjNum))),
    clonedResources :: !(Map.Map Scope P.ObjNum),
    rasterAnalyzer :: !(P.ImageData -> Either Text RasterAnalysis),
    rasterResults :: !(Map.Map (P.ObjNum, Scope) RasterAnalysis),
    convertedImages :: !(Map.Map (P.ObjNum, Scope) P.ObjNum),
    remainingBytes :: !Int
  }

charge :: Int -> Resources -> Either Text Resources
charge bytes state
  | bytes < 0 || bytes > remainingBytes state = Left budgetError
  | otherwise = Right state {remainingBytes = remainingBytes state - bytes}

-- The same saved graphics context reuses a summary; shared Form graphs are
-- not expanded once for every path through them.
scanForms :: Cmyk -> Bool -> Set.Set P.ObjNum -> Scope -> P.ObjOf P.ObjNum -> Graphics -> ByteString -> Resources -> Either Text (Scan, Resources)
scanForms swatch emit active scope resources graphics content state = do
  operations <- maybe (Left "PDF 図版の描画命令を読めません") Right (P.contentOperations content)
  go (Scan graphics [] Unpainted [] (if emit then Just (remainingBytes state) else Nothing)) state operations
  where
    go scan@(Scan _ _ Multicolor _ _) st _ | not emit = Right (scan, st)
    go scan@(Scan _ saved _ _ _) st []
      | null saved = Right (scan, st)
      | otherwise = Left "PDF 図版の描画状態が閉じていません"
    go (Scan before saved seen output _) st (operation@(operator, args) : rest) = do
      current <- externalGraphics resources before operation st
      (external, updated) <-
        if operator == "Do"
          then do
            (key, fields, childResources, childScope, prepared) <- xObjectResource resources scope args st
            if lookup "Subtype" fields == Just (P.OName "Image")
              then
                if fillAlpha current == 0
                  then Right (Just Unpainted, prepared)
                  else do
                    (analysis, decoded) <- analyzePdfImage childScope childResources key fields prepared
                    Right (Just (raKind analysis), decoded)
              else do
                let cacheKey = (key, childScope, current)
                case Map.lookup cacheKey (formSummaries prepared) of
                  Just kind -> Right (Just kind, prepared)
                  Nothing -> do
                    guardForm active key
                    (body, decoded) <- decodePdfStream key fields prepared
                    (Scan _ _ kind _ _, child) <- scanForms swatch False (Set.insert key active) childScope childResources current body decoded
                    Right (Just kind, child {formSummaries = Map.insert cacheKey kind (formSummaries child)})
          else Right (Nothing, st)
      let synced = Scan current saved seen output (if emit then Just (remainingBytes updated) else Nothing)
      next@(Scan _ _ _ _ budget) <- stepWith external swatch synced operation
      go next (case budget of Nothing -> updated; Just remaining -> updated {remainingBytes = remaining}) rest

renderForms :: Cmyk -> Set.Set P.ObjNum -> Scope -> P.ObjOf P.ObjNum -> Graphics -> ByteString -> Resources -> Either Text (ByteString, P.ObjOf P.ObjNum, Resources)
renderForms swatch active scope resources graphics content state = do
  operations <- maybe (Left "PDF 図版の描画命令を読めません") Right (P.contentOperations content)
  go (Scan graphics [] Unpainted [] (Just (remainingBytes state))) resources state operations
  where
    go (Scan _ saved _ output _) bound st []
      | null saved = Right (BC.unlines (reverse output), bound, st)
      | otherwise = Left "PDF 図版の描画状態が閉じていません"
    go (Scan before saved seen output _) bound st (operation@(operator, args) : rest) = do
      current <- externalGraphics resources before operation st
      (external, rebound, updated, rewritten) <-
        if operator == "Do"
          then do
            (key, fields, childResources, childScope, prepared) <- xObjectResource resources scope args st
            (clone, child) <-
              if lookup "Subtype" fields == Just (P.OName "Image")
                then if fillAlpha current == 0 then Right (key, prepared) else convertPdfImage childScope childResources key fields prepared
                else case Map.lookup (key, childScope) (convertedForms prepared) of
                  Just converted -> Right (converted, prepared)
                  Nothing -> do
                    guardForm active key
                    (body, decoded) <- decodePdfStream key fields prepared
                    (painted, _, rendered) <- renderForms swatch (Set.insert key active) childScope childResources current body decoded
                    fresh <- freshObject rendered
                    let fieldsOut = [(k, v) | (k, v) <- fields, k `notElem` ["Length", "Filter", "DecodeParms", "DL"]]
                    Right (fresh, rendered {convertedForms = Map.insert (key, childScope) fresh (convertedForms rendered), convertedObjects = Map.insert fresh (P.OStream fieldsOut painted) (convertedObjects rendered)})
            alias <- freshAlias scope clone child
            let bindings = Map.insertWith Map.union scope (Map.singleton alias clone) (scopeBindings child)
            Right (Just Unpainted, bound, child {scopeBindings = bindings}, ("Do", ["/" <> TE.encodeUtf8 alias]))
          else Right (Nothing, bound, st, operation)
      next@(Scan _ _ _ _ budget) <- stepWith external swatch (Scan current saved seen output (Just (remainingBytes updated))) rewritten
      go next rebound (case budget of Nothing -> updated; Just remaining -> updated {remainingBytes = remaining}) rest

-- Use the importer's existing nesting boundary for reference and Form graphs.
guardForm :: Set.Set P.ObjNum -> P.ObjNum -> Either Text ()
guardForm active key
  | Set.member key active || Set.size active >= P.maxNesting = Left "PDF 図版の Form 参照が循環しているか深すぎます"
  | otherwise = Right ()

externalGraphics :: P.ObjOf P.ObjNum -> Graphics -> (ByteString, [ByteString]) -> Resources -> Either Text Graphics
externalGraphics resources current ("gs", args) state = do
  name <- resourceName args
  entries <- dictionary resources state
  states <- maybe (Left "PDF 図版の ExtGState がありません") (`dictionary` state) (lookup "ExtGState" entries)
  selected <- maybe (Left "PDF 図版の描画状態が見つかりません") (`dictionary` state) (lookup name states)
  fill <- alpha "ca" (fillAlpha current) selected
  stroke <- alpha "CA" (strokeAlpha current) selected
  Right current {fillAlpha = fill, strokeAlpha = stroke}
  where
    alpha name fallback fields = case lookup name fields of
      Nothing -> Right fallback
      Just value -> do
        resolved <- dereference Set.empty value state
        amount <- case resolved of
          P.OInt number -> Right (fromInteger number)
          P.OReal number -> maybe (Left "PDF 図版の不透明度が不正です") Right (decimal (TE.encodeUtf8 number))
          _ -> Left "PDF 図版の不透明度が不正です"
        if amount < 0 || amount > 1 then Left "PDF 図版の不透明度が範囲外です" else Right amount
externalGraphics _ current _ _ = Right current

resourceName :: [ByteString] -> Either Text Text
resourceName [name] | BS.take 1 name == "/" = Right (TE.decodeLatin1 (BS.drop 1 name))
resourceName _ = Left "PDF 図版の資源名が不正です"

resourceScope :: Scope -> P.ObjOf P.ObjNum -> Resources -> Either Text Scope
resourceScope fallback object state = go Set.empty Nothing object
  where
    go seen _ (P.ORef key) = do
      guardForm seen key
      value <- maybe (Left "PDF 図版の資源の参照先がありません") Right (Map.lookup key (sourceObjects state))
      go (Set.insert key seen) (Just key) value
    go _ reference (P.ODict _) = Right (maybe fallback IndirectResources reference)
    go _ _ _ = Left "PDF 図版の資源辞書が不正です"

sourceTable :: Scope -> P.ObjOf P.ObjNum -> Resources -> Either Text (Map.Map Text (P.ObjOf P.ObjNum), Resources)
sourceTable scope resources state = case Map.lookup scope (sourceTables state) of
  Just table -> Right (table, state)
  Nothing -> do
    values <- dictionary resources state
    objects <- maybe (Right []) (`dictionary` state) (lookup "XObject" values)
    let table = Map.fromList objects
    Right (table, state {sourceTables = Map.insert scope table (sourceTables state)})

xObjectResource :: P.ObjOf P.ObjNum -> Scope -> [ByteString] -> Resources -> Either Text (P.ObjNum, [(Text, P.ObjOf P.ObjNum)], P.ObjOf P.ObjNum, Scope, Resources)
xObjectResource resources scope args state = do
  name <- resourceName args
  (objects, prepared) <- sourceTable scope resources state
  key <- case Map.lookup name objects of
    Just (P.ORef key) -> Right key
    _ -> Left "PDF 図版の XObject が見つかりません"
  object <- maybe (Left "PDF 図版の XObject の参照先がありません") Right (Map.lookup key (sourceObjects state))
  fields <- case object of
    P.OStream fields _ | lookup "Subtype" fields `elem` [Just (P.OName "Form"), Just (P.OName "Image")] -> Right fields
    _ -> Left "PDF 図版の XObject の種類に対応していません"
  case lookup "Resources" fields of
    _ | lookup "Subtype" fields == Just (P.OName "Image") -> Right (key, fields, resources, scope, prepared)
    Nothing -> Right (key, fields, resources, scope, prepared)
    Just own -> do
      childScope <- resourceScope (InlineResources key) own prepared
      Right (key, fields, own, childScope, prepared)

dictionary :: P.ObjOf P.ObjNum -> Resources -> Either Text [(Text, P.ObjOf P.ObjNum)]
dictionary object state = do
  resolved <- dereference Set.empty object state
  case resolved of
    P.ODict fields -> Right fields
    _ -> Left "PDF 図版の資源辞書が不正です"

dereference :: Set.Set P.ObjNum -> P.ObjOf P.ObjNum -> Resources -> Either Text (P.ObjOf P.ObjNum)
dereference seen (P.ORef key) state = do
  guardForm seen key
  object <- maybe (Left "PDF 図版の資源の参照先がありません") Right (Map.lookup key (sourceObjects state))
  dereference (Set.insert key seen) object state
dereference _ object _ = Right object

decodePdfStream :: P.ObjNum -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (ByteString, Resources)
decodePdfStream key fields state = case Map.lookup key (decodedStreams state) of
  Just body -> Right (body, state)
  Nothing -> do
    source <- case Map.lookup key (sourceObjects state) of
      Just (P.OStream _ bytes) -> Right bytes
      _ -> Left "PDF 図版の描画ストリームがありません"
    filters <- traverse (\(name, value) -> (name,) <$> deep 0 Set.empty value) [(name, value) | (name, value) <- fields, name `elem` ["Filter", "DecodeParms"]]
    (body, cost) <- either (const (Left "PDF 図版の描画ストリームを展開できません")) Right (P.decodeImportedStream (remainingBytes state) filters source)
    charged <- charge (max cost (BS.length body)) state
    Right (body, charged {decodedStreams = Map.insert key body (decodedStreams charged)})
  where
    deep depth _ _ | depth > P.maxNesting = Left "PDF 図版のフィルターの辞書が深すぎます"
    deep depth seen (P.ORef reference) = do
      guardForm seen reference
      value <- maybe (Left "PDF 図版のフィルターの参照先がありません") Right (Map.lookup reference (sourceObjects state))
      deep (depth + 1) (Set.insert reference seen) value
    deep depth seen (P.OArr values) = P.OArr <$> traverse (deep (depth + 1) seen) values
    deep depth seen (P.ODict values) = P.ODict <$> traverse (\(name, value) -> (name,) <$> deep (depth + 1) seen value) values
    deep _ _ value = Right value

-- The raster analyzer is shared with standalone figures. Reserve both decoded
-- samples and converted pixels before calling it, including on 32-bit targets.
analyzePdfImage :: Scope -> P.ObjOf P.ObjNum -> P.ObjNum -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (RasterAnalysis, Resources)
analyzePdfImage scope resources key fields state = case Map.lookup (key, scope) (rasterResults state) of
  Just analysis -> Right (analysis, state)
  Nothing -> do
    width <- positive "Width"
    height <- positive "Height"
    bits <- positive "BitsPerComponent"
    (space, components, profile, colored) <- pdfImageSpace resources fields state
    if bits `notElem` [1, 2, 4, 8, 16] then Left "PDF 図版の画像のビット深度に対応していません" else Right ()
    if any unsupportedMask fields then Left "PDF 図版の画像マスクを保って色を置き換えられません" else Right ()
    ranges <- unitDecode components fields state
    let reversed = ranges == concat (replicate components [True, False])
    if ranges == concat (replicate components [False, True]) || reversed then Right () else Left "PDF 図版の画像の Decode に対応していません"
    let pixels = width * height
        inputBytes = ((width * toInteger components * bits + 7) `div` 8) * height
        minimumOutputBytes = pixels * 4 * (if bits == 16 then 2 else 1)
    if inputBytes + minimumOutputBytes > toInteger (remainingBytes colored) || width > toInteger (maxBound :: Int) || height > toInteger (maxBound :: Int)
      then Left budgetError
      else Right ()
    (bytes, decoded) <- decodePdfStream key fields colored
    if toInteger (BS.length bytes) /= inputBytes then Left "PDF 図版の画像の寸法とデータ長が一致しません" else Right ()
    (samples, sampled) <-
      if reversed
        then do
          inverted <- charge (BS.length bytes) decoded
          Right (BS.map (255 -) bytes, inverted)
        else Right (bytes, decoded)
    (alpha, masked) <- pdfImageAlpha width height bits components bytes fields sampled
    let outputBits = if bits == 16 || maybe False ((== 16) . P.alphaBits) alpha then 16 else 8
        outputBytes = pixels * 4 * (outputBits `div` 8)
    reserved <- charge (fromInteger outputBytes) masked
    let input = P.ImageData (fromInteger width) (fromInteger height) (fromInteger bits) space profile samples False False alpha
    analysis <- rasterAnalyzer reserved input
    case raImage analysis of
      Nothing | raKind analysis `elem` [Unpainted, Multicolor] -> Right ()
      Just converted
        | P.imgWidth converted == P.imgWidth input,
          P.imgHeight converted == P.imgHeight input,
          P.imgBits converted == fromInteger outputBits,
          P.imgColor converted == P.CsCmyk,
          isNothing (P.imgIcc converted),
          not (P.imgDct converted),
          not (P.imgInvertedCmyk converted),
          P.imgAlpha converted == P.imgAlpha input,
          toInteger (BS.length (P.imgData converted)) == outputBytes ->
            Right ()
      _ -> Left "PDF 図版の画像の色置換結果が不正です"
    Right (analysis, reserved {rasterResults = Map.insert (key, scope) analysis (rasterResults reserved)})
  where
    positive name = do
      value <- maybe (Left "PDF 図版の画像の寸法がありません") Right (lookup name fields)
      resolved <- dereference Set.empty value state
      case resolved of
        P.OInt n | n > 0 -> Right n
        _ -> Left "PDF 図版の画像の寸法が不正です"
    unsupportedMask ("ImageMask", P.OBool False) = False
    unsupportedMask (name, _) = name == "ImageMask"

-- ICC profile streams share the same bounded decoder and cache as image data.
-- Range affects the default image Decode; non-unit ranges must not silently
-- be interpreted as ordinary device samples.
pdfImageSpace :: P.ObjOf P.ObjNum -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (P.ColorSpace, Int, Maybe BS.ByteString, Resources)
pdfImageSpace resources fields state = do
  value <- maybe (Left invalid) Right (lookup "ColorSpace" fields)
  resolve Set.empty True value
  where
    invalid = "PDF 図版の画像の色空間に対応していません"
    plain space components = Right (space, components, Nothing, state)
    colorResource name = do
      entries <- dictionary resources state
      spaces <- maybe (Right []) (`dictionary` state) (lookup "ColorSpace" entries)
      Right (lookup name spaces)
    named seen defaults name value
      | Set.member name seen || Set.size seen >= P.maxNesting = Left invalid
      | otherwise = resolve (Set.insert name seen) defaults value
    device seen defaults name space components
      | not defaults = plain space components
      | otherwise = do
          replacement <- colorResource name
          result@(_, count, _, _) <- maybe (plain space components) (named seen False name) replacement
          if count == components then Right result else Left invalid
    resolve seen defaults value = do
      resolved <- dereference Set.empty value state
      case resolved of
        P.OName "DeviceGray" -> device seen defaults "DefaultGray" P.CsGray 1
        P.OName "DeviceRGB" -> device seen defaults "DefaultRGB" P.CsRgb 3
        P.OName "DeviceCMYK" -> device seen defaults "DefaultCMYK" P.CsCmyk 4
        P.OName name -> do
          selected <- colorResource name >>= maybe (Left invalid) Right
          named seen defaults name selected
        P.OArr [P.OName "ICCBased", reference] -> do
          (key, entries) <- pdfStreamReference invalid state Set.empty reference
          count <- maybe (Left invalid) (\n -> dereference Set.empty n state) (lookup "N" entries)
          (space, components) <- case count of
            P.OInt 1 -> Right (P.CsGray, 1)
            P.OInt 3 -> Right (P.CsRgb, 3)
            P.OInt 4 -> Right (P.CsCmyk, 4)
            _ -> Left invalid
          ranges <- unitDecode components [("Decode", range) | Just range <- [lookup "Range" entries]] state
          if ranges == concat (replicate components [False, True]) then Right () else Left invalid
          (profile, decoded) <- decodePdfStream key entries state
          Right (space, components, Just profile, decoded)
        _ -> Left invalid

pdfStreamReference :: Text -> Resources -> Set.Set P.ObjNum -> P.ObjOf P.ObjNum -> Either Text (P.ObjNum, [(Text, P.ObjOf P.ObjNum)])
pdfStreamReference invalid state seen (P.ORef key) = do
  guardForm seen key
  case Map.lookup key (sourceObjects state) of
    Just (P.OStream entries _) -> Right (key, entries)
    Just next@(P.ORef _) -> pdfStreamReference invalid state (Set.insert key seen) next
    _ -> Left invalid
pdfStreamReference invalid _ _ _ = Left invalid

-- Only the default sample range and its reversal are needed here. Reading
-- their endpoints as zero or one avoids constructing huge decimal rationals.
unitDecode :: Int -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text [Bool]
unitDecode components fields state = case lookup "Decode" fields of
  Nothing -> Right (concat (replicate components [False, True]))
  Just value -> do
    resolved <- dereference Set.empty value state
    case resolved of
      P.OArr values | length values == 2 * components -> traverse endpoint values
      _ -> Left invalid
  where
    invalid = "PDF 図版の画像の Decode を解釈できません"
    endpoint value = do
      resolved <- dereference Set.empty value state
      case resolved of
        P.OInt 0 -> Right False
        P.OInt 1 -> Right True
        P.OReal number ->
          let (negative, body) = case T.uncons number of Just ('-', rest) -> (True, rest); Just ('+', rest) -> (False, rest); _ -> (False, number)
              (whole, tailPart) = T.breakOn "." body
              fraction = if T.null tailPart then "" else T.drop 1 tailPart
              normalized = T.dropWhile (== '0') whole
           in if T.null body || body == "." || not (T.all (== '0') fraction)
                then Left invalid
                else if T.null normalized then Right False else if normalized == "1" && not negative then Right True else Left invalid
        _ -> Left invalid

-- The original mask remains referenced by the converted image. Its decoded
-- samples are used only to classify visible pixels; no mask object is rewritten.
pdfImageAlpha :: Integer -> Integer -> Integer -> Int -> ByteString -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (Maybe P.Alpha, Resources)
pdfImageAlpha width height imageBits components raw fields state = case lookup "SMask" fields of
  Nothing -> colorKeyAlpha width height imageBits components raw fields state
  Just P.ONull -> colorKeyAlpha width height imageBits components raw fields state
  Just (P.OName "None") -> colorKeyAlpha width height imageBits components raw fields state
  Just reference -> do
    (key, maskFields) <- pdfStreamReference invalid state Set.empty reference
    dimensions <- traverse (\name -> maybe (Left invalid) (\value -> dereference Set.empty value state) (lookup name maskFields)) ["Width", "Height", "BitsPerComponent", "ColorSpace", "Subtype"]
    bits <- case dimensions of
      [P.OInt w, P.OInt h, P.OInt depth, P.OName "DeviceGray", P.OName "Image"]
        | w == width, h == height, depth `elem` [1, 2, 4, 8, 16] -> Right depth
      _ -> Left invalid
    if any (`isJustField` maskFields) ["Mask", "SMask", "Matte"] || maybe False (/= P.OBool False) (lookup "ImageMask" maskFields) then Left invalid else Right ()
    let sampleBytes = ((width * bits + 7) `div` 8) * height
    if sampleBytes > toInteger (remainingBytes state) then Left budgetError else Right ()
    ranges <- unitDecode 1 maskFields state
    (bytes, decoded) <- decodePdfStream key maskFields state
    if toInteger (BS.length bytes) /= sampleBytes then Left invalid else Right ()
    case ranges of
      [False, True] -> Right (Just (P.Alpha (fromInteger bits) bytes), decoded)
      [True, False] -> do
        reserved <- charge (BS.length bytes) decoded
        Right (Just (P.Alpha (fromInteger bits) (BS.map (255 -) bytes)), reserved)
      _ -> Left invalid
  where
    invalid = "PDF 図版のソフトマスクを保って色を置き換えられません"
    isJustField name entries = case lookup name entries of Nothing -> False; Just _ -> True

-- Colour-key ranges compare the original integer samples, before Decode.
-- Their component count changes on recoloring, so emit an equivalent gray
-- soft mask rather than retaining the old ranges against CMYK components.
colorKeyAlpha :: Integer -> Integer -> Integer -> Int -> ByteString -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (Maybe P.Alpha, Resources)
colorKeyAlpha width height bits components raw fields state = case lookup "Mask" fields of
  Nothing -> Right (Nothing, state)
  Just value -> do
    resolved <- dereference Set.empty value state
    values <- case resolved of
      P.OArr entries | length entries == 2 * components -> traverse (\entry -> dereference Set.empty entry state) entries
      _ -> Left invalid
    ranges <- pairs values
    let pixels = fromInteger (width * height)
        rowBytes = fromInteger ((width * toInteger components * bits + 7) `div` 8)
        depth = fromInteger bits
        at pixel channel =
          let sample = (pixel `mod` fromInteger width) * components + channel
              bit = sample * depth
              offset = (pixel `div` fromInteger width) * rowBytes + bit `div` 8
           in if depth == 16
                then fromIntegral (BS.index raw offset) * 256 + fromIntegral (BS.index raw (offset + 1))
                else (fromIntegral (BS.index raw offset) `shiftR` (8 - depth - bit `mod` 8)) .&. (2 ^ depth - 1)
        visible pixel = not (and [sample >= low && sample <= high | (channel, (low, high)) <- zip [0 ..] ranges, let sample = at pixel channel])
    reserved <- charge pixels state
    let alpha = fst (BS.unfoldrN pixels (\pixel -> Just (if visible pixel then 255 else 0, pixel + 1)) 0)
    Right (Just (P.Alpha 8 alpha), reserved)
  where
    invalid = "PDF 図版の画像の色キーマスクを解釈できません"
    pairs :: [P.ObjOf P.ObjNum] -> Either Text [(Int, Int)]
    pairs [] = Right []
    pairs (P.OInt low : P.OInt high : rest)
      | 0 <= low, low <= high, high < 2 ^ bits = ((fromInteger low, fromInteger high) :) <$> pairs rest
    pairs _ = Left invalid

-- Existing soft masks keep their original objects. Colour-key masks need a
-- new independent object because the converted image has four components.
convertedImageMask :: P.ImageData -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text ([(Text, P.ObjOf P.ObjNum)], Resources)
convertedImageMask image fields state
  | hasSoftMask = Right (withoutKey, state)
  | Just _ <- lookup "Mask" fields,
    Just alpha <- P.imgAlpha image = do
      fresh <- freshObject state
      let entries = [("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt (toInteger (P.imgWidth image))), ("Height", P.OInt (toInteger (P.imgHeight image))), ("ColorSpace", P.OName "DeviceGray"), ("BitsPerComponent", P.OInt (toInteger (P.alphaBits alpha)))] <> [("Interpolate", value) | Just value <- [lookup "Interpolate" fields]]
      Right (("SMask", P.ORef fresh) : filter ((/= "SMask") . fst) withoutKey, state {convertedObjects = Map.insert fresh (P.OStream entries (P.alphaSamples alpha)) (convertedObjects state)})
  | otherwise = Right (fields, state)
  where
    withoutKey = filter ((/= "Mask") . fst) fields
    hasSoftMask = case lookup "SMask" fields of Nothing -> False; Just P.ONull -> False; Just (P.OName "None") -> False; Just _ -> True

convertPdfImage :: Scope -> P.ObjOf P.ObjNum -> P.ObjNum -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (P.ObjNum, Resources)
convertPdfImage scope resources key fields state = case Map.lookup (key, scope) (convertedImages state) of
  Just converted -> Right (converted, state)
  Nothing -> do
    (analysis, decoded) <- analyzePdfImage scope resources key fields state
    case raImage analysis of
      Nothing -> Right (key, decoded)
      Just image -> do
        (maskedFields, masked) <- convertedImageMask image fields decoded
        fresh <- freshObject masked
        let fieldsOut = [(name, value) | (name, value) <- maskedFields, name `notElem` ["Length", "Filter", "DecodeParms", "DL", "Decode", "ColorSpace", "BitsPerComponent", "Resources"]] <> [("ColorSpace", P.OName "DeviceCMYK"), ("BitsPerComponent", P.OInt (toInteger (P.imgBits image)))]
        Right (fresh, masked {convertedImages = Map.insert (key, scope) fresh (convertedImages masked), convertedObjects = Map.insert fresh (P.OStream fieldsOut (P.imgData image)) (convertedObjects masked)})

freshObject :: Resources -> Either Text P.ObjNum
freshObject state =
  let lowest = min 0 (min (maybe 0 fst (Map.lookupMin (sourceObjects state))) (maybe 0 fst (Map.lookupMin (convertedObjects state))))
   in if lowest == minBound then Left "PDF 図版の変換用オブジェクト番号がありません" else Right (lowest - 1)

-- Generated names leave every original binding available to unmodified masks.
freshAlias :: Scope -> P.ObjNum -> Resources -> Either Text Text
freshAlias scope clone state = do
  names <- maybe (Left "PDF 図版の資源辞書を準備できません") Right (Map.lookup scope (sourceTables state))
  let choose candidate = if Map.member candidate names then choose (candidate <> "_") else candidate
  Right (choose ("GolemFigureColor" <> TE.decodeLatin1 (BC.pack (show (negate (toInteger clone))))))

-- Shared indirect dictionaries are cloned once, so their sharing survives.
cloneResourceDictionaries :: Resources -> Either Text Resources
cloneResourceDictionaries state = foldM clone state (Map.keys (scopeBindings state))
  where
    clone current scope@(IndirectResources key) = do
      bound <- bindScopeRaw scope (P.ORef key) current
      fresh <- freshObject current
      Right current {convertedObjects = Map.insert fresh bound (convertedObjects current), clonedResources = Map.insert scope fresh (clonedResources current)}
    clone current _ = Right current

-- Install aliases once at their original resource owner. Forms without their
-- own Resources keep inheriting that dictionary instead of copying it.
bindScope :: Scope -> P.ObjOf P.ObjNum -> Resources -> Either Text (P.ObjOf P.ObjNum)
bindScope scope resources state = case Map.lookup scope (clonedResources state) of
  Just key -> Right (P.ORef key)
  Nothing -> bindScopeRaw scope resources state

bindScopeRaw :: Scope -> P.ObjOf P.ObjNum -> Resources -> Either Text (P.ObjOf P.ObjNum)
bindScopeRaw scope resources state = case Map.lookup scope (scopeBindings state) of
  Nothing -> Right resources
  Just additions -> do
    values <- dictionary resources state
    originals <- maybe (Left "PDF 図版の資源辞書を準備できません") Right (Map.lookup scope (sourceTables state))
    let objects = Map.union (Map.map P.ORef additions) originals
    Right (P.ODict ([(k, v) | (k, v) <- values, k /= "XObject"] <> [("XObject", P.ODict (Map.toAscList objects))]))

finalizeClone :: Map.Map P.ObjNum Scope -> Resources -> (P.ObjNum, P.ObjOf P.ObjNum) -> Either Text (P.ObjNum, P.ObjOf P.ObjNum)
finalizeClone scopes state (key, P.OStream fields content) = case lookup "Resources" fields of
  Nothing -> Right (key, P.OStream fields content)
  Just resources -> do
    scope <- maybe (Left "PDF 図版の Form の資源辞書がありません") Right (Map.lookup key scopes)
    bound <- bindScope scope resources state
    Right (key, P.OStream ([(k, v) | (k, v) <- fields, k /= "Resources"] <> [("Resources", bound)]) content)
finalizeClone _ _ object = Right object

budgetError :: Text
budgetError = "PDF 図版の色変換が展開上限を超えます"

stepWith :: Maybe RasterKind -> Cmyk -> Scan -> (ByteString, [ByteString]) -> Either Text Scan
stepWith external swatch (Scan graphics stack kind output budget) (operator, args) = do
  let keep state saved seen bytes = case budget of
        Nothing -> Right (Scan state saved seen [] Nothing)
        Just remaining
          | BS.length bytes >= remaining -> Left budgetError
          | otherwise -> Right (Scan state saved seen (bytes : output) (Just (remaining - BS.length bytes - 1)))
      original = BC.unwords (args <> [operator])
      same = keep graphics stack kind original
      painted colors = keep graphics stack (foldl mergeKind kind (map colorKind colors)) original
      colorOp isStroke space = do
        color <- parseColor space args
        let state = if isStroke then graphics {strokeColor = color, strokeSpace = space} else graphics {fillColor = color, fillSpace = space}
        keep state stack kind (paint swatch color isStroke)
      spaceOp isStroke = do
        space <- case args of
          ["/DeviceGray"] -> Right GraySpace
          ["/DeviceRGB"] -> Right RgbSpace
          ["/GolemSRGB"] -> Right RgbSpace
          ["/DeviceCMYK"] -> Right CmykSpace
          _ -> Left "PDF 図版の色空間の変換は未完了です"
        let zero = case space of
              GraySpace -> Gray 0
              RgbSpace -> Rgb 0 0 0
              CmykSpace -> CmykColor 0 0 0 1
            state = if isStroke then graphics {strokeSpace = space, strokeColor = zero} else graphics {fillSpace = space, fillColor = zero}
        keep state stack kind (paint swatch zero isStroke)
  case operator of
    "Do" | Just used <- external -> keep graphics stack (mergeKind kind used) original
    "q" -> keep graphics (graphics : stack) kind original
    "Q" -> case stack of
      saved : rest -> keep saved rest kind original
      [] -> Left "PDF 図版の描画状態の復元先がありません"
    "g" -> colorOp False GraySpace
    "G" -> colorOp True GraySpace
    "rg" -> colorOp False RgbSpace
    "RG" -> colorOp True RgbSpace
    "k" -> colorOp False CmykSpace
    "K" -> colorOp True CmykSpace
    "cs" -> spaceOp False
    "CS" -> spaceOp True
    "sc" -> colorOp False (fillSpace graphics)
    "scn" -> colorOp False (fillSpace graphics)
    "SC" -> colorOp True (strokeSpace graphics)
    "SCN" -> colorOp True (strokeSpace graphics)
    "Tr" -> case args of
      [value] | Just n <- int value, n >= 0 && n <= 7 -> keep graphics {textMode = fromInteger n} stack kind original
      _ -> Left "PDF 図版のテキスト描画モードが不正です"
    _
      | operator `elem` ["f", "F", "f*"] -> painted [fillColor graphics | fillAlpha graphics > 0]
      | operator `elem` ["S", "s"] -> painted [strokeColor graphics | strokeAlpha graphics > 0]
      | operator `elem` ["B", "B*", "b", "b*"] -> painted ([fillColor graphics | fillAlpha graphics > 0] <> [strokeColor graphics | strokeAlpha graphics > 0])
      | operator `elem` ["Tj", "TJ", "'", "\""] -> painted ([fillColor graphics | textMode graphics `elem` [0, 2, 4, 6], fillAlpha graphics > 0] <> [strokeColor graphics | textMode graphics `elem` [1, 2, 5, 6], strokeAlpha graphics > 0])
      | operator `elem` ["Do", "sh", "BI"] -> Left "PDF 図版の画像・Form・シェーディングの色変換は未完了です"
      | otherwise -> same

parseColor :: Space -> [ByteString] -> Either Text Color
parseColor space args = do
  values <- maybe (Left "PDF 図版の色の成分を読めません") Right (traverse decimal args)
  let clipped = map (max 0 . min 1) values
  case (space, clipped) of
    (GraySpace, [g]) -> Right (Gray g)
    (RgbSpace, [r, g, b]) -> Right (Rgb r g b)
    (CmykSpace, [c, m, y, k]) -> Right (CmykColor c m y k)
    _ -> Left "PDF 図版の色の成分数が不正です"

-- PDF decimal syntax, without floating-point equality in grey detection.
decimal :: ByteString -> Maybe Rational
decimal bytes =
  let (sign, body) = case BC.uncons bytes of
        Just ('-', rest) -> (-1, rest)
        Just ('+', rest) -> (1, rest)
        _ -> (1, bytes)
      (whole, fraction) = BC.break (== '.') body
   in if BS.null fraction
        then fromInteger . (sign *) <$> int whole
        else do
          let tailDigits = BS.drop 1 fraction
          if BS.null whole && BS.null tailDigits || not (BC.all isDigit whole && BC.all isDigit tailDigits)
            then Nothing
            else do
              a <- if BS.null whole then Just 0 else int whole
              b <- if BS.null tailDigits then Just 0 else int tailDigits
              let scale = 10 ^ BS.length tailDigits
              pure (sign * (a * scale + b) % scale)

int :: ByteString -> Maybe Integer
int bytes = case BC.readInteger bytes of
  Just (n, rest) | BS.null rest -> Just n
  _ -> Nothing

colorKind :: Color -> RasterKind
colorKind = \case
  Gray _ -> Grayscale
  Rgb r g b | r == g && g == b -> Grayscale
  Rgb r g b -> SolidRgb (r, g, b)
  CmykColor c m y _ | c == m && m == y -> Grayscale
  CmykColor c m y k -> SolidCmyk (c, m, y, k)

mergeKind :: RasterKind -> RasterKind -> RasterKind
mergeKind Unpainted next = next
mergeKind previous Unpainted = previous
mergeKind previous next | previous == next = previous
mergeKind _ _ = Multicolor

paint :: Cmyk -> Color -> Bool -> ByteString
paint (c, m, y, k) source isStroke =
  let amount = case source of
        Gray g -> 1 - g
        Rgb r g b | r == g && g == b -> 1 - g
        CmykColor a b d e | a == b && b == d -> 1 - (1 - a) * (1 - e)
        _ -> 1
      values = [fromIntegral component / 100 * amount | component <- [c, m, y, k]]
   in BC.unwords (map (TE.encodeUtf8 . P.showRationalDigits 8) values <> [if isStroke then "K" else "k"])
