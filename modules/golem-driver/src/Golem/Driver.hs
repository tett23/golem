{- | The build pipeline (golem-driver ADR 0001): project → parse → S0 → S1
→ outputs. PDF (S2 and later) is added by golem-driver ADR 0002.
-}
module Golem.Driver
  ( Target (..),
    BuildOptions (..),
    defaultOptions,
    BuildResult (..),
    build,
    evaluateProject,
    evaluateProjectWith,
    Evaluated (..),
    sourceInfos,
    FontProvider (..),
    LoadedFonts (..),
    noFontProvider,
  )
where

import Control.Exception (SomeException, try)
import Control.Monad (forM, forM_, when)
import Data.Aeson qualified as J
import Data.Aeson.Key qualified as JK
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, mapMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Vector qualified as V
import Golem.Doc.Assemble
import Golem.Doc.IR
import Golem.Driver.Fonts (golemFontProvider)
import Golem.Driver.Pdf
import Golem.Driver.Plugins (loadPlugins)
import Golem.Epub
import Golem.Eval.Expr (Env (..), embedValue, evalExpr)
import Golem.Eval.File
import Golem.Eval.Value
import Golem.Html
import Golem.Parser.AST qualified as A
import Golem.Plugin.Lock (defaultCacheDir)
import Golem.Project
import Golem.Project.Paths (resolveInRoot)
import Golem.Project.Style
import Golem.Syntax
import Golem.Text qualified as GT
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, removeDirectoryRecursive)
import System.FilePath (takeDirectory, (</>))

data Target = TargetHtml | TargetEpub | TargetText | TargetPdf
  deriving stock (Eq, Ord, Show)

data BuildOptions = BuildOptions
  { optRoot :: !FilePath,
    optTargets :: !(Maybe [Target]),
    optProfile :: !Profile,
    optCheckOnly :: !Bool,
    -- | where fonts come from (golem-font; see Golem.Driver.Pdf)
    optFonts :: !FontProvider,
    -- | break paragraphs in parallel (the PDF is the same either way)
    optParallel :: !Bool
  }

defaultOptions :: FilePath -> BuildOptions
defaultOptions root = BuildOptions root Nothing Dev False golemFontProvider True

data BuildResult = BuildResult
  { brDiagnostics :: ![Diagnostic],
    brSources :: !(Map FileId SourceInfo),
    brWritten :: ![FilePath]
  }

data Evaluated = Evaluated
  { evProject :: !Project,
    evStyle :: !Style,
    evResults :: !(Map FileId EvalResult),
    evBook :: !(Maybe Book),
    evDiagnostics :: ![Diagnostic],
    {- | S0 of one file again, in the context of the last evaluation
    (the LSP re-evaluates the edited file alone when nothing that other
    files depend on has changed).
    -} evReevaluate :: FileId -> SourceFile -> EvalResult
  }

-- | Line indexes for rendering diagnostics.
sourceInfos :: Project -> Map FileId SourceInfo
sourceInfos p =
  Map.insert (projectManifestFile p) (SourceInfo "manifest.toml" (mkLineIndex (projectManifestText p))) $
    Map.map (\sf -> SourceInfo (sfPath sf) (mkLineIndex (sfText sf))) (projectSources p)

-- | Everything up to S1. Stops after a stage that produced errors.
evaluateProject :: Profile -> FilePath -> IO (Either [Diagnostic] Evaluated)
evaluateProject = evaluateProjectWith Map.empty

