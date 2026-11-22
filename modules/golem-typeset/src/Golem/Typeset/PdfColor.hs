-- | Process-colour conversion of imported figures (root ADR 0403).
module Golem.Typeset.PdfColor (recolorImportedPage) where

import Control.Monad (foldM)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (isDigit)
import Data.Map.Strict qualified as Map
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P
import Golem.Typeset.FigureColor (Cmyk, RasterAnalysis, RasterKind (..))

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
recolorImportedPage swatch _ page = do
  if P.ipDecodedBytes page < 0 || P.ipDecodedBytes page > P.maxDecodedBytes
    then Left "PDF 図版の展開済みサイズが不正です"
    else Right ()
  let source = Map.fromList (P.ipObjects page)
      initialState = Resources {sourceObjects = source, decodedForms = Map.empty, formSummaries = Map.empty, convertedForms = Map.empty, convertedObjects = Map.empty, scopeBindings = Map.empty, sourceTables = Map.empty, clonedResources = Map.empty, remainingBytes = P.maxDecodedBytes - P.ipDecodedBytes page}
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
    decodedForms :: !(Map.Map P.ObjNum ByteString),
    formSummaries :: !(Map.Map (P.ObjNum, Scope, Graphics) RasterKind),
    convertedForms :: !(Map.Map (P.ObjNum, Scope) P.ObjNum),
    convertedObjects :: !(Map.Map P.ObjNum (P.ObjOf P.ObjNum)),
    scopeBindings :: !(Map.Map Scope (Map.Map Text P.ObjNum)),
    sourceTables :: !(Map.Map Scope (Map.Map Text (P.ObjOf P.ObjNum))),
    clonedResources :: !(Map.Map Scope P.ObjNum),
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
            (key, fields, childResources, childScope, prepared) <- formResource resources scope args st
            let cacheKey = (key, childScope, current)
            case Map.lookup cacheKey (formSummaries prepared) of
              Just kind -> Right (Just kind, prepared)
              Nothing -> do
                guardForm active key
                (body, decoded) <- decodeForm key fields prepared
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
            (key, fields, childResources, childScope, prepared) <- formResource resources scope args st
            (clone, child) <- case Map.lookup (key, childScope) (convertedForms prepared) of
              Just converted -> Right (converted, prepared)
              Nothing -> do
                guardForm active key
                (body, decoded) <- decodeForm key fields prepared
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
  states <- maybe (Left "PDF 図版の ExtGState がありません") (\value -> dictionary value state) (lookup "ExtGState" entries)
  selected <- maybe (Left "PDF 図版の描画状態が見つかりません") (\value -> dictionary value state) (lookup name states)
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
    objects <- maybe (Right []) (\value -> dictionary value state) (lookup "XObject" values)
    let table = Map.fromList objects
    Right (table, state {sourceTables = Map.insert scope table (sourceTables state)})

formResource :: P.ObjOf P.ObjNum -> Scope -> [ByteString] -> Resources -> Either Text (P.ObjNum, [(Text, P.ObjOf P.ObjNum)], P.ObjOf P.ObjNum, Scope, Resources)
formResource resources scope args state = do
  name <- resourceName args
  (objects, prepared) <- sourceTable scope resources state
  key <- case Map.lookup name objects of
    Just (P.ORef key) -> Right key
    _ -> Left "PDF 図版の XObject が見つかりません"
  object <- maybe (Left "PDF 図版の XObject の参照先がありません") Right (Map.lookup key (sourceObjects state))
  fields <- case object of
    P.OStream fields _ | lookup "Subtype" fields == Just (P.OName "Form") -> Right fields
    _ -> Left "PDF 図版の画像 XObject の色変換は未完了です"
  case lookup "Resources" fields of
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

decodeForm :: P.ObjNum -> [(Text, P.ObjOf P.ObjNum)] -> Resources -> Either Text (ByteString, Resources)
decodeForm key fields state = case Map.lookup key (decodedForms state) of
  Just body -> Right (body, state)
  Nothing -> do
    source <- case Map.lookup key (sourceObjects state) of
      Just (P.OStream _ bytes) -> Right bytes
      _ -> Left "PDF 図版の Form ストリームがありません"
    filters <- traverse (\(name, value) -> (name,) <$> deep 0 Set.empty value) [(name, value) | (name, value) <- fields, name `elem` ["Filter", "DecodeParms"]]
    (body, cost) <- either (const (Left "PDF 図版の Form を展開できません")) Right (P.decodeImportedStream (remainingBytes state) filters source)
    charged <- charge (max cost (BS.length body)) state
    Right (body, charged {decodedForms = Map.insert key body (decodedForms charged)})
  where
    deep depth _ _ | depth > P.maxNesting = Left "PDF 図版のフィルターの辞書が深すぎます"
    deep depth seen (P.ORef reference) = do
      guardForm seen reference
      value <- maybe (Left "PDF 図版のフィルターの参照先がありません") Right (Map.lookup reference (sourceObjects state))
      deep (depth + 1) (Set.insert reference seen) value
    deep depth seen (P.OArr values) = P.OArr <$> traverse (deep (depth + 1) seen) values
    deep depth seen (P.ODict values) = P.ODict <$> traverse (\(name, value) -> (name,) <$> deep (depth + 1) seen value) values
    deep _ _ value = Right value

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
