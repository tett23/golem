{- | The build pipeline (golem-driver ADR 0001): project → parse → S0 → S1
→ outputs. PDF (S2 and later) is added by golem-driver ADR 0002.
-}
module Golem.Driver
  ( Target (..),
    allTargets,
    CropMarks (..),
    BuildOptions (..),
    defaultOptions,
    BuildResult (..),
    build,
    PreflightOptions (..),
    defaultPreflightOptions,
    PreflightResult (..),
    preflight,
    evaluateProject,
    evaluateProjectWith,
    loadBibliography,
    Evaluated (..),
    localStylesOf,
    docStyles,
    runningVars,
    missingStyleFiles,
    targetFileDiagnostics,
    sourceInfos,
    withEvaluatedSources,
    assetRefs,
    AssetUse (..),
    FontProvider (..),
    LoadedFonts (..),
    noFontProvider,
    paraLineBreaks,
    keepStyles,
    sourceSettingsOf,
    builtinKeepStyles,
    cssFontSize,
  )
where

import Control.Applicative ((<|>))
import Control.Exception (SomeException, try)
import Control.Monad (filterM, forM, forM_, mfilter, when)
import Data.Aeson qualified as J
import Data.Aeson.Key qualified as JK
import Data.Aeson.KeyMap qualified as KM
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (fromRight, lefts, rights)
import Data.List (nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Scientific (Scientific, base10Exponent, coefficient)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Vector qualified as V
import Golem.Doc.Assemble
import Golem.Doc.Bibliography (CslDate (..), CslEntry (..), CslName (..), formatEntry)
import Golem.Doc.IR
import Golem.Doc.ListMarkers (defaultNumberFormat)
import Golem.Doc.Numbering (numberSeparator)
import Golem.Driver.Fonts (golemFontProvider)
import Golem.Driver.Pdf
import Golem.Driver.Plugins (loadPlugins)
import Golem.Epub
import Golem.Eval.Expr (Env (..), embedValue, evalExpr)
import Golem.Eval.File
import Golem.Eval.Value
import Golem.Html
import Golem.Parser.AST qualified as A
import Golem.Parser.Read (ReadFailure (..), readInfo, readSourceFile, readTableSource)
import Golem.Parser.SourceSettings (SourceSettings)
import Golem.Pdf qualified as P
import Golem.Plugin.Lock (defaultCacheDir)
import Golem.Preflight (check)
import Golem.Preflight.Rules (Rules (..), parseRules, printRules)
import Golem.Preflight.View (View)
import Golem.Project
import Golem.Project.Paths (PathError (..), pathErrorMessage, resolveInRoot)
import Golem.Project.Style
import Golem.Syntax
import Golem.Text qualified as GT
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, pathIsSymbolicLink, removeDirectoryRecursive)
import System.FilePath (takeDirectory, takeFileName, (</>))

data Target = TargetHtml | TargetEpub | TargetText | TargetPdf
  deriving stock (Eq, Ord, Show)

-- | Every target, in the order they are written (golem-cli ADR 0002).
allTargets :: [Target]
allTargets = [TargetHtml, TargetEpub, TargetText, TargetPdf]

{- | The crop marks of the PDF (golem-pdf ADR 0004), chosen by golem build
--marks. golem-cli does not depend on golem-pdf, so this is not its type.
-}
data CropMarks = NoMarks | JapaneseMarks | WesternMarks
  deriving stock (Eq, Show)

data BuildOptions = BuildOptions
  { optRoot :: !FilePath,
    optTargets :: !(Maybe [Target]),
    optProfile :: !Profile,
    optCheckOnly :: !Bool,
    -- | where fonts come from (golem-font; see Golem.Driver.Pdf)
    optFonts :: !FontProvider,
    optParallel :: !Bool,
    -- | the crop marks of the PDF (golem-pdf ADR 0004)
    optMarks :: !CropMarks,
    -- | --no-notices: no notice is reported (golem-syntax ADR 0002)
    optNoNotices :: !Bool
  }

defaultOptions :: FilePath -> BuildOptions
defaultOptions root = BuildOptions root Nothing Dev False golemFontProvider True NoMarks False

data BuildResult = BuildResult
  { brDiagnostics :: ![Diagnostic],
    brSources :: !(Map FileId SourceInfo),
    brWritten :: ![FilePath]
  }

data Evaluated = Evaluated
  { evProject :: !Project,
    evStyle :: !Style,
    -- | the FileId of style.toml, where its diagnostics point
    evStyleFile :: !FileId,
    -- | the text of style.toml, empty when there is none (an input of the instance ID)
    evStyleText :: !Text,
    -- | the text of plugins.lock, when there is one (golem-plugin ADR 0003)
    evLockText :: !(Maybe Text),
    evResults :: !(Map FileId EvalResult),
    evBook :: !(Maybe Book),
    evDiagnostics :: ![Diagnostic],
    -- | the files read as text for @table and @listing, where their diagnostics point (golem-eval ADR 0004)
    evAssetSources :: !(Map FileId SourceInfo),
    -- | the table files the evaluation read, relative to the root, for the LSP to watch (golem-eval ADR 0004)
    evTableFiles :: !(Set.Set FilePath),
    {- | S0 of one file again, in the context of the last evaluation
    (the LSP re-evaluates the edited file alone when nothing that other
    files depend on has changed).
    -} evReevaluate :: FileId -> SourceFile -> EvalResult
  }

-- | The styles each file defines, of the files that define any (docs/adr ADR 0014).
localStylesOf :: Evaluated -> Map FileId LocalStyles
localStylesOf = Map.filter (/= noLocalStyles) . Map.map erStyles . evResults

-- | The style of each document: style.toml with the styles its file defines over it.
docStyles :: Evaluated -> FileId -> Style
docStyles e fid = maybe (evStyle e) (withLocalStyles (evStyle e)) (Map.lookup fid (localStylesOf e))

{- | The FileId of plugins.lock, where G0611 points (golem-plugin ADR 0003):
the one after style.toml's.
-}
lockFileId :: Project -> FileId
lockFileId p = let FileId n = styleFileId p in FileId (n + 1)

{- | Adds plugins.lock, when there is one, and the files read for @table
and @listing (golem-eval ADR 0004) to the files of diagnostics.
-}
withEvaluatedSources :: Evaluated -> Map FileId SourceInfo -> Map FileId SourceInfo
withEvaluatedSources e =
  Map.union (evAssetSources e)
    . maybe id (Map.insert (lockFileId (evProject e)) . SourceInfo "plugins.lock" . mkLineIndex) (evLockText e)

