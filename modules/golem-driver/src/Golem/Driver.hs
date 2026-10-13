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
    evaluateProject,
    evaluateProjectWith,
    Evaluated (..),
    missingStyleFiles,
    targetFileDiagnostics,
    sourceInfos,
    FontProvider (..),
    LoadedFonts (..),
    noFontProvider,
    paraLineBreaks,
    keepStyles,
    builtinKeepStyles,
    cssFontSize,
  )
where

import Control.Exception (SomeException, try)
import Control.Monad (forM, forM_, mfilter, when)
import Data.Aeson qualified as J
import Data.Aeson.Key qualified as JK
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (nub)
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
import Golem.Pdf qualified as P
import Golem.Plugin.Lock (defaultCacheDir)
import Golem.Project
import Golem.Project.Paths (PathError (..), pathErrorMessage, resolveInRoot)
import Golem.Project.Style
import Golem.Syntax
import Golem.Text qualified as GT
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, removeDirectoryRecursive)
import System.FilePath (takeDirectory, (</>))

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
    optMarks :: !CropMarks
  }

defaultOptions :: FilePath -> BuildOptions
defaultOptions root = BuildOptions root Nothing Dev False golemFontProvider True NoMarks

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
          styleFid = styleFileId project
      styleText <- readMaybeText (root </> "style.toml")
      case loadStyle styleFid styleText of
        Left ds -> pure (Left ds)
        Right style
          | hasErrors synDiags -> do
              assets <- loadAssets root project
              (citeKeys, _) <- loadBibliography root manifest0
              pure (Right (Evaluated project style styleFid (fromMaybe "" styleText) Map.empty Nothing synDiags (reeval profile project style assets citeKeys noPlugins Map.empty)))
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
                then pure (Right (Evaluated project style styleFid (fromMaybe "" styleText) results Nothing pre again))
                else do
                  let (book, s1Diags) = assemble cfg evalDeferred chapterDocs
                  pure (Right (Evaluated project style styleFid (fromMaybe "" styleText) results (Just book) (pre <> s1Diags) again))

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
            ctxParaStyles = paraLineBreaks style,
            ctxDefaultKenten = compKenten (stComposition style),
            ctxCiteKeys = citeKeys,
            ctxAssets = assets,
            ctxPlugins = hook
          }
   in evalFile ctx (sfAst sf)

-- | Whether each paragraph style keeps its lines, resolved (docs/adr ADR 0005).
paraLineBreaks :: Style -> Map Text LineBreaks
paraLineBreaks style =
  Map.fromList [(n, fromMaybe JoinLines (psLineBreaks d)) | n <- Map.keys (stParaStyles style), Just d <- [paraStyle style (Just n)]]

-- | The paragraph styles that keep their lines (lint G0501, docs/adr ADR 0005).
keepStyles :: Style -> Set.Set Text
keepStyles = Map.keysSet . Map.filter (== KeepLines) . paraLineBreaks

-- | The built-in paragraph styles that keep their lines: verse.
builtinKeepStyles :: Set.Set Text
builtinKeepStyles = keepStyles defaultStyle

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
          targets = fromMaybe (targetsOf (projectManifest project)) (optTargets opts)
      hasStyle <- doesFileExist (optRoot opts </> "style.toml")
      let styleFid = evStyleFile e
          -- style.toml is a source of diagnostics (golem-project ADR 0004, G0702) when it exists
          infos =
            (if hasStyle then Map.insert styleFid (SourceInfo "style.toml" (mkLineIndex (evStyleText e))) else id)
              (sourceInfos project)
          marksDiags = cropMarkDiagnostics opts e (if hasStyle then styleFid else projectManifestFile project) targets
      -- the files of style.toml, for the targets that use them (golem-project ADR 0004)
      missing <- missingStyleFiles (optRoot opts) (evStyle e)
      let perTarget = [(t, map (adjustForProfile (optProfile opts)) (targetFileDiagnostics styleFid (evStyle e) missing t)) | t <- targets]
          fileDiags = nub (concatMap snd perTarget)
          -- G0702 stops the PDF before it is laid out; the other targets are written
          writable = [t | (t, ds) <- perTarget, not (hasErrors ds), t /= TargetPdf || null marksDiags]
      case evBook e of
        Just book
          | not (hasErrors (finish (evDiagnostics e))) && not (optCheckOnly opts) -> do
              (written, outDiags) <- writeTargets opts e book missing writable
              pure (BuildResult (finish (evDiagnostics e <> fileDiags <> marksDiags <> outDiags)) infos written)
        _ -> pure (BuildResult (finish (evDiagnostics e <> fileDiags <> marksDiags)) infos [])
  where
    finish = sortDiagnostics . map (adjustForProfile (optProfile opts))