-- | @overlay@ replaces file contents (unsaved edits in the LSP).
evaluateProjectWith :: Map FilePath Text -> Profile -> FilePath -> IO (Either [Diagnostic] Evaluated)
evaluateProjectWith overlay profile root = do
  lp <- loadProjectWith overlay root
  case lp of
    Left ds -> pure (Left ds)
    Right project -> do
      let synDiags = concatMap sfSyntaxDiagnostics (Map.elems (projectSources project))
          manifest0 = projectManifest project
          styleFid = FileId (length (fileTableEntries (projectFiles project)))
      styleText <- readMaybeText (root </> "style.toml")
      estyle <- loadStyle (\p -> doesFileExist (root </> p)) styleFid styleText
      case estyle of
        Left ds -> pure (Left ds)
        Right style
          | hasErrors synDiags -> do
              assets <- loadAssets root project
              (citeKeys, _) <- loadBibliography root manifest0
              pure (Right (Evaluated project style Map.empty Nothing synDiags (reeval profile project style assets citeKeys noPlugins Map.empty)))
          | otherwise -> do
              let manifest = manifest0
                  masterDiags =
                    [ diagnostic "G0307" Error (mkSpan (projectManifestFile project) 0 0) ("style.toml にないマスターページです: " <> m)
                    | (_, Just m) <- projectChapters project,
                      not (Map.member m (stMasters style))
                    ]
              cacheDir <- defaultCacheDir
              hookE <- loadPlugins root cacheDir (projectManifestFile project) manifest
              let (pluginDiags, hook) = either (,noPlugins) ([],) hookE
              assets <- loadAssets root project
              (citeKeys, _) <- loadBibliography root manifest
              let results = evalAll profile project style assets citeKeys hook
                  s0Diags = concatMap erDiagnostics (Map.elems results)
                  chapterDocs = [erDocument r | (fid, _) <- projectChapters project, Just r <- [Map.lookup fid results]]
                  cfg = AssembleConfig (Map.mapMaybe hsNumber (stHeadings style)) (stFigureNumber style)
                  pre = masterDiags <> pluginDiags <> s0Diags
                  again = reeval profile project style assets citeKeys hook results
              if hasErrors pre
                then pure (Right (Evaluated project style results Nothing pre again))
                else do
                  let (book, s1Diags) = assemble cfg evalDeferred chapterDocs
                  pure (Right (Evaluated project style results (Just book) (pre <> s1Diags) again))

readMaybeText :: FilePath -> IO (Maybe Text)
readMaybeText p = do
  e <- doesFileExist p
  if e then Just . TE.decodeUtf8Lenient <$> BS.readFile p else pure Nothing

evalDeferred :: DocValues -> DeferredExpr -> Either Diagnostic Text
evalDeferred dv (DeferredExpr e) =
  let docNs = Map.fromList [("chapters", VHash (Map.fromList [("count", VInt (dvChapterCount dv))]))]
      en = Env Map.empty (Map.singleton "doc" docNs)
   in evalExpr en e >>= embedValue (A.locSpan e)

-- | Evaluates files in import order so that imports see their exports.
evalAll :: Profile -> Project -> Style -> Map FilePath (Maybe Text) -> Set.Set Text -> PluginHook -> Map FileId EvalResult
evalAll profile project style assets citeKeys hook = foldl' step Map.empty (projectOrder project)
  where
    step acc fid = case Map.lookup fid (projectSources project) of
      Nothing -> acc
      Just sf -> Map.insert fid (reeval profile project style assets citeKeys hook acc fid sf) acc

-- | S0 of one file, with the exports of its imports taken from @acc@.
reeval :: Profile -> Project -> Style -> Map FilePath (Maybe Text) -> Set.Set Text -> PluginHook -> Map FileId EvalResult -> FileId -> SourceFile -> EvalResult
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
            ctxDefaultKenten = compKenten (stComposition style),
            ctxCiteKeys = citeKeys,
            ctxAssets = assets,
            ctxPlugins = hook
          }
   in evalFile ctx (sfAst sf)