-- | Line indexes for rendering diagnostics.
sourceInfos :: Project -> Map FileId SourceInfo
sourceInfos p =
  Map.insert (projectManifestFile p) (SourceInfo "manifest.toml" (mkLineIndex (projectManifestText p))) $
    Map.map (\sf -> SourceInfo (sfPath sf) (mkLineIndex (sfText sf))) (projectSources p)

-- | Everything up to S1. Stops after a stage that produced errors.
evaluateProject :: Profile -> FilePath -> IO (Either ProjectFailure Evaluated)
evaluateProject = evaluateProjectWith Map.empty

-- | @overlay@ replaces file contents (unsaved edits in the LSP).
evaluateProjectWith :: Map FilePath Text -> Profile -> FilePath -> IO (Either ProjectFailure Evaluated)
evaluateProjectWith overlay profile root = do
  lp <- loadProjectWith overlay root
  case lp of
    Left f -> pure (Left f)
    Right project -> do
      styleBytes <- readMaybeBytes (root </> "style.toml")
      let -- G0323: the default style, when there is no style.toml (golem-syntax ADR 0002)
          defaultStyleNotice = [notice "G0323" (mkSpan (projectManifestFile project) 0 0) "style.toml がないので、既定の体裁で組みます" | isNothing styleBytes]
          synDiags = defaultStyleNotice <> concatMap sfSyntaxDiagnostics (Map.elems (projectSources project))
          manifest0 = projectManifest project
          styleFid = styleFileId project
      -- style.toml passes the reading stage too (golem-parser ADR 0009)
      let styleRead = traverse (readSourceFile styleFid "style.toml") styleBytes
          styleText = fromRight Nothing styleRead
      case first (map noFix . rfDiagnostics) styleRead >>= loadStyle styleFid of
        -- style.toml is where its errors point (golem-project ADR 0006)
        Left ds -> pure (Left (ProjectFailure ds (Map.insert styleFid (maybe (SourceInfo "style.toml" (mkLineIndex "")) (readInfo "style.toml") styleBytes) (sourceInfos project))))
        Right style
          | hasErrors synDiags -> do
              loaded <- loadAssets overlay root project
              let assets = laAssets loaded
              (bibDiags, citeKeys, _) <- loadBibliography root manifest0
              pure (Right (Evaluated project style styleFid (fromMaybe "" styleText) Nothing Map.empty Nothing (synDiags <> laDiagnostics loaded <> bibDiags) (laSources loaded) (laTableFiles loaded) (reeval profile project style assets citeKeys noPlugins Map.empty)))
          | otherwise -> do
              let manifest = manifest0
                  -- one G0307 for each name, in the order of the chapters (golem-project ADR 0006)
                  masterDiags =
                    [ diagnostic "G0307" Error (mkSpan (projectManifestFile project) 0 0) ("style.toml にないマスターページです: " <> m)
                    | m <- nub [m | (_, Just m) <- projectChapters project],
                      not (Map.member m (stMasters style))
                    ]
              cacheDir <- defaultCacheDir
              lockText <- readMaybeText (root </> "plugins.lock")
              hookE <- loadPlugins cacheDir (projectManifestFile project) (lockFileId project) (fromMaybe "" lockText) manifest
              let (pluginDiags, hook) = either (,noPlugins) ([],) hookE
                  -- no G0222 after the plugins failed to load (golem-plugin ADR 0003)
                  quiet = if null pluginDiags then id else \r -> r {erDiagnostics = filter ((/= DiagnosticCode "G0222") . diagCode) (erDiagnostics r)}
              loaded <- loadAssets overlay root project
              let assets = laAssets loaded
              -- G0326 and G0303 of the bibliography, for every target (golem-doc ADR 0004)
              (bibDiags, citeKeys, _) <- loadBibliography root manifest
              let results = Map.map quiet (evalAll profile project style assets citeKeys hook)
                  s0Diags = concatMap erDiagnostics (Map.elems results)
                  -- the chapter of the manifest of each file: a top-level entry, a nested array as one (golem-driver ADR 0018)
                  chapterOfFile = [i | (i, e) <- zip [0 :: Int ..] (manifestChapters manifest), _ <- chapterFiles [e]] <> [length (manifestChapters manifest) ..]
                  chapterRuns = [(erDocument r, ch) | ((fid, _), ch) <- zip (projectChapters project) chapterOfFile, Just r <- [Map.lookup fid results]]
                  chapterDocs = map fst chapterRuns
                  -- where G0407 points (golem-syntax ADR 0002)
                  numberSites = Map.unions (map erNumberSites (Map.elems results))
                  cfg = AssembleConfig (Map.mapMaybe hsNumber (stHeadings style)) (stFigureNumber style) numberSites (stNotesNumbering style) (map snd chapterRuns) (cdNumber (stCode style))
                  pre = defaultStyleNotice <> masterDiags <> pluginDiags <> laDiagnostics loaded <> bibDiags <> s0Diags
                  again f sf = quiet (reeval profile project style assets citeKeys hook results f sf)
              if hasErrors pre
                then pure (Right (Evaluated project style styleFid (fromMaybe "" styleText) lockText results Nothing pre (laSources loaded) (laTableFiles loaded) again))
                else do
                  let (book, s1Diags) = assemble cfg evalDeferred chapterDocs
                  pure (Right (Evaluated project style styleFid (fromMaybe "" styleText) lockText results (Just book) (pre <> s1Diags) (laSources loaded) (laTableFiles loaded) again))

readMaybeText :: FilePath -> IO (Maybe Text)
readMaybeText p = do
  e <- doesFileExist p
  if e then Just . TE.decodeUtf8Lenient <$> BS.readFile p else pure Nothing

readMaybeBytes :: FilePath -> IO (Maybe BS.ByteString)
readMaybeBytes p = do
  e <- doesFileExist p
  if e then Just <$> BS.readFile p else pure Nothing

-- | golem fmt does not format style.toml, so its G0103 has no fix (golem-parser ADR 0009).
noFix :: Diagnostic -> Diagnostic
noFix d = d {diagFixes = []}

-- | A deferred expression; G0208 is at the inline @sp@ (golem-eval ADR 0003).
evalDeferred :: DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic Text
evalDeferred dv sp (DeferredExpr e) =
  let docNs = Map.fromList [("chapters", VHash (Map.fromList [("count", VInt (dvChapterCount dv))]))]
      en = Env Map.empty (Map.singleton "doc" docNs)
   in evalExpr en e >>= embedValue sp

