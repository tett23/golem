{-# LANGUAGE MultiWayIf #-}

-- | Process-colour conversion of imported figures (root ADR 0403).
module Golem.Typeset.PdfColor (recolorImportedPage) where

import Control.Applicative ((<|>))
import Control.Monad (foldM)
import Data.Bits (shiftL, shiftR, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (isDigit)
import Data.List (transpose)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Ratio (denominator, numerator, (%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P
import Golem.Typeset.FigureColor (Cmyk, RasterAnalysis (..), RasterKind (..))
import Golem.Typeset.PdfDct (DctSamples (..), PdfDctSpec (..), decodePdfDct)
import Golem.Typeset.PdfShading qualified as S

-- A colour is kept in the source space until an operator actually paints it.
-- A CIE-based colour (root ADR 0425) keeps its space's identity, its
-- clipped components, and its gray value when it is neutral.
data Color = Gray !Rational | Rgb !Rational !Rational !Rational | CmykColor !Rational !Rational !Rational !Rational | Cie !Text ![Rational] !(Maybe Rational)
  deriving stock (Eq, Ord, Show)

-- An Indexed space keeps its palette as colours of its base space.
-- An ICCBased space of Gray, RGB or CMYK data maps its Range to 0 to 1 and
-- is then a device space; a CIE-based space clips to its ranges (root ADR 0425).
data Space = GraySpace | RgbSpace | CmykSpace | IndexedSpace ![Color] | RangedSpace !Space ![(Rational, Rational)] | CieSpace !CieFamily !Text ![(Rational, Rational)]
  deriving stock (Eq, Ord, Show)

data CieFamily = CalGrayFamily | CalRgbFamily | LabFamily
  deriving stock (Eq, Ord, Show)

data Graphics = Graphics
  { fillColor :: !Color,
    strokeColor :: !Color,
    fillSpace :: !Space,
    strokeSpace :: !Space,
    textMode :: !Int,
    fillAlpha :: !Rational,
    strokeAlpha :: !Rational,
    -- Overprint for stroking (OP) and for other painting (op), and OPM.
    overprintStroke :: !Bool,
    overprintFill :: !Bool,
    overprintMode :: !Int
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
      initialState = Resources {sourceObjects = source, decodedStreams = Map.empty, formSummaries = Map.empty, convertedForms = Map.empty, convertedObjects = Map.empty, scopeBindings = Map.empty, sourceTables = Map.empty, shadingBindings = Map.empty, shadingTables = Map.empty, unreplaceableShading = False, clonedResources = Map.empty, rasterAnalyzer = analyze, rasterResults = Map.empty, convertedImages = Map.empty, inlineSources = Map.empty, remainingBytes = P.maxDecodedBytes - P.ipDecodedBytes page}
  scope <- resourceScope PageResources (P.ipResources page) initialState
  (Scan _ _ kind _ _, analyzed) <- scanForms swatch False Set.empty scope (P.ipResources page) initial (P.ipContent page) initialState
  if kind == Grayscale && unreplaceableShading analyzed then Left "PDF 図版の濃淡のシェーディングを指定色に置き換えられません" else Right ()
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
    initial = Graphics (Gray 0) (Gray 0) GraySpace GraySpace 0 1 1 False False 0

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
    -- Converted shadings get aliases in the Shading resources, like XObjects.
    shadingBindings :: !(Map.Map Scope (Map.Map Text P.ObjNum)),
    shadingTables :: !(Map.Map Scope (Map.Map Text (P.ObjOf P.ObjNum))),
    -- A gray shading met that cannot be recoloured (root ADR 0425).
    unreplaceableShading :: !Bool,
    clonedResources :: !(Map.Map Scope P.ObjNum),
    rasterAnalyzer :: !(P.ImageData -> Either Text RasterAnalysis),
    rasterResults :: !(Map.Map (P.ObjNum, Scope) RasterAnalysis),
    convertedImages :: !(Map.Map (P.ObjNum, Scope) P.ObjNum),
    -- An inline image is read as an image XObject numbered like a clone.
    inlineSources :: !(Map.Map ByteString P.ObjNum),
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
    go (Scan before saved seen output _) st0 (operation@(operator, args) : rest) = do
      (current, space, st) <- prepareOperation resources before operation st0
      let scanImage imageScope imageResources key fields prepared
            | fillAlpha current == 0 = Right (Just Unpainted, prepared)
            | overprintMode current /= 0 && overprintFill current = Left overprintError
            | otherwise = do
                (kind, decoded) <- pdfImageKind (fillColor current) imageScope imageResources key fields prepared
                Right (Just kind, decoded)
      (external, updated) <- case operator of
        "Do" -> do
          (key, fields, childResources, childScope, prepared) <- xObjectResource resources scope args st
          if lookup "Subtype" fields == Just (P.OName "Image")
            then scanImage childScope childResources key fields prepared
            else do
              let cacheKey = (key, childScope, current)
              case Map.lookup cacheKey (formSummaries prepared) of
                Just kind -> Right (Just kind, prepared)
                Nothing -> do
                  guardForm active key
                  (body, decoded) <- decodePdfStream key fields prepared
                  (Scan _ _ kind _ _, child) <- scanForms swatch False (Set.insert key active) childScope childResources current body decoded
                  Right (Just kind, child {formSummaries = Map.insert cacheKey kind (formSummaries child)})
        "BI" -> do
          (key, fields, prepared) <- inlineSource args st
          scanImage scope resources key fields prepared
        "sh" -> do
          (value, tabled) <- shadingResource scope resources args st
          (shading, analyzed) <- analyzeShading value tabled
          if
            | fillAlpha current == 0 -> Right (Just Unpainted, analyzed)
            | overprintMode current /= 0 && overprintFill current -> Left overprintError
            | otherwise -> Right (Just (shadingKind shading), analyzed {unreplaceableShading = unreplaceableShading analyzed || shadingBlocked shading})
        _ -> Right (Nothing, st)
      let synced = Scan current saved seen output (if emit then Just (remainingBytes updated) else Nothing)
      next@(Scan _ _ _ _ budget) <- stepWith external space swatch synced operation
      go next (case budget of Nothing -> updated; Just remaining -> updated {remainingBytes = remaining}) rest

renderForms :: Cmyk -> Set.Set P.ObjNum -> Scope -> P.ObjOf P.ObjNum -> Graphics -> ByteString -> Resources -> Either Text (ByteString, P.ObjOf P.ObjNum, Resources)
renderForms swatch active scope resources graphics content state = do
  operations <- maybe (Left "PDF 図版の描画命令を読めません") Right (P.contentOperations content)
  go (Scan graphics [] Unpainted [] (Just (remainingBytes state))) resources state operations
  where
    go (Scan _ saved _ output _) bound st []
      | null saved = Right (BC.unlines (reverse output), bound, st)
      | otherwise = Left "PDF 図版の描画状態が閉じていません"
    go (Scan before saved seen output _) bound st0 (operation@(operator, args) : rest) = do
      (current, space, st) <- prepareOperation resources before operation st0
      let renderImage imageScope imageResources key fields prepared
            | fillAlpha current == 0 = Right (key, prepared)
            | otherwise = do
                stencil <- isStencil fields prepared
                if stencil then Right (key, prepared) else convertPdfImage imageScope imageResources key fields prepared
          bindClone clone child = do
            alias <- freshAlias scope clone child
            let bindings = Map.insertWith Map.union scope (Map.singleton alias clone) (scopeBindings child)
            Right (Just Unpainted, bound, child {scopeBindings = bindings}, ("Do", ["/" <> TE.encodeUtf8 alias]))
      (external, rebound, updated, rewritten) <- case operator of
        "Do" -> do
          (key, fields, childResources, childScope, prepared) <- xObjectResource resources scope args st
          (clone, child) <-
            if lookup "Subtype" fields == Just (P.OName "Image")
              then renderImage childScope childResources key fields prepared
              else case Map.lookup (key, childScope) (convertedForms prepared) of
                Just converted -> Right (converted, prepared)
                Nothing -> do
                  guardForm active key
                  (body, decoded) <- decodePdfStream key fields prepared
                  (painted, _, rendered) <- renderForms swatch (Set.insert key active) childScope childResources current body decoded
                  fresh <- freshObject rendered
                  grouped <- cmykGroup fields rendered
                  let fieldsOut = [(k, v) | (k, v) <- grouped, k `notElem` ["Length", "Filter", "DecodeParms", "DL"]]
                  Right (fresh, rendered {convertedForms = Map.insert (key, childScope) fresh (convertedForms rendered), convertedObjects = Map.insert fresh (P.OStream fieldsOut painted) (convertedObjects rendered)})
          bindClone clone child
        "BI" -> do
          (_, tabled) <- sourceTable scope resources st
          (key, fields, prepared) <- inlineSource args tabled
          (clone, child) <- renderImage scope resources key fields prepared
          -- An unconverted inline image is written as the XObject it was read as.
          let kept = if clone == key then child {convertedObjects = Map.insert key (P.OStream fields (inlineData key child)) (convertedObjects child)} else child
          bindClone clone kept
        "sh" -> do
          (value, tabled) <- shadingResource scope resources args st
          (shading, analyzed) <- analyzeShading value tabled
          (object, materialized) <- materialize (convertShading swatch shading) analyzed
          fresh <- freshObject materialized
          alias <- freshShadingAlias scope fresh materialized
          let bindings = Map.insertWith Map.union scope (Map.singleton alias fresh) (shadingBindings materialized)
          Right (Just Unpainted, bound, materialized {convertedObjects = Map.insert fresh object (convertedObjects materialized), shadingBindings = bindings}, ("sh", ["/" <> TE.encodeUtf8 alias]))
        _ -> Right (Nothing, bound, st, operation)
      next@(Scan _ _ _ _ budget) <- stepWith external space swatch (Scan current saved seen output (Just (remainingBytes updated))) rewritten
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
  -- Normal compositing is affine in each colour, so recoloring each object
  -- equals recoloring the composite. Other blend modes and transfer
  -- functions are not, and are not recolored per object.
  mapM_ (\key -> traverse (named key ["Normal", "Compatible"]) (lookup key selected)) ["BM"]
  mapM_ (\key -> traverse (named key ["Identity", "Default"]) (lookup key selected)) ["TR", "TR2"]
  -- OP sets both overprints unless op is in the same dictionary (root ADR 0425).
  strokeOverprint <- flag "OP" selected
  fillOverprint <- flag "op" selected
  mode <- traverse (\value -> dereference Set.empty value state >>= \case P.OInt n | n == 0 || n == 1 -> Right (fromInteger n); _ -> Left overprintInvalid) (lookup "OPM" selected)
  Right
    current
      { fillAlpha = fill,
        strokeAlpha = stroke,
        overprintStroke = fromMaybe (overprintStroke current) strokeOverprint,
        overprintFill = fromMaybe (fromMaybe (overprintFill current) strokeOverprint) fillOverprint,
        overprintMode = fromMaybe (overprintMode current) mode
      }
  where
    overprintInvalid = "PDF 図版のオーバープリントの指定が不正です"
    flag name fields = traverse (\value -> dereference Set.empty value state >>= \case P.OBool b -> Right b; _ -> Left overprintInvalid) (lookup name fields)
    named key allowed value = do
      resolved <- dereference Set.empty value state
      let ok = \case
            P.OName n -> n `elem` allowed
            P.OArr values -> not (null values) && all ok values
            _ -> False
      if ok resolved then Right () else Left ("PDF 図版の " <> key <> " を保って色を置き換えられません")
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

{- | The graphics state, the colour space a @cs@ or @CS@ selects, and the
checked fonts, before an operation is painted.
-}
prepareOperation :: P.ObjOf P.ObjNum -> Graphics -> (ByteString, [ByteString]) -> Resources -> Either Text (Graphics, Maybe Space, Resources)
prepareOperation resources before operation state = do
  current <- externalGraphics resources before operation state
  checked <- type3Colours resources operation state
  (space, spaced) <- operationSpace resources operation checked
  Right (current, space, spaced)

-- A Type 3 glyph declared with d0 paints its own colours, which are neither
-- classified nor recolored with the text's fill.
type3Colours :: P.ObjOf P.ObjNum -> (ByteString, [ByteString]) -> Resources -> Either Text Resources
type3Colours resources ("Tf", [name, _]) state = do
  font <- resourceName [name]
  entries <- dictionary resources state
  fonts <- maybe (Right []) (`dictionary` state) (lookup "Font" entries)
  case lookup font fonts of
    Nothing -> Right state
    Just value -> do
      fields <- dictionary value state
      if lookup "Subtype" fields /= Just (P.OName "Type3")
        then Right state
        else do
          procs <- maybe (Right []) (`dictionary` state) (lookup "CharProcs" fields)
          foldM glyph state (map snd procs)
  where
    glyph st reference = do
      (key, entries) <- pdfStreamReference "PDF 図版の Type 3 フォントの字形がありません" st Set.empty reference
      (body, decoded) <- decodePdfStream key entries st
      operations <- maybe (Left "PDF 図版の Type 3 フォントの字形を読めません") Right (P.contentOperations body)
      if any ((== "d0") . fst) operations then Left "PDF 図版の Type 3 フォントの色を置き換えられません" else Right decoded
type3Colours _ _ state = Right state

-- Named colour spaces resolve through the resources like those of images.
operationSpace :: P.ObjOf P.ObjNum -> (ByteString, [ByteString]) -> Resources -> Either Text (Maybe Space, Resources)
operationSpace resources (operator, args) state
  | operator `notElem` ["cs", "CS"] = Right (Nothing, state)
  | otherwise = do
      name <- resourceName args
      case name of
        "DeviceGray" -> Right (Just GraySpace, state)
        "DeviceRGB" -> Right (Just RgbSpace, state)
        "DeviceCMYK" -> Right (Just CmykSpace, state)
        "Pattern" -> Left "PDF 図版のパターンの色置換は未完了です"
        _ -> do
          entries <- dictionary resources state
          spaces <- maybe (Right []) (`dictionary` state) (lookup "ColorSpace" entries)
          case lookup name spaces of
            Nothing | name == "GolemSRGB" -> Right (Just RgbSpace, state)
            Nothing -> Left "PDF 図版の色空間が見つかりません"
            Just value -> do
              special <- cieSpace value state
              case special of
                Just (space, resolved) -> Right (Just space, resolved)
                Nothing -> deviceSpace value
  where
    deviceSpace value = do
      (space, components, _, palette, resolved) <- pdfImageSpace resources [("ColorSpace", value)] state
      let device = case space of
            P.CsGray -> GraySpace
            P.CsCmyk -> CmykSpace
            _ -> RgbSpace
          colour bytes = case map (\w -> fromIntegral w % 255) (BS.unpack bytes) of
            [g] -> Gray g
            [r, g, b] -> Rgb r g b
            [c, m, y, k] -> CmykColor c m y k
            _ -> Gray 0
      Right (Just (maybe device (\(count, table) -> IndexedSpace [colour (BS.take components (BS.drop (i * components) table)) | i <- [0 .. count]]) palette), resolved)

isStencil :: [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text Bool
isStencil fields state = case lookup "ImageMask" fields of
  Nothing -> Right False
  Just value -> do
    resolved <- dereference Set.empty value state
    case resolved of
      P.OBool flag -> Right flag
      _ -> Left "PDF 図版の ImageMask が不正です"

-- A stencil mask paints the fill colour, which the content already recolors.
-- A CCITT image is one-bit gray, so it is a tone without being decoded.
pdfImageKind :: Color -> Scope -> P.ObjOf P.ObjNum -> P.ObjNum -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (RasterKind, Resources)
pdfImageKind fill scope resources key fields state = do
  stencil <- isStencil fields state
  ccitt <- isCcitt fields state
  if
    | stencil -> Right (colorKind fill, state)
    | ccitt -> do
        (_, checked) <- ccittDecode resources fields state
        Right (Grayscale, checked)
    | otherwise -> do
        (analysis, decoded) <- analyzePdfImage scope resources key fields state
        Right (raKind analysis, decoded)

imageFilters :: [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text [P.ObjOf P.ObjNum]
imageFilters fields state = case lookup "Filter" fields of
  Nothing -> Right []
  Just value -> do
    resolved <- dereference Set.empty value state
    case resolved of
      P.OArr values -> traverse (\entry -> dereference Set.empty entry state) values
      P.ONull -> Right []
      other -> Right [other]

isCcitt :: [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text Bool
isCcitt fields state = (\filters -> take 1 (reverse filters) == [P.OName "CCITTFaxDecode"]) <$> imageFilters fields state

-- Whether a CCITT image reverses its samples. Only one-bit gray samples
-- without masks are recolored without decoding them.
ccittDecode :: P.ObjOf P.ObjNum -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (Bool, Resources)
ccittDecode resources fields state = do
  bits <- maybe (Right (P.OInt 1)) (\value -> dereference Set.empty value state) (lookup "BitsPerComponent" fields)
  (space, _, _, palette, resolved) <- pdfImageSpace resources fields state
  let unmasked = all (\name -> maybe True (`elem` [P.ONull, P.OName "None"]) (lookup name fields)) ["SMask", "Mask"]
  if bits == P.OInt 1 && space == P.CsGray && isNothing palette && unmasked then Right () else Left "PDF 図版の CCITT 画像の色置換は未完了です"
  ranges <- unitDecode 1 fields resolved
  case ranges of
    [False, True] -> Right (False, resolved)
    [True, False] -> Right (True, resolved)
    _ -> Left "PDF 図版の画像の Decode に対応していません"

-- The source of an inline image, numbered once per distinct segment.
inlineSource :: [ByteString] -> Resources -> Either Text (P.ObjNum, [(Text, P.ObjOf P.ObjNum)], Resources)
inlineSource [segment] state = case Map.lookup segment (inlineSources state) of
  Just key | Just (P.OStream fields _) <- Map.lookup key (sourceObjects state) -> Right (key, fields, state)
  _ -> do
    (entries, bytes) <- maybe (Left "PDF 図版のインライン画像を読めません") Right (P.inlineImageParts segment)
    fresh <- freshObject state
    let fields = [("Type", P.OName "XObject"), ("Subtype", P.OName "Image")] <> [entry | entry@(name, _) <- entries, name `notElem` ["Type", "Subtype", "Length"]]
    Right (fresh, fields, state {sourceObjects = Map.insert fresh (P.OStream fields bytes) (sourceObjects state), inlineSources = Map.insert segment fresh (inlineSources state)})
inlineSource _ _ = Left "PDF 図版のインライン画像を読めません"

inlineData :: P.ObjNum -> Resources -> ByteString
inlineData key state = case Map.lookup key (sourceObjects state) of
  Just (P.OStream _ bytes) -> bytes
  _ -> BS.empty

-- Converted content is CMYK, so a transparency group blends in DeviceCMYK;
-- with Normal compositing that equals recoloring the blended gray.
cmykGroup :: [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text [(Text, P.ObjOf P.ObjNum)]
cmykGroup fields state = case lookup "Group" fields of
  Nothing -> Right fields
  Just value -> do
    group <- dictionary value state
    let replaced = if isJust (lookup "CS" group) then [(k, if k == "CS" then P.OName "DeviceCMYK" else v) | (k, v) <- group] else group
    Right [(k, if k == "Group" then P.ODict replaced else v) | (k, v) <- fields]

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
    (space, components, profile, palette, colored) <- pdfImageSpace resources fields state
    let sampleComponents = maybe components (const 1) palette
    if bits `notElem` (if isJust palette then [1, 2, 4, 8] else [1, 2, 4, 8, 16]) then Left "PDF 図版の画像のビット深度に対応していません" else Right ()
    if any unsupportedMask fields then Left "PDF 図版の画像マスクを保って色を置き換えられません" else Right ()
    written <- decodeRanges sampleComponents fields colored
    let maximum' = 2 ^ bits - 1
        defaults = if isJust palette then [(0, fromInteger maximum')] else replicate sampleComponents (0, 1)
        ranges = fromMaybe defaults written
        reversed = isNothing palette && ranges == replicate sampleComponents (1, 0)
        expanded = isJust palette || (ranges /= defaults && not reversed)
        expandedBits = if bits == 16 then 16 else 8
    let pixels = width * height
        inputBytes = ((width * toInteger sampleComponents * bits + 7) `div` 8) * height
        expandedBytes = if expanded then pixels * toInteger components * (expandedBits `div` 8) else 0
        minimumOutputBytes = pixels * 4 * (if bits == 16 then 2 else 1)
    if inputBytes + expandedBytes + minimumOutputBytes > toInteger (remainingBytes colored) || width > toInteger (maxBound :: Int) || height > toInteger (maxBound :: Int)
      then Left budgetError
      else Right ()
    (bytes, decoded) <- decodePdfImageStream key width height bits sampleComponents fields colored
    if toInteger (BS.length bytes) /= inputBytes then Left "PDF 図版の画像の寸法とデータ長が一致しません" else Right ()
    (samples, sampled) <-
      if
        | expanded -> do
            reservedExpansion <- charge (fromInteger expandedBytes) decoded
            Right (expandSamples (fromInteger width) (fromInteger height) (fromInteger bits) sampleComponents ranges palette components bytes, reservedExpansion)
        | reversed -> do
            inverted <- charge (BS.length bytes) decoded
            Right (BS.map (255 -) bytes, inverted)
        | otherwise -> Right (bytes, decoded)
    (alpha, masked) <- pdfImageAlpha width height bits sampleComponents bytes fields sampled
    let outputBits = if bits == 16 || maybe False ((== 16) . P.alphaBits) alpha then 16 else 8
        outputBytes = pixels * 4 * (outputBits `div` 8)
        sampleBits = fromInteger (if expanded then expandedBits else bits)
    reserved <- charge (fromInteger outputBytes) masked
    let input = P.ImageData (fromInteger width) (fromInteger height) sampleBits space profile samples False False alpha
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

-- Decode the lossless filter prefix first, then DCT into native device samples.
-- The common stream cache holds the final samples, never a second JPEG decode.
decodePdfImageStream :: P.ObjNum -> Integer -> Integer -> Integer -> Int -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (ByteString, Resources)
decodePdfImageStream key width height bits components fields state = case Map.lookup key (decodedStreams state) of
  Just samples -> Right (samples, state)
  Nothing -> do
    filters <- imageFilters fields state
    case reverse filters of
      P.OName "RunLengthDecode" : reversedPrefix -> do
        let prefix = reverse reversedPrefix
        prefixParameters <- case lookup "DecodeParms" fields of
          Nothing -> Right []
          Just value -> do
            resolved <- dereference Set.empty value state
            case resolved of
              P.OArr values | length values == length filters -> Right (take (length prefix) values)
              P.ONull -> Right []
              _ | null prefix -> Right []
              _ -> Left invalid
        let plainFields = filter (\(name, _) -> name `notElem` ["Filter", "DecodeParms"]) fields
            prefixFields = if null prefix then plainFields else ("Filter", P.OArr prefix) : [("DecodeParms", P.OArr prefixParameters) | not (null prefixParameters)] <> plainFields
        (encoded, decoded) <- decodePdfStream key prefixFields state
        bytes <- runLength (remainingBytes decoded) encoded
        charged <- charge (BS.length bytes) decoded
        Right (bytes, charged {decodedStreams = Map.insert key bytes (decodedStreams charged)})
      P.OName "DCTDecode" : reversedPrefix -> do
        if bits == 8 then Right () else Left invalid
        parameters <- case lookup "DecodeParms" fields of
          Nothing -> Right (replicate (length filters) P.ONull)
          Just value -> do
            resolved <- dereference Set.empty value state
            case resolved of
              P.ONull -> Right (replicate (length filters) P.ONull)
              P.OArr values | length values == length filters -> Right values
              P.ODict _ | length filters == 1 -> Right [resolved]
              _ -> Left invalid
        (prefixParameters, jpegParameters) <- case reverse parameters of
          value : rest -> Right (reverse rest, value)
          [] -> Left invalid
        resolved <- dereference Set.empty jpegParameters state
        jpegFields <- case resolved of P.ONull -> Right []; P.ODict entries -> Right entries; _ -> Left invalid
        transform <- case lookup "ColorTransform" jpegFields of
          Nothing -> Right Nothing
          Just value -> do
            resolvedTransform <- dereference Set.empty value state
            case resolvedTransform of
              P.OInt n | n >= toInteger (minBound :: Int), n <= toInteger (maxBound :: Int) -> Right (Just (fromInteger n))
              _ -> Left invalid
        let prefix = reverse reversedPrefix
            plainFields = filter (\(name, _) -> name `notElem` ["Filter", "DecodeParms"]) fields
            prefixFields = if null prefix then plainFields else ("Filter", P.OArr prefix) : ("DecodeParms", P.OArr prefixParameters) : plainFields
        (encoded, decoded) <- decodePdfStream key prefixFields state
        samples <- decodePdfDct (PdfDctSpec components transform (fromInteger width) (fromInteger height) (remainingBytes decoded)) encoded
        charged <- charge (dctDecodedBytes samples) decoded
        let bytes = P.imgData (dctImage samples)
        Right (bytes, charged {decodedStreams = Map.insert key bytes (decodedStreams charged)})
      _ -> decodePdfStream key fields state
  where
    invalid = "PDF 図版の JPEG フィルターの指定が不正です"

-- RunLengthDecode (ISO 32000-1:2008 7.4.5), bounded by the remaining budget.
runLength :: Int -> ByteString -> Either Text ByteString
runLength limit = go [] 0
  where
    go acc size input = case BS.uncons input of
      Nothing -> Right (BS.concat (reverse acc))
      Just (128, _) -> Right (BS.concat (reverse acc))
      Just (count, rest)
        | count < 128 ->
            let run = fromIntegral count + 1
                chunk = BS.take run rest
             in if BS.length chunk < run then Left broken else step acc size chunk (BS.drop run rest)
        | otherwise -> case BS.uncons rest of
            Just (byte, rest') -> step acc size (BS.replicate (257 - fromIntegral count) byte) rest'
            Nothing -> Left broken
    step acc size chunk rest
      | size + BS.length chunk > limit = Left budgetError
      | otherwise = go (chunk : acc) (size + BS.length chunk) rest
    broken = "PDF 図版の RunLength のストリームが壊れています"

-- ICC profile streams share the same bounded decoder and cache as image data.
-- Range affects the default image Decode; non-unit ranges must not silently
-- be interpreted as ordinary device samples.
-- An Indexed space gives its base space with the highest index and the table.
pdfImageSpace :: P.ObjOf P.ObjNum -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (P.ColorSpace, Int, Maybe BS.ByteString, Maybe (Int, ByteString), Resources)
pdfImageSpace resources fields state = do
  value <- maybe (Left invalid) Right (lookup "ColorSpace" fields)
  resolved <- dereference Set.empty value state
  case resolved of
    P.OArr [P.OName "Indexed", base, high, table] -> do
      (space, components, profile, based) <- resolve Set.empty True base
      count <- dereference Set.empty high based
      highest <- case count of
        P.OInt n | n >= 0 && n <= 255 -> Right (fromInteger n)
        _ -> Left invalid
      (bytes, read') <- lookupTable table based
      if BS.length bytes < (highest + 1) * components then Left invalid else Right ()
      Right (space, components, profile, Just (highest, BS.take ((highest + 1) * components) bytes), read')
    _ -> do
      (space, components, profile, decoded) <- resolve Set.empty True value
      Right (space, components, profile, Nothing, decoded)
  where
    invalid = "PDF 図版の画像の色空間に対応していません"
    lookupTable table st = do
      resolvedTable <- dereference Set.empty table st
      case (table, resolvedTable) of
        (_, P.OStr bytes) -> Right (bytes, st)
        (_, P.OHex bytes) -> Right (bytes, st)
        (P.ORef _, P.OStream _ _) -> do
          (key, entries) <- pdfStreamReference invalid st Set.empty table
          decodePdfStream key entries st
        _ -> Left invalid
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
          -- The profile's data colour space must agree with N (root ADR 0425).
          if lookup (iccDataSpace profile) [("GRAY", 1), ("RGB ", 3), ("CMYK", 4)] == Just components then Right () else Left invalid
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

-- A Decode array as exact decimals. Long numbers are refused rather than
-- read as huge rationals; twelve fractional digits exceed 16-bit samples.
decodeRanges :: Int -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (Maybe [(Rational, Rational)])
decodeRanges components fields state = case lookup "Decode" fields of
  Nothing -> Right Nothing
  Just value -> do
    resolved <- dereference Set.empty value state
    values <- case resolved of
      P.OArr entries | length entries == 2 * components -> traverse number entries
      _ -> Left invalid
    Right (Just (pairs values))
  where
    invalid = "PDF 図版の画像の Decode を解釈できません"
    pairs (low : high : rest) = (low, high) : pairs rest
    pairs _ = []
    number value = do
      resolved <- dereference Set.empty value state
      case resolved of
        P.OInt n | abs n <= 10 ^ (12 :: Int) -> Right (fromInteger n)
        P.OReal text
          | let (whole, fraction) = BC.break (== '.') (TE.encodeUtf8 text),
            BS.length whole <= 13,
            Just parsed <- decimal (whole <> BS.take 13 fraction) ->
              Right parsed
        _ -> Left invalid

-- Samples mapped through Decode (and an Indexed table) to 8-bit, or 16-bit
-- for 16-bit sources, without row padding. Indexes round to the nearest
-- integer and are clipped to the table (ISO 32000-1:2008 8.6.6.3, 8.9.5.2).
expandSamples :: Int -> Int -> Int -> Int -> [(Rational, Rational)] -> Maybe (Int, ByteString) -> Int -> ByteString -> ByteString
expandSamples width height bits sampleComponents ranges palette components raw =
  BS.concat [slice channel (rawSample pixel channel) | pixel <- [0 .. width * height - 1], channel <- [0 .. sampleComponents - 1]]
  where
    maximum' = 2 ^ bits - 1 :: Int
    rowBytes = (width * sampleComponents * bits + 7) `div` 8
    entryBytes = case palette of
      Just _ -> components
      Nothing -> if bits == 16 then 2 else 1
    nearest :: Rational -> Integer
    nearest value = floor (value + 1 / 2)
    mapped (low, high) sample = low + fromIntegral sample * (high - low) / fromIntegral maximum'
    entry range sample = case palette of
      Just (highest, table) ->
        let index = fromInteger (max 0 (min (toInteger highest) (nearest (mapped range sample))))
         in BS.take components (BS.drop (index * components) table)
      Nothing ->
        let clipped = max 0 (min 1 (mapped range sample))
         in if bits == 16
              then let v = nearest (clipped * 65535) in BS.pack [fromInteger (v `shiftR` 8), fromInteger (v .&. 255)]
              else BS.singleton (fromInteger (nearest (clipped * 255)))
    tables = [BS.concat [entry range sample | sample <- [0 .. maximum']] | range <- ranges]
    slice channel sample = BS.take entryBytes (BS.drop (sample * entryBytes) (tables !! channel))
    rawSample pixel channel =
      let sample = (pixel `mod` width) * sampleComponents + channel
          bit = sample * bits
          offset = (pixel `div` width) * rowBytes + bit `div` 8
       in if bits == 16
            then fromIntegral (BS.index raw offset) `shiftL` 8 + fromIntegral (BS.index raw (offset + 1))
            else (fromIntegral (BS.index raw offset) `shiftR` (8 - bits - bit `mod` 8)) .&. maximum'

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
  Nothing -> imageMaskAlpha width height imageBits components raw fields state
  Just P.ONull -> imageMaskAlpha width height imageBits components raw fields state
  Just (P.OName "None") -> imageMaskAlpha width height imageBits components raw fields state
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
    (bytes, decoded) <- decodePdfImageStream key width height bits 1 maskFields state
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

-- ISO 32000-1:2008 8.9.6.2-3: a one-bit stencil paints zero
-- samples with the default Decode. Keep the mask stream attached to the
-- converted image; only the visibility used by classification is decoded.
imageMaskAlpha :: Integer -> Integer -> Integer -> Int -> ByteString -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (Maybe P.Alpha, Resources)
imageMaskAlpha width height bits components raw fields state = case lookup "Mask" fields of
  Nothing -> Right (Nothing, state)
  Just reference -> do
    resolved <- dereference Set.empty reference state
    case resolved of
      P.OStream _ _ -> explicitMaskAlpha width height fields reference state
      _ -> colorKeyAlpha width height bits components raw fields state

explicitMaskAlpha :: Integer -> Integer -> [(Text, P.ObjOf P.ObjNum)] -> P.ObjOf P.ObjNum -> Resources -> Either Text (Maybe P.Alpha, Resources)
explicitMaskAlpha width height imageFields reference state = do
  (key, fields) <- pdfStreamReference invalid state Set.empty reference
  values <- traverse (\(name, fallback) -> maybe (Left invalid) (\value -> dereference Set.empty value state) (lookup name fields <|> fallback)) [("Subtype", Nothing), ("Width", Nothing), ("Height", Nothing), ("ImageMask", Nothing), ("BitsPerComponent", Just (P.OInt 1))]
  case values of
    [P.OName "Image", P.OInt w, P.OInt h, P.OBool True, P.OInt 1] | w == width, h == height -> Right ()
    _ -> Left invalid
  if any (\name -> isJust (lookup name fields)) ["ColorSpace", "Mask", "SMask", "Matte"] then Left invalid else Right ()
  -- Interpolation can expose samples whose mask-centre is transparent.
  -- Its visibility analysis remains separate work; do not erase such colours.
  noInterpolation imageFields
  noInterpolation fields
  let sampleBytes = ((width + 7) `div` 8) * height
  if sampleBytes > toInteger (remainingBytes state) then Left budgetError else Right ()
  ranges <- unitDecode 1 fields state
  (bytes, decoded) <- decodePdfImageStream key width height 1 1 fields state
  if toInteger (BS.length bytes) /= sampleBytes then Left invalid else Right ()
  case ranges of
    [False, True] -> do
      reserved <- charge (BS.length bytes) decoded
      Right (Just (P.Alpha 1 (BS.map (255 -) bytes)), reserved)
    [True, False] -> Right (Just (P.Alpha 1 bytes), decoded)
    _ -> Left invalid
  where
    invalid = "PDF 図版の明示マスクを保って色を置き換えられません"
    noInterpolation fields = case lookup "Interpolate" fields of
      Nothing -> Right ()
      Just value -> do
        resolved <- dereference Set.empty value state
        if resolved == P.OBool False then Right () else Left invalid

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
  | Just reference <- lookup "Mask" fields,
    Right (P.OStream _ _) <- dereference Set.empty reference state =
      Right (fields, state)
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
    ccitt <- isCcitt fields state
    if ccitt then convertCcitt else convertDecoded
  where
    -- The encoded samples stay; an Indexed CMYK table gives each of the two
    -- tones the colour the shared raster analyzer gives black and white.
    convertCcitt = do
      (reversed, checked) <- ccittDecode resources fields state
      analysis <- rasterAnalyzer checked (P.ImageData 2 1 8 P.CsGray Nothing (BS.pack [0, 255]) False False Nothing)
      tones <- case raImage analysis of
        Just image | P.imgColor image == P.CsCmyk, P.imgBits image == 8, BS.length (P.imgData image) == 8 -> Right (P.imgData image)
        _ -> Left "PDF 図版の画像の色置換結果が不正です"
      let table = if reversed then BS.drop 4 tones <> BS.take 4 tones else tones
          space = P.OArr [P.OName "Indexed", P.OName "DeviceCMYK", P.OInt 1, P.OHex table]
          fieldsOut = [(name, value) | (name, value) <- fields, name `notElem` ["Length", "Decode", "ColorSpace", "BitsPerComponent"]] <> [("ColorSpace", space), ("BitsPerComponent", P.OInt 1)]
      source <- case Map.lookup key (sourceObjects checked) of
        Just (P.OStream _ bytes) -> Right bytes
        _ -> Left "PDF 図版の画像のストリームがありません"
      fresh <- freshObject checked
      Right (fresh, checked {convertedImages = Map.insert (key, scope) fresh (convertedImages checked), convertedObjects = Map.insert fresh (P.OStream fieldsOut source) (convertedObjects checked)})
    convertDecoded = do
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
cloneResourceDictionaries state = foldM clone state (Set.toList (Set.fromList (Map.keys (scopeBindings state) <> Map.keys (shadingBindings state))))
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
bindScopeRaw scope resources state = case [(category, additions, tables) | (category, bindings, tables) <- [("XObject", scopeBindings state, sourceTables state), ("Shading", shadingBindings state, shadingTables state)], Just additions <- [Map.lookup scope bindings]] of
  [] -> Right resources
  categories -> do
    values <- dictionary resources state
    replaced <- traverse (\(category, additions, tables) -> (\originals -> (category, P.ODict (Map.toAscList (Map.union (Map.map P.ORef additions) originals)))) <$> maybe (Left "PDF 図版の資源辞書を準備できません") Right (Map.lookup scope tables)) categories
    Right (P.ODict ([(k, v) | (k, v) <- values, k `notElem` map fst replaced] <> replaced))

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

stepWith :: Maybe RasterKind -> Maybe Space -> Cmyk -> Scan -> (ByteString, [ByteString]) -> Either Text Scan
stepWith external resolved swatch (Scan graphics stack kind output budget) (operator, args) = do
  let keep state saved seen bytes = case budget of
        Nothing -> Right (Scan state saved seen [] Nothing)
        Just remaining
          | BS.length bytes >= remaining -> Left budgetError
          | otherwise -> Right (Scan state saved seen (bytes : output) (Just (remaining - BS.length bytes - 1)))
      original = BC.unwords (args <> [operator])
      same = keep graphics stack kind original
      painted fills strokes
        | overprintMode graphics /= 0 && (not (null fills) && overprintFill graphics || not (null strokes) && overprintStroke graphics) = Left overprintError
        | otherwise = keep graphics stack (foldl mergeKind kind (map colorKind (fills <> strokes))) original
      colorOp isStroke space = do
        color <- parseColor space args
        let state = if isStroke then graphics {strokeColor = color, strokeSpace = space} else graphics {fillColor = color, fillSpace = space}
        keep state stack kind (paint swatch color isStroke)
      spaceOp isStroke = do
        space <- maybe (Left "PDF 図版の色空間の変換は未完了です") Right resolved
        zero <- initialColor space
        let state = if isStroke then graphics {strokeSpace = space, strokeColor = zero} else graphics {fillSpace = space, fillColor = zero}
        keep state stack kind (paint swatch zero isStroke)
  case operator of
    _ | operator `elem` ["Do", "BI", "sh"], Just used <- external -> keep graphics stack (mergeKind kind used) original
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
      | operator `elem` ["f", "F", "f*"] -> painted [fillColor graphics | fillAlpha graphics > 0] []
      | operator `elem` ["S", "s"] -> painted [] [strokeColor graphics | strokeAlpha graphics > 0]
      | operator `elem` ["B", "B*", "b", "b*"] -> painted [fillColor graphics | fillAlpha graphics > 0] [strokeColor graphics | strokeAlpha graphics > 0]
      | operator `elem` ["Tj", "TJ", "'", "\""] -> painted [fillColor graphics | textMode graphics `elem` [0, 2, 4, 6], fillAlpha graphics > 0] [strokeColor graphics | textMode graphics `elem` [1, 2, 5, 6], strokeAlpha graphics > 0]
      | operator `elem` ["Do", "sh", "BI"] -> Left "PDF 図版の画像・Form・シェーディングの色変換は未完了です"
      | otherwise -> same

parseColor :: Space -> [ByteString] -> Either Text Color
parseColor (IndexedSpace palette) args = case args of
  [arg] | Just index <- decimal arg, denominator index == 1, index >= 0, index < fromIntegral (length palette) -> Right (palette !! fromInteger (numerator index))
  _ -> Left "PDF 図版の色の索引が不正です"
parseColor (RangedSpace base ranges) args = do
  values <- maybe (Left "PDF 図版の色の成分を読めません") Right (traverse decimal args)
  if length values == length ranges then rangedColor base ranges values else Left "PDF 図版の色の成分数が不正です"
parseColor (CieSpace family key ranges) args = do
  values <- maybe (Left "PDF 図版の色の成分を読めません") Right (traverse decimal args)
  if length values == length ranges then Right (cieColor family key ranges values) else Left "PDF 図版の色の成分数が不正です"
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

-- The initial colour of a space selected by cs or CS.
initialColor :: Space -> Either Text Color
initialColor = \case
  GraySpace -> Right (Gray 0)
  RgbSpace -> Right (Rgb 0 0 0)
  CmykSpace -> Right (CmykColor 0 0 0 1)
  IndexedSpace (first : _) -> Right first
  IndexedSpace [] -> Right (Gray 0)
  RangedSpace base ranges -> rangedColor base ranges (map (const 0) ranges)
  CieSpace family key ranges -> Right (cieColor family key ranges (map (const 0) ranges))

clip :: (Rational, Rational) -> Rational -> Rational
clip (low, high) = max low . min high

-- Range maps an ICCBased component to 0 to 1 before the device rules apply.
rangedColor :: Space -> [(Rational, Rational)] -> [Rational] -> Either Text Color
rangedColor base ranges values =
  let unit = [(clip range value - low) / (high - low) | (range@(low, high), value) <- zip ranges values]
   in case (base, unit) of
        (GraySpace, [g]) -> Right (Gray g)
        (RgbSpace, [r, g, b]) -> Right (Rgb r g b)
        (CmykSpace, [c, m, y, k]) -> Right (CmykColor c m y k)
        _ -> Left "PDF 図版の色の成分数が不正です"

-- CIE-based colours are classified by their clipped values without
-- conversion; equal values in one space are one colour (root ADR 0425).
cieColor :: CieFamily -> Text -> [(Rational, Rational)] -> [Rational] -> Color
cieColor family key ranges values =
  let clipped = zipWith clip ranges values
      neutral = case (family, clipped) of
        (CalGrayFamily, [g]) -> Just g
        (CalRgbFamily, [r, g, b]) | r == g && g == b -> Just r
        -- An ICCBased Lab Range may exceed 0 to 100; L* stays within it.
        (LabFamily, [l, 0, 0]) -> Just (clip (0, 100) l / 100)
        _ -> Nothing
   in Cie key clipped neutral

overprintError :: Text
overprintError = "PDF 図版の OPM 1 のオーバープリントを保って色を置き換えられません"

iccDataSpace :: ByteString -> ByteString
iccDataSpace = BS.take 4 . BS.drop 16

-- The CIE-based spaces and the ICCBased spaces classified by the data colour
-- space of their profiles (root ADR 0425); Nothing for any other space.
cieSpace :: P.ObjOf P.ObjNum -> Resources -> Either Text (Maybe (Space, Resources))
cieSpace value state = do
  resolved <- dereference Set.empty value state
  case resolved of
    P.OArr [P.OName family, dictionaryValue]
      | Just kind <- lookup family [("CalGray", CalGrayFamily), ("CalRGB", CalRgbFamily), ("Lab", LabFamily)] -> do
          fields <- dictionary dictionaryValue state
          deepFields <- traverse (\(name, entry) -> (name,) <$> resolveDeep 0 Set.empty entry state) fields
          ranges <- case kind of
            CalGrayFamily -> Right [(0, 1)]
            CalRgbFamily -> Right (replicate 3 (0, 1))
            LabFamily -> ((0, 100) :) <$> maybe (Right [(-100, 100), (-100, 100)]) (rangePairs 2) (lookup "Range" deepFields)
          Right (Just (CieSpace kind (family <> " " <> T.pack (show deepFields)) ranges, state))
    P.OArr [P.OName "ICCBased", reference] -> do
      (key, entries) <- pdfStreamReference unsupported state Set.empty reference
      count <- maybe (Left unsupported) (\n -> dereference Set.empty n state) (lookup "N" entries)
      components <- case count of
        P.OInt n | n `elem` [1, 3, 4] -> Right (fromInteger n)
        _ -> Left unsupported
      deepEntries <- traverse (\(name, entry) -> (name,) <$> resolveDeep 0 Set.empty entry state) [(name, entry) | (name, entry) <- entries, name `notElem` ["Length", "Filter", "DecodeParms", "DL"]]
      ranges <- maybe (Right (replicate components (0, 1))) (rangePairs components) (lookup "Range" deepEntries)
      if all (uncurry (<)) ranges then Right () else Left unsupported
      (profile, decoded) <- decodePdfStream key entries state
      let identity = "ICCBased " <> T.pack (show deepEntries) <> " " <> TE.decodeLatin1 (P.sha256 profile)
      space <- case (iccDataSpace profile, components) of
        ("GRAY", 1) -> Right (RangedSpace GraySpace ranges)
        ("RGB ", 3) -> Right (RangedSpace RgbSpace ranges)
        ("CMYK", 4) -> Right (RangedSpace CmykSpace ranges)
        ("Lab ", 3) -> Right (CieSpace LabFamily identity ranges)
        _ -> Left unsupported
      Right (Just (space, decoded))
    _ -> Right Nothing
  where
    unsupported = "PDF 図版の ICC プロファイルの色空間を扱えません"
    rangePairs count = \case
      P.OArr entries | length entries == 2 * count -> do
        numbers <- traverse number entries
        let pairs (low : high : rest) = (low, high) : pairs rest
            pairs _ = []
            result = pairs numbers
        if all (uncurry (<=)) result then Right result else Left "PDF 図版の色空間の Range が不正です"
      _ -> Left "PDF 図版の色空間の Range が不正です"
    number = \case
      P.OInt n -> Right (fromInteger n)
      P.OReal text | Just parsed <- decimal (TE.encodeUtf8 text) -> Right parsed
      _ -> Left "PDF 図版の色空間の Range が不正です"

-- A value with every reference replaced, bounded like Form nesting.
resolveDeep :: Int -> Set.Set P.ObjNum -> P.ObjOf P.ObjNum -> Resources -> Either Text (P.ObjOf P.ObjNum)
resolveDeep depth _ _ _ | depth > P.maxNesting = Left "PDF 図版の色空間の辞書が深すぎます"
resolveDeep depth seen (P.ORef reference) state = do
  guardForm seen reference
  value <- maybe (Left "PDF 図版の資源の参照先がありません") Right (Map.lookup reference (sourceObjects state))
  resolveDeep (depth + 1) (Set.insert reference seen) value state
resolveDeep depth seen (P.OArr values) state = P.OArr <$> traverse (\value -> resolveDeep (depth + 1) seen value state) values
resolveDeep depth seen (P.ODict values) state = P.ODict <$> traverse (\(name, value) -> (name,) <$> resolveDeep (depth + 1) seen value state) values
resolveDeep _ _ (P.OStream fields _) _ = Right (P.ODict fields)
resolveDeep _ _ value _ = Right value

colorKind :: Color -> RasterKind
colorKind = \case
  Cie _ _ (Just _) -> Grayscale
  Cie key values Nothing -> SolidOther key values
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
        Cie _ _ (Just g) -> 1 - g
        _ -> 1
      values = [fromIntegral component / 100 * amount | component <- [c, m, y, k]]
   in BC.unwords (map (TE.encodeUtf8 . P.showRationalDigits 8) values <> [if isStroke then "K" else "k"])

-- Function-based shadings (root ADR 0425) ---------------------------------

-- | A shading's dictionary, the space of its values, its functions, the
-- colours of its definition, and how its gray values follow one output.
data ShadingInfo = ShadingInfo
  { shadingFields :: ![(Text, P.ObjOf P.ObjNum)],
    shadingFunctions :: !(Either S.Fn [S.Fn]),
    shadingColours :: ![Color],
    shadingBackground :: !(Maybe [Rational]),
    shadingGray :: !(Maybe S.Gray)
  }

shadingKind :: ShadingInfo -> RasterKind
shadingKind = foldl mergeKind Unpainted . map colorKind . shadingColours

allGray :: ShadingInfo -> Bool
allGray shading = all ((== Grayscale) . colorKind) (shadingColours shading)

-- | All its values are tones, but no linear map recolours them.
shadingBlocked :: ShadingInfo -> Bool
shadingBlocked shading = allGray shading && isNothing (shadingGray shading)

shadingResource :: Scope -> P.ObjOf P.ObjNum -> [ByteString] -> Resources -> Either Text (P.ObjOf P.ObjNum, Resources)
shadingResource scope resources args state = do
  name <- resourceName args
  (table, tabled) <- case Map.lookup scope (shadingTables state) of
    Just table -> Right (table, state)
    Nothing -> do
      values <- dictionary resources state
      entries <- maybe (Right []) (`dictionary` state) (lookup "Shading" values)
      let table = Map.fromList entries
      Right (table, state {shadingTables = Map.insert scope table (shadingTables state)})
  value <- maybe (Left "PDF 図版のシェーディングが見つかりません") Right (Map.lookup name table)
  Right (value, tabled)

freshShadingAlias :: Scope -> P.ObjNum -> Resources -> Either Text Text
freshShadingAlias scope clone state = do
  names <- maybe (Left "PDF 図版の資源辞書を準備できません") Right (Map.lookup scope (shadingTables state))
  let choose candidate = if Map.member candidate names then choose (candidate <> "_") else candidate
  Right (choose ("GolemFigureColor" <> TE.decodeLatin1 (BC.pack (show (negate (toInteger clone))))))

analyzeShading :: P.ObjOf P.ObjNum -> Resources -> Either Text (ShadingInfo, Resources)
analyzeShading value state = do
  resolved <- dereference Set.empty value state
  fields <- case resolved of
    P.ODict entries -> Right entries
    P.OStream _ _ -> Left "PDF 図版のメッシュのシェーディングの色置換は未完了です"
    _ -> Left invalid
  kind <- maybe (Left invalid) (\v -> dereference Set.empty v state) (lookup "ShadingType" fields)
  if kind `elem` map P.OInt [1, 2, 3] then Right () else Left "PDF 図版のメッシュのシェーディングの色置換は未完了です"
  spaceValue <- maybe (Left invalid) Right (lookup "ColorSpace" fields)
  (space, spaced) <- shadingSpace spaceValue state
  functionValue <- maybe (Left invalid) Right (lookup "Function" fields)
  (functionObject, read') <- resolveFunction 0 Set.empty functionValue spaced
  functions <- case functionObject of
    P.OArr entries -> Right <$> traverse (S.readFunction streamBytes) entries
    single -> Left <$> S.readFunction streamBytes single
  let components = spaceComponents space
      all' = either pure id functions
      hasCalculator = \case
        S.Fn4 -> True
        S.Fn3 _ inner _ -> any hasCalculator inner
        _ -> False
  if any hasCalculator all' then Left "PDF 図版の PostScript の計算機の関数のシェーディングは色を判定できません" else Right ()
  outputs <- case functions of
    Left fn | S.fnOutputs fn == components -> Right (Just (S.fnPositions fn))
    Right fns
      | length fns == components && all ((== 1) . S.fnOutputs) fns ->
          let columns = [concatMap (take 1) (S.fnPositions fn) | fn <- fns]
           in Right (if allSame (map length columns) then Just (transpose columns) else Nothing)
    _ -> Left invalid
  background <- traverse (\v -> dereference Set.empty v read' >>= numbersOf) (lookup "Background" fields)
  colours <- traverse (rawColor space) (maybe [] id outputs <> maybe [] pure background)
  let definitions = case functions of
        Left fn -> [S.fnDefinition fn i | i <- [0 .. components - 1]]
        Right fns -> [S.fnDefinition fn 0 | fn <- fns]
      valuesOf i = case functions of
        Left fn -> S.fnValues fn i <> maybe [] (pure . (!! i)) background
        Right fns -> S.fnValues (fns !! i) 0 <> maybe [] (pure . (!! i)) background
      ranges = spaceRanges space
      within = case functions of
        Left fn -> S.fnWithin ranges fn
        Right fns -> and [S.fnWithin [range] fn | (range, fn) <- zip ranges fns]
      backgroundWithin = maybe True (and . zipWith (\(low, high) v -> low <= v && v <= high) ranges) background
      zeros = all (all (== 0) . valuesOf)
      normalized (low, high) = (1 / (high - low), negate low / (high - low))
      gray = case space of
        GraySpace -> Just (S.Gray 0 1 0)
        CieSpace CalGrayFamily _ _ -> Just (S.Gray 0 1 0)
        RangedSpace GraySpace [range] -> Just (uncurry (S.Gray 0) (normalized range))
        RgbSpace | equalOutputs -> Just (S.Gray 0 1 0)
        CieSpace CalRgbFamily _ _ | equalOutputs -> Just (S.Gray 0 1 0)
        RangedSpace RgbSpace (range : rest) | equalOutputs, all (== range) rest -> Just (uncurry (S.Gray 0) (normalized range))
        CieSpace LabFamily _ _ | zeros [1, 2] -> Just (S.Gray 0 (1 / 100) 0)
        CmykSpace | zeros [0, 1, 2] -> Just (S.Gray 3 (-1) 1)
        RangedSpace CmykSpace [(l0, _), (l1, _), (l2, _), (low, high)]
          | and [all (== l) (valuesOf i) | (i, l) <- zip [0, 1, 2] [l0, l1, l2]] -> Just (S.Gray 3 (-1 / (high - low)) (1 + low / (high - low)))
        _ -> Nothing
      equalOutputs = allSame definitions && maybe True allSame background
      linear = if isJust outputs && within && backgroundWithin then gray else Nothing
  Right (ShadingInfo fields functions colours background linear, read')
  where
    invalid = "PDF 図版のシェーディングを読めません"
    streamBytes = \case
      P.OStream _ bytes -> Right bytes
      _ -> Left "PDF 図版のシェーディングの関数を読めません"
    allSame :: (Eq a) => [a] -> Bool
    allSame xs = and (zipWith (==) xs (drop 1 xs))
    numbersOf = \case
      P.OArr entries -> traverse (\case P.OInt n -> Right (fromInteger n); P.OReal t -> maybe (Left invalid) Right (decimal (TE.encodeUtf8 t)); _ -> Left invalid) entries
      _ -> Left invalid

-- | A function with references replaced and sampled tables decoded.
resolveFunction :: Int -> Set.Set P.ObjNum -> P.ObjOf P.ObjNum -> Resources -> Either Text (P.ObjOf P.ObjNum, Resources)
resolveFunction depth seen value state
  | depth > P.maxNesting = Left "PDF 図版のシェーディングの関数が深すぎます"
  | otherwise = case value of
      P.ORef key -> do
        guardForm seen key
        object <- maybe (Left "PDF 図版の資源の参照先がありません") Right (Map.lookup key (sourceObjects state))
        case object of
          P.OStream fields _ -> do
            (body, decoded) <- decodePdfStream key fields state
            deep <- traverse (\(name, entry) -> (name,) <$> resolveDeep 0 Set.empty entry state) fields
            Right (P.OStream deep body, decoded)
          _ -> resolveFunction (depth + 1) (Set.insert key seen) object state
      P.OArr entries -> do
        (resolved, final) <- foldM (\(acc, st) entry -> (\(r, st') -> (acc <> [r], st')) <$> resolveFunction (depth + 1) seen entry st) ([], state) entries
        Right (P.OArr resolved, final)
      P.ODict fields -> do
        (resolved, final) <- foldM (\(acc, st) (name, entry) -> (\(r, st') -> (acc <> [(name, r)], st')) <$> (if name == "Functions" then resolveFunction (depth + 1) seen entry st else (,st) <$> resolveDeep 0 Set.empty entry st)) ([], state) fields
        Right (P.ODict resolved, final)
      P.OStream _ _ -> Left "PDF 図版のシェーディングの関数を読めません"
      other -> Right (other, state)

-- | The space of a shading's values: a device family name or a CIE-based or
-- ICCBased array.
shadingSpace :: P.ObjOf P.ObjNum -> Resources -> Either Text (Space, Resources)
shadingSpace value state = do
  resolved <- dereference Set.empty value state
  case resolved of
    P.OName "DeviceGray" -> Right (GraySpace, state)
    P.OName "DeviceRGB" -> Right (RgbSpace, state)
    P.OName "DeviceCMYK" -> Right (CmykSpace, state)
    _ -> do
      special <- cieSpace resolved state
      maybe (Left "PDF 図版のシェーディングの色空間に対応していません") Right special

spaceComponents :: Space -> Int
spaceComponents = length . spaceRanges

spaceRanges :: Space -> [(Rational, Rational)]
spaceRanges = \case
  GraySpace -> [(0, 1)]
  RgbSpace -> replicate 3 (0, 1)
  CmykSpace -> replicate 4 (0, 1)
  IndexedSpace _ -> [(0, 255)]
  RangedSpace _ ranges -> ranges
  CieSpace _ _ ranges -> ranges

-- | A shading value as a colour, without clipping it to the space.
rawColor :: Space -> [Rational] -> Either Text Color
rawColor space values = case (space, values) of
  (GraySpace, [g]) -> Right (Gray g)
  (RgbSpace, [r, g, b]) -> Right (Rgb r g b)
  (CmykSpace, [c, m, y, k]) -> Right (CmykColor c m y k)
  (RangedSpace base ranges, _) | length ranges == length values -> rawColor base [(v - low) / (high - low) | ((low, high), v) <- zip ranges values]
  (CieSpace family key ranges, _) | length ranges == length values -> Right (cieColor family key (map (const (-(10 ^ (30 :: Int)), 10 ^ (30 :: Int))) ranges) values)
  _ -> Left "PDF 図版のシェーディングの色の成分数が不正です"

-- | The recoloured shading: a gray one maps the output of its gray value,
-- a one-colour one paints the swatch.
convertShading :: Cmyk -> ShadingInfo -> P.ObjOf P.ObjNum
convertShading (c, m, y, k) shading =
  let inks = [fromIntegral component / 100 | component <- [c, m, y, k]] :: [Rational]
      function = case shadingGray shading of
        Just (S.Gray output alpha beta) | allGray shading ->
          let maps = [(negate (s * alpha), s * (1 - beta)) | s <- inks]
              apply (a, b) v = a * v + b
           in ( case shadingFunctions shading of
                  Left fn -> S.mapFunction output maps fn
                  Right fns -> P.OArr [S.mapFunction 0 [one] (fns !! output) | one <- maps],
                fmap (\values -> P.OArr [S.numberObject (apply one (values !! output)) | one <- maps]) (shadingBackground shading)
              )
        _ -> (S.solidFunction (domainOf (shadingFunctions shading)) inks, fmap (const (P.OArr (map S.numberObject inks))) (shadingBackground shading))
      (newFunction, newBackground) = function
      replaced = [("ColorSpace", P.OName "DeviceCMYK"), ("Function", newFunction)] <> [("Background", b) | Just b <- [newBackground]]
   in P.ODict ([(key, value) | (key, value) <- shadingFields shading, key `notElem` map fst replaced] <> replaced)
  where
    domainOf = \case
      Left fn -> domain fn
      Right (fn : _) -> domain fn
      Right [] -> (0, 1)
    domain = \case
      S.Fn0 fields _ _ _ _ _ -> first fields
      S.Fn2 _ _ _ d _ _ -> d
      S.Fn3 fields _ _ -> first fields
      S.Fn4 -> (0, 1)
    first fields = case lookup "Domain" fields of
      Just (P.OArr (a : b : _)) | Just x <- num a, Just z <- num b -> (x, z)
      _ -> (0, 1)
    num = \case
      P.OInt n -> Just (fromInteger n)
      P.OReal t -> decimal (TE.encodeUtf8 t)
      _ -> Nothing

-- | Streams nested in a converted object become fresh objects.
materialize :: P.ObjOf P.ObjNum -> Resources -> Either Text (P.ObjOf P.ObjNum, Resources)
materialize object state = case object of
  P.OStream fields bytes -> do
    charged <- charge (BS.length bytes) state
    fresh <- freshObject charged
    Right (P.ORef fresh, charged {convertedObjects = Map.insert fresh (P.OStream fields bytes) (convertedObjects charged)})
  P.OArr values -> do
    (out, final) <- foldM (\(acc, st) v -> (\(r, st') -> (acc <> [r], st')) <$> materialize v st) ([], state) values
    Right (P.OArr out, final)
  P.ODict fields -> do
    (out, final) <- foldM (\(acc, st) (name, v) -> (\(r, st') -> (acc <> [(name, r)], st')) <$> materialize v st) ([], state) fields
    Right (P.ODict out, final)
  other -> Right (other, state)