metadataValues :: Metadata -> Map Text Value
metadataValues md =
  Map.fromList $
    [ ("id", VString (mdId md)),
      ("title", VString (mdTitle md)),
      ("language", VString (mdLanguage md)),
      ("date", VString (T.pack (show (mdDate md)))),
      ("creators", VArray [VString (crName c) | c <- mdCreators md])
    ]
      <> [("title_reading", VString r) | Just r <- [mdTitleReading md]]
      <> [("edition", VString e) | Just e <- [mdEdition md]]
      <> [("publisher", VString p) | Just p <- [mdPublisher md]]

{- | Files referenced by @figure, @table and @listing: text content for
tables and listings, presence for images.
-}
loadAssets :: FilePath -> Project -> IO (Map FilePath (Maybe Text))
loadAssets root project = do
  let refs = concatMap (assetRefs . sfAst) (Map.elems (projectSources project))
  found <- forM refs $ \(path, wantText) -> do
    r <- resolveInRoot root path
    case r of
      Left _ -> pure Nothing
      Right rel ->
        if wantText
          then Just . (path,) . Just . TE.decodeUtf8Lenient <$> BS.readFile (root </> rel)
          else pure (Just (path, Nothing))
  pure (Map.fromList (catMaybes found))

assetRefs :: A.File -> [(FilePath, Bool)]
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
            "figure" -> [(T.unpack p, False) | p <- take 1 pos <> kw "web"]
            "table" -> [(T.unpack p, True) | p <- kw "src"]
            "listing" -> [(T.unpack p, True) | p <- take 1 pos <> kw "src"]
            _ -> []
    txt = \case
      A.Word t -> Just t
      A.StringLit t -> Just t
      _ -> Nothing

-- | CSL-JSON: keys, and entries formatted in the single built-in style.
loadBibliography :: FilePath -> Manifest -> IO (Set.Set Text, Map Text Text)
loadBibliography root manifest = do
  entries <- forM (manifestBibliography manifest) $ \p -> do
    r <- try (BL.readFile (root </> p)) :: IO (Either SomeException BL.ByteString)
    pure $ case r of
      Right bytes -> case J.eitherDecode bytes of
        Right (J.Array xs) -> mapMaybe entry (V.toList xs)
        _ -> []
      Left _ -> []
  let m = Map.fromList (concat entries)
  pure (Map.keysSet m, m)
  where
    entry = \case
      J.Object o -> do
        J.String k <- KM.lookup "id" o
        let str key = case KM.lookup (JK.fromText key) o of
              Just (J.String s) -> Just s
              _ -> Nothing
            authors = case KM.lookup "author" o of
              Just (J.Array as) -> T.intercalate ", " [nameOf a | a <- V.toList as]
              _ -> ""
            year = case KM.lookup "issued" o of
              Just (J.Object i) -> case KM.lookup "date-parts" i of
                Just (J.Array ps) -> case V.toList ps of
                  (J.Array y : _) -> case V.toList y of
                    (J.Number n : _) -> T.pack (show (round n :: Integer))
                    _ -> ""
                  _ -> ""
                _ -> ""
              _ -> ""
            parts = filter (not . T.null) [authors, fromMaybe "" (str "title"), fromMaybe "" (str "publisher"), year]
        pure (k, T.intercalate ". " parts <> ".")
      _ -> Nothing
    nameOf = \case
      J.Object a -> T.strip (fromMaybe "" (txt "family" a) <> " " <> fromMaybe "" (txt "given" a))
      _ -> ""
    txt k a = case KM.lookup k a of
      Just (J.String s) -> Just s
      _ -> Nothing

targetsOf :: Manifest -> [Target]
targetsOf m =
  let t = manifestTargets m
   in [TargetHtml | tgHtml t] <> [TargetEpub | isJust (tgEpub t)] <> [TargetText | not (null (tgText t))] <> [TargetPdf | isJust (tgPdf t)]