-- | Evaluates files in import order so that imports see their exports.
evalAll :: Profile -> Project -> Style -> Map FilePath Asset -> Set.Set Text -> PluginHook -> Map FileId EvalResult
evalAll profile project style assets citeKeys hook = foldl' step Map.empty (projectOrder project)
  where
    step acc fid = case Map.lookup fid (projectSources project) of
      Nothing -> acc
      Just sf -> Map.insert fid (reeval profile project style assets citeKeys hook acc fid sf) acc

-- | S0 of one file, with the exports of its imports taken from @acc@.
reeval :: Profile -> Project -> Style -> Map FilePath Asset -> Set.Set Text -> PluginHook -> Map FileId EvalResult -> FileId -> SourceFile -> EvalResult
reeval profile project style assets citeKeys hook acc fid sf =
  let ft = projectFiles project
      meta = metadataValues (manifestMetadata (projectManifest project))
      importsOfFile f = let ImportGraph g = projectImports project in Map.findWithDefault [] f g
      exports =
        Map.fromList
          [ (path, erExports r)
          | (tfid, _) <- importsOfFile fid,
            Just path <- [lookupPath tfid ft],
            Just r <- [Map.lookup tfid acc]
          ]
      ctx =
        EvalContext
          { ctxFile = fid,
            ctxPath = sfPath sf,
            ctxProfile = profile,
            ctxMeta = meta,
            ctxImports = exports,
            ctxSwatches = Map.keysSet (stSwatches style),
            ctxCharStyles = Map.keysSet (stCharStyles style),
            ctxParaStyles = paraLineBreaks style,
            ctxDefaultKenten = compKenten (stComposition style),
            ctxCiteKeys = citeKeys,
            ctxAssets = assets,
            ctxPlugins = hook,
            ctxSource = sourceSettingsOf project fid,
            ctxStyle = style
          }
   in evalFile ctx (sfAst sf)

-- | How a file of the project is read (docs/adr ADR 0013).
sourceSettingsOf :: Project -> FileId -> SourceSettings
sourceSettingsOf project fid = Map.findWithDefault (manifestSource (projectManifest project)) fid (projectSourceSettings project)

-- | The paragraph styles that keep their lines (lint G0501, docs/adr ADR 0005).
keepStyles :: Style -> Set.Set Text
keepStyles = Map.keysSet . Map.filter (== KeepLines) . paraLineBreaks

-- | The built-in paragraph styles that keep their lines: verse.
builtinKeepStyles :: Set.Set Text
builtinKeepStyles = keepStyles defaultStyle

-- | @meta@: the text of the metadata a running head shows too, and the creators.
metadataValues :: Metadata -> Map Text Value
metadataValues md =
  Map.insert "creators" (VArray [VString (crName c) | c <- mdCreators md]) (VString <$> runningMetadata md)

{- | The variables the running heads show, as text, for each chapter file
by its master page (golem-driver ADR 0022): its own (@{set.<name>}@) and
those of its imports (@{set.<namespace>.<name>}@). G0267 for a variable
without @?@ that the file does not have, G0268 for a value that is not a
string or a number; at the top of the file, once for each file and name.
-}
runningVars :: Evaluated -> (Map FileId (Map [Text] Text), [Diagnostic])
runningVars e =
  let project = evProject e
      style = evStyle e
      masters = stMasters style
      ImportGraph graph = projectImports project
      masterOf name = (name >>= \n -> (n,) <$> Map.lookup n masters) <|> (("body",) <$> Map.lookup "body" masters) <|> Map.lookupMin masters
      perFile (fid, name) = case (masterOf name, Map.lookup fid (evResults e)) of
        (Just (mname, MasterDef (Just rh) _), Just r) ->
          let refs = Map.fromListWith (&&) [(n, q) | c <- [rhOdd rh, rhEven rh], (RefVar n, q) <- runningRefs c]
              lookupVar = \case
                [v] -> Map.lookup v (erExports r)
                [ns, v] -> listToMaybe [x | (tfid, site) <- Map.findWithDefault [] fid graph, isNamespace site == ns, Just tr <- [Map.lookup tfid (evResults e)], Just x <- [Map.lookup v (erExports tr)]]
                _ -> Nothing
              at = mkSpan fid 0 0
              related = [(mkSpan (evStyleFile e) 0 0, "マスターページ " <> mname <> " の柱の書式")]
              one (n, optional) = case lookupVar n of
                Nothing
                  | optional -> ([], [])
                  | otherwise -> ([], [(diagnostic "G0267" Error at ("柱が参照する変数 " <> T.intercalate "." n <> " が、このファイルにありません（マスターページ " <> mname <> "）")) {diagRelated = related}])
                -- strings and numbers as they are embedded in prose
                Just v -> case embedValue at v of
                  Right t -> ([(n, t)], [])
                  Left _ -> ([], [(diagnostic "G0268" Error at ("柱に出せるのは文字列と数です: " <> T.intercalate "." n <> " は " <> typeName v)) {diagRelated = related}])
              (vals, ds) = foldMap one (Map.toList refs)
           in (Map.singleton fid (Map.fromList vals), ds)
        _ -> (Map.empty, [])
   in foldMap perFile (nub [(fid, name) | (fid, name) <- projectChapters project])

-- | How a file is referred to: by @figure, @table or @listing (golem-eval ADR 0004).
data AssetUse = UseImage | UseTable | UseListing
  deriving stock (Eq, Ord, Show)

-- | What 'loadAssets' read (golem-eval ADR 0004).
data LoadedAssets = LoadedAssets
  { laAssets :: !(Map FilePath Asset),
    -- | the files read as text, where their diagnostics point
    laSources :: !(Map FileId SourceInfo),
    -- | the reading stage of the table files: G0101 and G0282
    laDiagnostics :: ![Diagnostic],
    -- | the table files the last evaluation read, for the LSP to watch (golem-eval ADR 0004)
    laTableFiles :: !(Set.Set FilePath)
  }