-- | Files of style.toml that cannot be used: path -> why (resolveInRoot).
missingStyleFiles :: FilePath -> Style -> IO (Map FilePath PathError)
missingStyleFiles root style = do
  let paths = nub (map snd (fontFiles style) <> maybe [] pure (stIntent style))
  resolved <- forM paths $ \p -> (p,) <$> resolveInRoot root p
  pure (Map.fromList [(p, err) | (p, Left err) <- resolved])

{- | Diagnostics of the missing files for one target (golem-project ADR
0004): the fonts the PDF uses and its output intent (errors), every font
for HTML and EPUB (warnings, errors in prod), nothing for plain text.
-}
targetFileDiagnostics :: FileId -> Style -> Map FilePath PathError -> Target -> [Diagnostic]
targetFileDiagnostics fid style missing = \case
  TargetPdf ->
    report "G0802" Error "フォントのファイルがありません" pdfFonts
      <> report "G0806" Error "出力インテントの ICC プロファイルがありません" (maybe [] pure (stIntent style))
  TargetHtml -> siteFonts
  TargetEpub -> siteFonts
  TargetText -> []
  where
    pdfFonts = [p | r <- usedRoles style, Just (FontRole ja la _) <- [Map.lookup r (stFonts style)], Just p <- [ja, la]]
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

writeTargets :: BuildOptions -> Evaluated -> Book -> Map FilePath PathError -> [Target] -> IO ([FilePath], [Diagnostic])
writeTargets opts e book missing targets = do
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
            hcSwatches = Map.map (\(Swatch c) -> c) (stSwatches style),
            -- missing fonts are left out of the site (golem-project ADR 0004)
            hcFonts = Map.map (\fr -> (present (frJa fr), present (frLatin fr))) (stFonts style),
            -- the resolved styles (docs/adr ADR 0005)
            hcCharStyles =
              Map.fromList
                [ (n, HtmlCharStyle (csFont d) (csSyntheticBold d == Just True) (csSyntheticItalic d == Just True) (csColor d))
                | n <- Map.keys (stCharStyles style),
                  Just d <- [charStyle style n]
                ],
            hcParaStyles =
              Map.fromList
                [ ( n,
                    HtmlParaStyle
                      (psFont d)
                      (psLineBreaks d == Just KeepLines)
                      (fromMaybe 0 (psSpaceBetween d))
                      (cssLength (fromMaybe (Zw 0) (psIndent d)))
                      (cssLength (fromMaybe (Zw 0) (psFirstLineIndent d)))
                  )
                | n <- Map.keys (stParaStyles style),
                  Just d <- [paraStyle style (Just n)]
                ],
            hcBibliography = bib,
            hcDev = dev,
            hcCaptionFace = let c = paraStyle style (Just "caption") in Face (c >>= psFont) (cssFontSize style <$> (c >>= psSize)),
            hcSidenoteFace = let d = paraStyle style (Just "sidenote") in Face (d >>= psFont) (cssFontSize style <$> (d >>= psSize)),
            hcRubyMonoAlign = rubyAlignCss (rdMonoAlign ruby),
            hcRubyGroupAlign = rubyAlignCss (rdGroupAlign ruby),
            hcRubyBaseSpacing = rubyAlignCss (rdBaseSpacing ruby)
          }
      present = mfilter (`Map.notMember` missing)
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
          -- without [targets.text], both variants, as when variants is omitted (golem-cli ADR 0002)
          variants = case tgText (manifestTargets manifest) of
            [] -> [TextVertical, TextHorizontal]
            vs -> vs
      clean dir
      files <- forM variants $ \v -> do
        let (sub, gv) = case v of
              TextVertical -> ("vertical", GT.Vertical)
              TextHorizontal -> ("horizontal", GT.Horizontal)
        forM (GT.renderText (stNumbersVertical style) dev (textFirstLine style) gv ft book) $ \(p, t) -> do
          writeText (dir </> sub </> p) t
          pure (dir </> sub </> p)
      pure (concat files, [])
    TargetPdf -> do
      let dir = root </> "build" </> "pdf"
          out = dir </> pdfFileName (mdId md)
          -- the manifest, style.toml, the sources and the options that change the output (golem-pdf ADR 0004)
          inputs = projectManifestText project : evStyleText e : [sfText sf | sf <- Map.elems (projectSources project)] <> [optionsInput opts]
      r <- renderPdf (optFonts opts) (PdfInput root project style book (optParallel opts) (map TE.encodeUtf8 inputs) bib (markStyle (optMarks opts)))
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