build :: BuildOptions -> IO BuildResult
build opts = do
  ev <- evaluateProject (optProfile opts) (optRoot opts)
  case ev of
    Left ds -> pure (BuildResult (finish ds) Map.empty [])
    Right e -> do
      let project = evProject e
          infos = sourceInfos project
      case evBook e of
        Just book
          | not (hasErrors (finish (evDiagnostics e))) && not (optCheckOnly opts) -> do
              let manifest = projectManifest project
                  targets = fromMaybe (targetsOf manifest) (optTargets opts)
              (written, outDiags) <- writeTargets opts e book targets
              pure (BuildResult (finish (evDiagnostics e <> outDiags)) infos written)
        _ -> pure (BuildResult (finish (evDiagnostics e)) infos [])
  where
    finish = sortDiagnostics . map (adjustForProfile (optProfile opts))

writeTargets :: BuildOptions -> Evaluated -> Book -> [Target] -> IO ([FilePath], [Diagnostic])
writeTargets opts e book targets = do
  let root = optRoot opts
      project = evProject e
      style = evStyle e
      manifest = projectManifest project
      md = manifestMetadata manifest
      ft = projectFiles project
      dev = optProfile opts == Dev
      vertical = maybe False pageVertical (stPage style)
  (_, bib) <- loadBibliography root manifest
  let hcfg =
        HtmlConfig
          { hcTitle = mdTitle md,
            hcLanguage = mdLanguage md,
            hcVertical = vertical,
            hcNumberDefault = stNumbersVertical style,
            hcStrongAs = stStrongAs style,
            hcSwatches = Map.map (\(Swatch c) -> c) (stSwatches style),
            hcCharStyles = Map.map csFont (stCharStyles style),
            hcFonts = Map.map (\fr -> (frJa fr, frLatin fr)) (stFonts style),
            hcBibliography = bib,
            hcDev = dev
          }
      site = renderXhtml hcfg ft book
  results <- forM targets $ \case
    TargetHtml -> do
      let dir = root </> "build" </> "html"
      clean dir
      forM_ (sitePages site) $ \(p, t) -> writeText (dir </> p) t
      writeText (dir </> "style.css") (siteCss site)
      writeText (dir </> "index.xhtml") (indexPage hcfg ft book)
      copied <- forM (siteAssets site) $ \(o, src) -> copy (root </> src) (dir </> o) >> pure (dir </> o)
      pure (map ((dir </>) . fst) (sitePages site) <> [dir </> "style.css", dir </> "index.xhtml"] <> copied, [])
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
      pure ([out], [])
    TargetText -> do
      let dir = root </> "build" </> "text"
          variants = tgText (manifestTargets manifest)
      clean dir
      files <- forM variants $ \v -> do
        let (sub, gv) = case v of
              TextVertical -> ("vertical", GT.Vertical)
              TextHorizontal -> ("horizontal", GT.Horizontal)
        forM (GT.renderText (stNumbersVertical style) dev gv ft book) $ \(p, t) -> do
          writeText (dir </> sub </> p) t
          pure (dir </> sub </> p)
      pure (concat files, [])
    TargetPdf -> do
      let dir = root </> "build" </> "pdf"
          out = dir </> pdfFileName (mdId md)
          inputs = projectManifestText project : [sfText sf | sf <- Map.elems (projectSources project)]
      r <- renderPdf (optFonts opts) (PdfInput root project style book (optParallel opts) (map TE.encodeUtf8 inputs))
      case r of
        Left ds -> pure ([], ds)
        Right bytes -> do
          clean dir
          createDirectoryIfMissing True dir
          BS.writeFile out bytes
          pure ([out], [])
  pure (concatMap fst results, concatMap snd results)
  where
    clean dir = do
      ex <- doesDirectoryExist dir
      when ex (removeDirectoryRecursive dir)
    writeText p t = createDirectoryIfMissing True (takeDirectory p) >> TIO.writeFile p t
    copy src dst = createDirectoryIfMissing True (takeDirectory dst) >> BS.readFile src >>= BS.writeFile dst

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
              <> maybe "" (\n -> escapeXml n <> " ") (teNumber te)
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