{- | Files referenced by @figure, @table and @listing: text content for
tables and listings, presence for images, and why a path cannot be used
(golem-eval ADR 0003). A path any reference reads as text is read as
text, from @overlay@ when the editor has it open. Each file read as text
has a FileId, from the one after plugins.lock's, in the order of the paths
(golem-eval ADR 0004). A table file passes the reading stage of table
files ('readTableSource'); a listing is read as before.
-}
loadAssets :: Map FilePath Text -> FilePath -> Project -> IO LoadedAssets
loadAssets overlay root project = do
  let refs = Map.fromListWith Set.union [(p, Set.singleton u) | sf <- Map.elems (projectSources project), (p, u) <- assetRefs (sfAst sf)]
      FileId lock = lockFileId project
      textPaths = [p | (p, us) <- Map.toList refs, any (`Set.member` us) [UseTable, UseListing]]
      fids = Map.fromList (zip textPaths (map FileId [lock + 1 ..]))
  loaded <- Map.traverseWithKey (load fids) refs
  pure
    LoadedAssets
      { laAssets = Map.map (\(a, _, _, _) -> a) loaded,
        laSources = Map.fromList [s | (_, Just s, _, _) <- Map.elems loaded],
        laDiagnostics = concat [ds | (_, _, ds, _) <- Map.elems loaded],
        laTableFiles = Set.fromList [rel | (_, _, _, Just rel) <- Map.elems loaded]
      }
  where
    load fids path uses = do
      r <- resolveInRoot root path
      case (r, Map.lookup path fids) of
        (Left e, _) -> pure (AssetInvalid e, Nothing, [], Nothing)
        (Right rel, Just fid) -> do
          bytes <- maybe (BS.readFile (root </> rel)) (pure . TE.encodeUtf8) (Map.lookup rel overlay <|> Map.lookup path overlay)
          let source = Just (fid, readInfo rel bytes)
              lenient = TE.decodeUtf8Lenient bytes
          pure $
            if Set.member UseTable uses
              then case readTableSource fid bytes of
                Right t -> (AssetText fid t, source, [], Just rel)
                Left ds -> (AssetTableUnreadable fid lenient, source, ds, Just rel)
              else (AssetText fid lenient, source, [], Nothing)
        (Right _, Nothing) -> pure (AssetPresent, Nothing, [], Nothing)

-- | The paths a file refers to by @figure, @table and @listing, as written.
assetRefs :: A.File -> [(FilePath, AssetUse)]
assetRefs (A.File _ bs) = concatMap blk bs
  where
    blk (A.Located _ b) = case b of
      A.BlockCommand (A.Located _ name) args body -> cmd name args <> concatMap blk body
      A.Attributed cs t -> concatMap blk cs <> maybe [] blk t
      A.BulletList items -> concatMap (concatMap blk) items
      A.OrderedList items -> concatMap (concatMap blk) items
      A.DefList gs -> concatMap (concatMap (concatMap blk) . A.dgDefs) gs
      _ -> []
    cmd name args =
      let pos = [t | A.Located _ (A.Positional v) <- args, Just t <- [txt v]]
          kw k = [t | A.Located _ (A.Keyword (A.Located _ k') v) <- args, k' == k, Just t <- [txt v]]
       in case name of
            "figure" -> [(T.unpack p, UseImage) | p <- take 1 pos <> kw "web"]
            "table" -> [(T.unpack p, UseTable) | p <- kw "src"]
            "listing" -> [(T.unpack p, UseListing) | p <- take 1 pos <> kw "src"]
            _ -> []
    txt = \case
      A.Word t -> Just t
      A.StringLit t -> Just t
      _ -> Nothing

{- | CSL-JSON: G0326 and G0303 for the files of the bibliography that
cannot be read, the keys, and the entries formatted by golem-doc
(golem-doc ADR 0004). The diagnostics point at the head of manifest.toml,
FileId 0, as G0302 does, because the manifest keeps no positions.
-}
loadBibliography :: FilePath -> Manifest -> IO ([Diagnostic], Set.Set Text, Map Text Text)
loadBibliography root manifest = do
  results <- forM (manifestBibliography manifest) $ \p -> do
    res <- resolveInRoot root p
    case res of
      Left Missing -> pure (Left (unreadable ("参考文献のファイルがありません: " <> T.pack p)))
      Left e -> pure (Left (diagnostic "G0303" Error manifestHead (T.pack (pathErrorMessage e <> ": " <> p))))
      Right rel -> do
        r <- try (BL.readFile (root </> rel)) :: IO (Either SomeException BL.ByteString)
        pure $ case J.eitherDecode <$> r of
          Left _ -> Left (unreadable ("参考文献のファイルがありません: " <> T.pack p))
          Right (Left err) -> Left (unreadable ("参考文献のファイルを JSON として読めません: " <> T.pack p <> "（" <> T.pack err <> "）"))
          Right (Right (J.Array xs)) -> Right (mapMaybe cslEntry (V.toList xs))
          Right (Right _) -> Left (unreadable ("参考文献のファイルは CSL-JSON の配列で書きます: " <> T.pack p))
  let m = Map.fromList [(ceId c, formatEntry c) | c <- concat (rights results)]
  pure (lefts results, Map.keysSet m, m)
  where
    manifestHead = mkSpan (FileId 0) 0 0
    unreadable = diagnostic "G0326" Error manifestHead

-- | The fields of a CSL-JSON item that the bibliography shows; Nothing without a string id.
cslEntry :: J.Value -> Maybe CslEntry
cslEntry = \case
  J.Object o -> do
    J.String k <- KM.lookup "id" o
    pure
      CslEntry
        { ceId = k,
          ceLanguage = str "language" o,
          ceAuthors = case KM.lookup "author" o of
            Just (J.Array as) -> mapMaybe name (V.toList as)
            _ -> [],
          ceTitle = str "title" o,
          cePublisher = str "publisher" o,
          ceIssued = KM.lookup "issued" o >>= date
        }
  _ -> Nothing
  where
    str k o = case KM.lookup (JK.fromText k) o of
      Just (J.String s) -> Just s
      _ -> Nothing
    -- literal first; a name with neither family nor given is left out
    name = \case
      J.Object a -> case (str "literal" a, str "family" a, str "given" a) of
        (Just l, _, _) -> Just (LiteralName l)
        (_, Nothing, Nothing) -> Nothing
        (_, f, g) -> Just (PersonalName f g)
      _ -> Nothing
    -- the first number of the first date-parts, or else the literal
    date = \case
      J.Object i -> case KM.lookup "date-parts" i of
        Just (J.Array ps) | (J.Array y : _) <- V.toList ps, (J.Number n : _) <- V.toList y, Just yr <- cslYear n -> Just (DateYear yr)
        _ -> DateLiteral <$> str "literal" i
      _ -> Nothing

{- | The year of a CSL-JSON number (docs/adr ADR 0035): Nothing from 10^15
up, 0 below 0.1, and otherwise the number rounded. It is judged from the
coefficient and the exponent, so that 1e1000000000 does not become an
integer of a billion digits.
-}
cslYear :: Scientific -> Maybe Integer
cslYear n
  | c == 0 = Just 0
  | magnitude > 15 = Nothing
  | magnitude < 0 = Just 0
  | otherwise = Just (round n)
  where
    c = coefficient n
    magnitude = length (show (abs c)) + base10Exponent n

targetsOf :: Manifest -> [Target]
targetsOf m =
  let t = manifestTargets m
   in [TargetHtml | tgHtml t] <> [TargetEpub | isJust (tgEpub t)] <> [TargetText | not (null (tgText t))] <> [TargetPdf | isJust (tgPdf t)]

build :: BuildOptions -> IO BuildResult
build opts = fst <$> buildCore False opts

{- | The build; with @inMemory@, the PDF is not written but returned with
its view (golem preflight, golem-cli ADR 0006).
-}
buildCore :: Bool -> BuildOptions -> IO (BuildResult, Maybe (BS.ByteString, View))
buildCore inMemory opts = do
  ev <- evaluateProject (optProfile opts) (optRoot opts)
  case ev of
    Left f -> pure (BuildResult (finishWith Set.empty (pfDiagnostics f)) (pfSources f) [], Nothing)
    Right e -> do
      let project = evProject e
          finish = finishWith (manifestSilencedNotices (projectManifest project))
          targets = fromMaybe (targetsOf (projectManifest project)) (optTargets opts)
      hasStyle <- doesFileExist (optRoot opts </> "style.toml")
      let styleFid = evStyleFile e
          -- style.toml is a source of diagnostics (golem-project ADR 0004, G0702) when it exists
          infos =
            (if hasStyle then Map.insert styleFid (SourceInfo "style.toml" (mkLineIndex (evStyleText e))) else id)
              (withEvaluatedSources e (sourceInfos project))
          -- where diagnostics about style.toml point (golem-driver ADR 0016)
          diagFid = if hasStyle then styleFid else projectManifestFile project
          -- G0702, and what style.toml decides of the layout (G0701, G0725; golem-driver ADR 0016)
          marksDiags =
            cropMarkDiagnostics opts e diagFid targets
              <> (if TargetPdf `elem` targets then styleLayoutDiagnostics diagFid (isJust (markStyle (optMarks opts))) (evStyle e) (Map.elems (localStylesOf e)) else [])
      -- the files of style.toml, for the targets that use them (golem-project ADR 0004)
      missing <- missingStyleFiles (optRoot opts) (evStyle e)
      -- without code in the book, the role code is not used (golem-driver ADR 0017)
      let fileStyle = maybe id (\b -> codeStyles (bookHasCode (docStyles e) b) (stFonts (evStyle e))) (evBook e) (evStyle e)
          perTarget = [(t, map (adjustForProfile (optProfile opts)) (targetFileDiagnostics diagFid fileStyle (Map.elems (localStylesOf e)) missing t)) | t <- targets]
          fileDiags = nub (concatMap snd perTarget)
          -- G0701, G0702 and G0725 stop the PDF before it is laid out; the other targets are written
          writable = [t | (t, ds) <- perTarget, not (hasErrors ds), t /= TargetPdf || null marksDiags]
          -- the variables of the running heads, after S0, only for the PDF (golem-driver ADR 0022)
          evDiags = evDiagnostics e <> (if TargetPdf `elem` targets then snd (runningVars e) else [])
      case evBook e of
        Just book
          | not (hasErrors (finish evDiags)) && not (optCheckOnly opts) -> do
              -- a list number its format cannot write stops every target (golem-driver ADR 0013)
              let listDiags = listNumberDiagnostics (evStyle e) (maybe False pageVertical (stPage (evStyle e))) book
              (written, outDiags, pdf) <-
                if null listDiags || null writable
                  then writeTargets inMemory opts e diagFid book missing writable
                  else pure ([], listDiags, Nothing)
              pure (BuildResult (finish (evDiags <> fileDiags <> marksDiags <> outDiags)) infos written, pdf)
        _ -> pure (BuildResult (finish (evDiags <> fileDiags <> marksDiags)) infos [], Nothing)
  where
    -- the profile, then the notices silenced by the manifest or by --no-notices (golem-syntax ADR 0002)
    finishWith silenced = sortDiagnostics . silenceNotices (if optNoNotices opts then Nothing else Just silenced) . map (adjustForProfile (optProfile opts))

data PreflightOptions = PreflightOptions
  { poRoot :: !FilePath,
    -- | --rules: from the working directory, or absolute; preflight.toml of the root without it
    poRules :: !(Maybe FilePath),
    poMarks :: !CropMarks,
    poFonts :: !FontProvider,
    poParallel :: !Bool
  }

defaultPreflightOptions :: FilePath -> PreflightOptions
defaultPreflightOptions root = PreflightOptions root Nothing NoMarks golemFontProvider True

data PreflightResult = PreflightResult
  { prDiagnostics :: ![Diagnostic],
    prSources :: !(Map FileId SourceInfo),
    -- | the PDF checked, when one was made
    prPdf :: !(Maybe BS.ByteString),
    prView :: !(Maybe View),
    -- | the rules as the summary names them: their name, their file, or the built-in print
    prRulesLabel :: !Text,
    prBasedOn :: !Text
  }

{- | golem preflight (golem-cli ADR 0006): the rules first (G0901 stops
here), then the PDF as golem build --target pdf --profile prod makes it,
kept in memory, then the checks of the rules on its view.
-}
preflight :: PreflightOptions -> IO PreflightResult
preflight po = do
  let path = fromMaybe (poRoot po </> "preflight.toml") (poRules po)
      rulesFid = FileId 0
  exists <- doesFileExist path
  rulesE <-
    if not exists
      then
        pure $
          if isJust (poRules po)
            then Left ([diagnostic "G0901" Error (mkSpan rulesFid 0 0) ("プリフライトの設定のファイルがありません: " <> T.pack path)], "")
            else Right (printRules, "組み込みの print")
      else do
        bytes <- BS.readFile path
        pure $ case TE.decodeUtf8' bytes of
          Left _ -> Left ([diagnostic "G0901" Error (mkSpan rulesFid 0 0) ("プリフライトの設定のファイルが UTF-8 として読めません: " <> T.pack path)], "")
          Right src -> case parseRules rulesFid src of
            Left ds -> Left (ds, src)
            Right r -> Right (r, fromMaybe (T.pack (takeFileName path)) (ruName r))
  case rulesE of
    Left (ds, src) -> pure (PreflightResult (sortDiagnostics ds) (Map.singleton rulesFid (SourceInfo path (mkLineIndex src))) Nothing Nothing "" "")
    Right (rules, label) -> do
      let opts = (defaultOptions (poRoot po)) {optTargets = Just [TargetPdf], optProfile = Prod, optMarks = poMarks po, optFonts = poFonts po, optParallel = poParallel po}
      (r, pdf) <- buildCore True opts
      let checks = maybe [] (check rules . snd) pdf
      pure (PreflightResult (sortDiagnostics (brDiagnostics r <> checks)) (brSources r) (fst <$> pdf) (snd <$> pdf) label (ruBasedOn rules))

-- | Files of style.toml that cannot be used: path -> why (resolveInRoot).
missingStyleFiles :: FilePath -> Style -> IO (Map FilePath PathError)
missingStyleFiles root style = do
  let paths = nub (map snd (fontFiles style) <> maybe [] pure (stIntent style))
  resolved <- forM paths $ \p -> (p,) <$> resolveInRoot root p
  pure (Map.fromList [(p, err) | (p, Left err) <- resolved])

{- | Diagnostics of the missing files for one target (golem-project ADR
0004): the fonts the PDF uses and its output intent (errors), every font
for HTML and EPUB (warnings, errors in prod), nothing for plain text.
The PDF also needs a body font with a file (G0807, golem-driver ADR 0016).
-}
targetFileDiagnostics :: FileId -> Style -> [LocalStyles] -> Map FilePath PathError -> Target -> [Diagnostic]
targetFileDiagnostics fid style locals missing = \case
  TargetPdf ->
    bodyFontDiagnostics fid style
      <> report "G0802" Error "フォントのファイルがありません" pdfFonts
      <> report "G0806" Error "出力インテントの ICC プロファイルがありません" (maybe [] pure (stIntent style))
  TargetHtml -> siteFonts
  TargetEpub -> siteFonts
  TargetText -> []
  where
    pdfFonts = [p | r <- usedRoles style locals, Just (FontRole ja la _) <- [Map.lookup r (stFonts style)], Just p <- [ja, la]]
    siteFonts = report "G0310" Warning "フォントのファイルがないので、HTML と EPUB に同梱しません" (map snd (fontFiles style))
    report code sev missingMsg paths =
      [ diagnostic code sev (mkSpan fid 0 0) (T.pack (msg <> ": " <> p))
      | p <- nub paths,
        Just err <- [Map.lookup p missing],
        let msg = if err == Missing then missingMsg else pathErrorMessage err
      ]

{- | G0702 (golem-pdf ADR 0004): Japanese crop marks need bleed, because the
trim line and the bleed line would be drawn on top of each other. Only when
the PDF is a target; at the top of style.toml (or of the manifest without
one), as Style keeps no positions.
-}
cropMarkDiagnostics :: BuildOptions -> Evaluated -> FileId -> [Target] -> [Diagnostic]
cropMarkDiagnostics opts e fid targets =
  [ diagnostic "G0702" Error (mkSpan fid 0 0) "日本式のトンボには塗り足しが要ります。style.toml の [page] に bleed を書いてください"
  | optMarks opts == JapaneseMarks,
    TargetPdf `elem` targets,
    maybe 0 pageBleed (stPage (evStyle e)) == 0
  ]

-- | The crop marks of golem-pdf.
markStyle :: CropMarks -> Maybe P.MarkStyle
markStyle = \case
  NoMarks -> Nothing
  JapaneseMarks -> Just P.Japanese
  WesternMarks -> Just P.Western

{- | The options that change the output, as one input of the instance ID
(golem-pdf ADR 0004), spelt as on the command line. --target and --format
do not change the bytes of the PDF and are left out.
-}
optionsInput :: BuildOptions -> Text
optionsInput opts =
  "options marks="
    <> (case optMarks opts of NoMarks -> "none"; JapaneseMarks -> "japanese"; WesternMarks -> "western")
    <> " profile="
    <> (case optProfile opts of Dev -> "dev"; Prod -> "prod")

{- | Writes the targets, after G0813 (docs/adr ADR 0035): @build@ and the
folder of each target that is written must be real folders or missing, not
symbolic links nor other files, or nothing is removed nor written.
-}
writeTargets :: Bool -> BuildOptions -> Evaluated -> FileId -> Book -> Map FilePath PathError -> [Target] -> IO ([FilePath], [Diagnostic], Maybe (BS.ByteString, View))
writeTargets inMemory opts e diagFid book missing targets = do
  let written = [t | t <- targets, not (inMemory && t == TargetPdf)]
  unsafe <- if null written then pure [] else unsafeOutputDirs (optRoot opts) written
  case unsafe of
    [] -> writeTargetsChecked inMemory opts e diagFid book missing targets
    ps -> pure ([], [diagnostic "G0813" Error (mkSpan diagFid 0 0) ("出力先がシンボリックリンクかディレクトリではないので、消すことも書くこともしません: " <> T.pack p) | p <- ps], Nothing)

{- | The output folders, relative to the root, that are symbolic links (to
anywhere, or nowhere) or files that are not folders: @build@ and the folder
of each target.
-}
unsafeOutputDirs :: FilePath -> [Target] -> IO [FilePath]
unsafeOutputDirs root targets = filterM unsafe ("build" : nub (map targetDir targets))
  where
    targetDir = \case
      TargetHtml -> "build/html"
      TargetEpub -> "build/epub"
      TargetText -> "build/text"
      TargetPdf -> "build/pdf"
    unsafe rel = do
      let p = root </> rel
      link <- fromRight False <$> (try (pathIsSymbolicLink p) :: IO (Either SomeException Bool))
      if link then pure True else doesFileExist p

writeTargetsChecked :: Bool -> BuildOptions -> Evaluated -> FileId -> Book -> Map FilePath PathError -> [Target] -> IO ([FilePath], [Diagnostic], Maybe (BS.ByteString, View))
writeTargetsChecked inMemory opts e diagFid book missing targets = do
  let root = optRoot opts
      project = evProject e
      style = evStyle e
      manifest = projectManifest project
      md = manifestMetadata manifest
      ft = projectFiles project
      dev = optProfile opts == Dev
      vertical = maybe False pageVertical (stPage style)
  (_, _, bib) <- loadBibliography root manifest
  let hcfg =
        HtmlConfig
          { hcTitle = mdTitle md,
            hcLanguage = mdLanguage md,
            hcVertical = vertical,
            hcNumberDefault = stNumbersVertical style,
            hcSwatches = Map.map (\(Swatch c) -> c) (stSwatches style),
            -- missing fonts are left out of the site (golem-project ADR 0004)
            hcFonts = Map.map (\fr -> (present (frJa fr), present (frLatin fr))) (stFonts style),
            -- the resolved styles (docs/adr ADR 0005)
            hcCharStyles = htmlCharStyles style,
            hcParaStyles = htmlParaStyles style,
            -- the styles of each file that differ from those of style.toml (docs/adr ADR 0014)
            hcLocalStyles =
              Map.fromList
                [ ( fid,
                    HtmlLocalStyles
                      { hlCharStyles = Map.differenceWith changed (htmlCharStyles st) (htmlCharStyles style),
                        hlParaStyles = Map.differenceWith changed (htmlParaStyles st) (htmlParaStyles style),
                        hlCaptionFace = mfilter (/= captionFace style) (Just (captionFace st)),
                        hlSidenoteFace = mfilter (/= sidenoteFace style) (Just (sidenoteFace st))
                      }
                  )
                | fid <- Map.keys (localStylesOf e),
                  let st = docStyles e fid
                ],
            hcBibliography = bib,
            hcDev = dev,
            hcCaptionFace = captionFace style,
            hcSidenoteFace = sidenoteFace style,
            hcRubyMonoAlign = rubyAlignCss (rdMonoAlign ruby),
            hcRubyGroupAlign = rubyAlignCss (rdGroupAlign ruby),
            hcRubyBaseSpacing = rubyAlignCss (rdBaseSpacing ruby),
            hcBreakKinds = Set.fromList [k | Document _ bs <- bookDocs book, Block _ _ (ForcedBreak k) <- bs],
            -- only a book with [lists] changes the markers (golem-driver ADR 0013)
            -- the paragraph style code for pre (golem-driver ADR 0017)
            hcCode =
              let d = paraStyle style (Just "code")
               in HtmlCode
                    { hcoFont = d >>= psFont,
                      hcoSize = cssFontSize style <$> (d >>= psSize),
                      hcoBackground = d >>= psBackground,
                      hcoPadding = cssLength (fromMaybe (Zw 0.5) (d >>= psPadding)),
                      -- the border and [code] (golem-driver ADR 0023)
                      hcoBorder = d >>= psBorder,
                      hcoBorderWidth = cssLength (fromMaybe (Abs 16384) (d >>= psBorderWidth)),
                      hcoLineNumbers = cdLineNumbers (stCode style),
                      hcoLineNumberColor = cdLineNumberColor (stCode style),
                      hcoHighlight = cdHighlight (stCode style),
                      hcoAdded = cdAdded (stCode style),
                      hcoRemoved = cdRemoved (stCode style),
                      hcoColors = cdColors (stCode style)
                    },
            hcLists =
              if stLists style == defaultListStyle
                then Nothing
                else Just (HtmlLists (lsBullets (stLists style)) (fromMaybe (pure (defaultNumberFormat vertical)) (lsNumbers (stLists style))) (GT.tlGap (textLists style)))
          }
      present = mfilter (`Map.notMember` missing)
      changed a b = if a == b then Nothing else Just a
      captionFace st = let c = paraStyle st (Just "caption") in Face (c >>= psFont) (cssFontSize st <$> (c >>= psSize))
      sidenoteFace st = let d = paraStyle st (Just "sidenote") in Face (d >>= psFont) (cssFontSize st <$> (d >>= psSize))
      ruby = compRuby (stComposition style)
      site = renderXhtml hcfg ft book
  results <- forM targets $ \case
    TargetHtml -> do
      let dir = root </> "build" </> "html"
      clean dir
      forM_ (sitePages site) $ \(p, t) -> writeText (dir </> p) t
      writeText (dir </> "style.css") (siteCss site)
      writeText (dir </> "index.xhtml") (indexPage hcfg ft book)
      copied <- forM (siteAssets site) $ \(o, src) -> copy (root </> src) (dir </> o) >> pure (dir </> o)
      pure (map ((dir </>) . fst) (sitePages site) <> [dir </> "style.css", dir </> "index.xhtml"] <> copied, [], Nothing)
    TargetEpub -> do
      let dir = root </> "build" </> "epub"
          out = dir </> "book.epub"
          isbn = fromMaybe Nothing (tgEpub (manifestTargets manifest))
          cfg =
            EpubConfig
              { epIdentifier = maybe (mdId md) ("urn:isbn:" <>) isbn,
                epTitle = mdTitle md,
                epTitleReading = mdTitleReading md,
                epLanguage = mdLanguage md,
                epDate = mdDate md,
                epPublisher = mdPublisher md,
                epCreators = [EpubCreator (crName c) (crReading c) (crRole c) | c <- mdCreators md],
                epVertical = vertical
              }
      clean dir
      createDirectoryIfMissing True dir
      writeEpub root out cfg ft book site
      pure ([out], [], Nothing)
    TargetText -> do
      let dir = root </> "build" </> "text"
          -- without [targets.text], both variants, as when variants is omitted (golem-cli ADR 0002)
          variants = case tgText (manifestTargets manifest) of
            [] -> [TextVertical, TextHorizontal]
            vs -> vs
      clean dir
      files <- forM variants $ \v -> do
        let (sub, gv) = case v of
              TextVertical -> ("vertical", GT.Vertical)
              TextHorizontal -> ("horizontal", GT.Horizontal)
        -- each document with the indents of its style (docs/adr ADR 0014)
        let pages = concat [GT.renderText (mdLanguage md) (stNumbersVertical style) dev (textFirstLine (docStyles e fid)) (textLists style) bib gv ft book {bookDocs = [d]} | d@(Document fid _) <- bookDocs book]
        forM pages $ \(p, t) -> do
          writeText (dir </> sub </> p) t
          pure (dir </> sub </> p)
      pure (concat files, [], Nothing)
    TargetPdf -> do
      let dir = root </> "build" </> "pdf"
          out = dir </> pdfFileName (mdId md)
          -- the manifest, style.toml, the sources and the options that change the output (golem-pdf ADR 0004)
          inputs = projectManifestText project : evStyleText e : [sfText sf | sf <- Map.elems (projectSources project)] <> [optionsInput opts]
      r <- renderPdfView (optFonts opts) (PdfInput root project style book (optParallel opts) (map TE.encodeUtf8 inputs) bib (markStyle (optMarks opts)) (localStylesOf e) (Map.fromList [(fid, m) | (fid, Just m) <- projectChapters project]) diagFid (fst (runningVars e)))
      -- G0808: code in the body role without [fonts.code] (golem-driver ADR 0017)
      -- G0745: kenten the PDF does not draw, with ruby (golem-driver ADR 0019)
      let fontNotice = codeFontNotice diagFid style book <> kentenRubyNotices book
      case r of
        Left ds -> pure ([], ds <> fontNotice, Nothing)
        Right (bytes, notices, view)
          -- golem preflight keeps the PDF in memory (golem-cli ADR 0006)
          | inMemory -> pure ([], notices <> fontNotice, Just (bytes, view))
          | otherwise -> do
              clean dir
              createDirectoryIfMissing True dir
              BS.writeFile out bytes
              pure ([out], notices <> fontNotice, Nothing)
  pure (concat [w | (w, _, _) <- results], concat [d | (_, d, _) <- results], listToMaybe [x | (_, _, Just x) <- results])
  where
    clean dir = do
      ex <- doesDirectoryExist dir
      when ex (removeDirectoryRecursive dir)
    -- UTF-8 whatever the locale (docs/adr/0002-determinism.md)
    writeText p t = createDirectoryIfMissing True (takeDirectory p) >> BS.writeFile p (TE.encodeUtf8 t)
    copy src dst = createDirectoryIfMissing True (takeDirectory dst) >> BS.readFile src >>= BS.writeFile dst

{- | The markers of [lists] in plain text (golem-driver ADR 0013): a gap is
written when [lists] gap is not 0, or by the last character without it.
-}
textLists :: Style -> GT.TextLists
textLists style =
  let l = stLists style
      nonZero = \case
        Abs x -> x /= 0
        Zw r -> r /= 0
   in GT.TextLists (lsBullets l) (lsNumbers l) (nonZero <$> lsGap l)

-- | The character styles of a style, resolved for CSS (docs/adr ADR 0005).
htmlCharStyles :: Style -> Map Text HtmlCharStyle
htmlCharStyles style =
  Map.fromList
    [ (n, HtmlCharStyle (csFont d) (csSyntheticBold d == Just True) (csSyntheticItalic d == Just True) (csColor d) (htmlFeatures (csKerning d) (csTracking d) (csProportional d) (csBaselineShift d)) (isCodeCharStyle style n))
    | n <- Map.keys (stCharStyles style),
      Just d <- [charStyle style n]
    ]

-- | The paragraph styles of a style, resolved for CSS (docs/adr ADR 0005, 0006).
htmlParaStyles :: Style -> Map Text HtmlParaStyle
htmlParaStyles style =
  Map.fromList
    [ ( n,
        HtmlParaStyle
          (psFont d)
          (psLineBreaks d == Just KeepLines)
          (fromMaybe 0 (psSpaceBetween d))
          (cssLength (fromMaybe (Zw 0) (psIndent d)))
          (cssLength (fromMaybe (Zw 0) (psFirstLineIndent d)))
          (htmlFeatures (psKerning d) (psTracking d) (psProportional d) (psBaselineShift d))
      )
    | n <- Map.keys (stParaStyles style),
      Just d <- [paraStyle style (Just n)]
    ]

-- | The keys of the spacing of characters for CSS (docs/adr/0020).
htmlFeatures :: Maybe Kerning -> Maybe Int -> Maybe Bool -> Maybe Dim -> HtmlFeatures
htmlFeatures k t p b =
  HtmlFeatures
    { hfKerning =
        k >>= \case
          KernMetrics -> Just "metrics"
          KernJapaneseEqualWidth -> Just "japanese-equal-width"
          KernNone -> Just "none"
          KernOptical -> Nothing,
      hfTracking = t,
      hfProportional = p,
      hfBaselineShift = cssLength <$> b
    }

{- | The ideographic spaces that start the lines of a paragraph of a style
in plain text (docs/adr ADR 0006): the whole part of indent plus
first-line-indent when both are in zw, none otherwise.
-}
textFirstLine :: Style -> Maybe Text -> Int
textFirstLine style st = case paraStyle style st of
  Just ParaStyleDef {psIndent = Just (Zw a), psFirstLineIndent = Just (Zw b)} -> max 0 (truncate (a + b))
  _ -> 0

-- | A ruby alignment of style.toml as a CSS ruby-align value (golem-layout ADR 0009).
rubyAlignCss :: Text -> Text
rubyAlignCss = \case
  "1:2:1" -> "space-around"
  "0:1:0" -> "space-between"
  "start" -> "start"
  _ -> "center"

{- | A length of style.toml in CSS: zw as em, other units as pt, with at
most three decimals (docs/adr ADR 0003).
-}
cssLength :: Dim -> Text
cssLength = \case
  Zw r -> decimal3 r <> "em"
  Abs sp -> decimal3 (toRational sp / 65536) <> "pt"

{- | A size of style.toml as a CSS font-size (golem-driver ADR 0010): zw as
em, an absolute size as its ratio to an absolute grid size in em, pt
without one.
-}
cssFontSize :: Style -> Dim -> Text
cssFontSize style = \case
  Zw r -> decimal3 r <> "em"
  Abs sp -> case stPage style >>= pageGrid of
    Just Grid {gridFontSize = Abs fs} | fs > 0 -> decimal3 (toRational sp / toRational fs) <> "em"
    _ -> cssLength (Abs sp)

-- | At most three decimals, fixed (docs/adr ADR 0003).
decimal3 :: Rational -> Text
decimal3 r =
  let thousandths = round (r * 1000) :: Integer
      (i, f) = abs thousandths `divMod` 1000
      sign = if thousandths < 0 then "-" else ""
      frac = T.dropWhileEnd (== '0') (T.justifyRight 3 '0' (T.pack (show f)))
   in sign <> T.pack (show i) <> (if T.null frac then "" else "." <> frac)

-- | The table of contents page of the HTML target.
indexPage :: HtmlConfig -> FileTable -> Book -> Text
indexPage cfg ft book =
  let items =
        T.concat
          [ "<li class=\"toc-"
              <> T.pack (show (teLevel te))
              <> "\"><a href=\""
              <> escapeXml (T.pack (pagePath ft (teFile te)))
              <> "#"
              <> escapeXml (teAnchor te)
              <> "\">"
              <> maybe "" (\n -> escapeXml (n <> numberSeparator (hcLanguage cfg) n)) (teNumber te)
              <> escapeXml (T.concat (map inlineText (teTitle te)))
              <> "</a></li>\n"
          | te <- bookToc book
          ]
   in T.concat
        [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"",
          escapeXml (hcLanguage cfg),
          "\" xml:lang=\"",
          escapeXml (hcLanguage cfg),
          "\">\n<head>\n<meta charset=\"UTF-8\"/>\n<title>",
          escapeXml (hcTitle cfg),
          "</title>\n<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/>\n</head>\n<body>\n<h1>",
          escapeXml (hcTitle cfg),
          "</h1>\n<nav class=\"toc\">\n<ol>\n",
          items,
          "</ol>\n</nav>\n</body>\n</html>\n"
        ]
