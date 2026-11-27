{-# LANGUAGE CPP #-}
{-# LANGUAGE ForeignFunctionInterface #-}

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
    cleanFinderInfo,
    PreflightOptions (..),
    defaultPreflightOptions,
    PreflightResult (..),
    preflight,
    evaluateProject,
    BuildInMemory (..),
    buildPdfInMemory,
    hostContext,
    evaluateProjectWith,
    evaluateLoose,
    functionPaths,
    loadBibliography,
    pdfStructure,
    manuscriptLines,
    pdfLeafTexts,
    pdfWithTree,
    pdfWithDests,
    metadataValues,
    epubConfig,
    Evaluated (..),
    localStylesOf,
    docStyles,
    runningVars,
    projectVarTexts,
    sourceInfos,
    withEvaluatedSources,
    assetRefs,
    AssetUse (..),
    FontProvider (..),
    LoadedFonts (..),
    noFontProvider,
    keepStyles,
    sourceSettingsOf,
    builtinKeepStyles,
    cssFontSize,
    targetsOf,
  )
where

import Control.Exception (IOException, SomeException, try)
#if !defined(wasm32_HOST_ARCH)
import Control.Exception qualified as Exception
#endif
import Control.Monad (forM, forM_, join, mfilter, unless, when)
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (fromRight)
import Data.List (isPrefixOf, nub, sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, listToMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
#if !defined(wasm32_HOST_ARCH)
import Foreign.C.Error (throwErrnoIfMinus1Retry_)
import Foreign.C.String (CString)
import Foreign.C.Types (CInt (..))
#endif
import Golem.Assemble
import Golem.Assemble.Formats (MarkFormat (..))
import Golem.Assemble.ListMarkers (defaultNumberFormat, listNumberDiagnostics)
import Golem.Bibliography (EntryPart)
import Golem.Doc.IR
import Golem.Driver.Html
import Golem.Driver.PageMap (PageMapError (..), decodePageMap, resolvePageMapWithAst)
import Golem.Driver.Svg (activeMessage)
import Golem.Driver.Version (golemVersion)
import Golem.Epub
import Golem.Evaluate
import Golem.Html
import Golem.Length qualified as GL
import Golem.Parser.Read (readInfo, readSourceFile)
import Golem.Pdf qualified as P
import Golem.Preflight (MissingGlyph (..), check, checkBleed, missingGlyphs, pageChecks)
import Golem.Preflight.Rules (Level (LevelOff), Rules (..), parseRules, printRules)
import Golem.Preflight.View (View)
import Golem.Project
import Golem.Project.Files (Files (..), diskFiles, memoryFiles)
import Golem.Project.Paths (PathError (..), normalizeRelative, pathErrorMessage)
import Golem.Project.Style
import Golem.Svg qualified as Svg
import Golem.Svg.Active (activeContent)
import Golem.Syntax
import Golem.Text qualified as GT
import Golem.Typeset
import Golem.Typeset.FigureColor (safeRecolorRasterBytes)
import Golem.Typeset.FontProvider (golemFontProvider, pdfFontDiagnostics)
import Golem.Typeset.Svg (drawingSvg, figureColor, recolorFigure, svgDrawing)
import Numeric (showHex)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, pathIsSymbolicLink, removeDirectoryRecursive)
import System.FilePath (takeDirectory, takeFileName, (</>))
#if !defined(wasm32_HOST_ARCH)
import System.FilePath qualified as FilePath
import System.Posix.IO (OpenMode (ReadOnly), closeFd, defaultFileFlags, openFd)
import System.Posix.Types (Fd (..))
#endif

{- | The targets: the PDF for print, and the PDF for the screen (root ADR
0431), which is built only when it is chosen.
-}
data Target = TargetHtml | TargetEpub | TargetText | TargetPdf | TargetPdfScreen
  deriving stock (Eq, Ord, Show)

-- | Every target built without --target, in the order they are written (golem-cli ADR 0002); not the PDF for the screen (root ADR 0431).
allTargets :: [Target]
allTargets = [TargetHtml, TargetEpub, TargetText, TargetPdf]

-- | The PDF for print and the PDF for the screen, which share their layout (root ADR 0431).
isPdfTarget :: Target -> Bool
isPdfTarget t = t == TargetPdf || t == TargetPdfScreen

{- | The crop marks of the PDF (golem-pdf ADR 0004), chosen by golem build
--marks. golem-cli does not depend on golem-pdf, so this is not its type.
-}
data CropMarks = NoMarks | JapaneseMarks | WesternMarks
  deriving stock (Eq, Show)

data BuildOptions = BuildOptions
  { optRoot :: !FilePath,
    -- | how the files of the project are read (docs/adr/0199); writing goes to optRoot
    optFiles :: !Files,
    optTargets :: !(Maybe [Target]),
    optProfile :: !Profile,
    optCheckOnly :: !Bool,
    -- | where fonts come from (golem-font; see Golem.Typeset)
    optFonts :: !FontProvider,
    optParallel :: !Bool,
    -- | the crop marks of the PDF (golem-pdf ADR 0004)
    optMarks :: !CropMarks,
    -- | --no-notices: no notice is reported (golem-syntax ADR 0002)
    optNoNotices :: !Bool,
    -- | --verbose: the infos are reported too (docs/adr 0104)
    optVerbose :: !Bool
  }

defaultOptions :: FilePath -> BuildOptions
defaultOptions root = BuildOptions root (diskFiles root) Nothing Dev False golemFontProvider True NoMarks False False

data BuildResult = BuildResult
  { brDiagnostics :: ![Diagnostic],
    brSources :: !(Map FileId SourceInfo),
    brWritten :: ![FilePath]
  }

{- | The configuration of the EPUB: creators as dc:creator, contributors as
dc:contributor, both without the printer and the binder, the roles as
MARC relator codes (docs/adr ADR 0033).
-}
epubConfig :: Metadata -> Maybe Text -> Bool -> EpubConfig
epubConfig md isbn vertical =
  EpubConfig
    { epIdentifier = maybe (mdId md) ("urn:isbn:" <>) isbn,
      epTitle = mdTitle md,
      epTitleReading = mdTitleReading md,
      epLanguage = mdLanguage md,
      epDate = mdDate md,
      epPublisher = mdPublisher md,
      epCreators = people (mdCreators md),
      epContributors = people (mdContributors md),
      epVertical = vertical,
      epPageList = []
    }
  where
    people cs = [EpubCreator (crName c) (crReading c) (marcRelator (crRole c)) | c <- cs, inMetadata (crRole c)]

targetsOf :: Manifest -> [Target]
targetsOf m =
  let t = manifestTargets m
   in [TargetHtml | tgHtml t] <> [TargetEpub | isJust (tgEpub t)] <> [TargetText | not (null (tgText t))] <> [TargetPdf | isJust (tgPdf t)]

#if !defined(wasm32_HOST_ARCH)
foreign import ccall safe "golem_lock_directory" lockDirectory :: CInt -> IO CInt
foreign import ccall safe "golem_clean_finder_info" cleanFinderInfoAt :: CString -> CString -> IO CInt

-- | Remove only a regular Finder file in real project directories.
cleanFinderInfo :: FilePath -> [FilePath] -> IO ()
cleanFinderInfo root paths = do
  exists <- doesDirectoryExist root
  when exists $ do
    forM_ (nub paths) $ \path -> do
      let relative = FilePath.normalise path
      BS.useAsCString (TE.encodeUtf8 (T.pack root)) $ \rootString ->
        BS.useAsCString (TE.encodeUtf8 (T.pack relative)) $ \relativeString ->
          throwErrnoIfMinus1Retry_ ("remove " <> root </> relative </> ".DS_Store")
            (cleanFinderInfoAt rootString relativeString)

-- | Hold an exclusive lock on the project directory while writing targets or
-- removing an earlier PDF. The directory itself is the lock, so a build
-- leaves no lock file in the project.
withOutputLock :: FilePath -> IO a -> IO a
withOutputLock root action = do
  exists <- doesDirectoryExist root
  if exists
    then Exception.bracket (openFd root ReadOnly defaultFileFlags) closeFd $ \(Fd fd) -> do
      throwErrnoIfMinus1Retry_ "lock project directory" (lockDirectory fd)
      action
    else action
#else
withOutputLock :: FilePath -> IO a -> IO a
withOutputLock _ action = action

cleanFinderInfo :: FilePath -> [FilePath] -> IO ()
cleanFinderInfo _ _ = pure ()
#endif

build :: BuildOptions -> IO BuildResult
build opts = withOutputLock (optRoot opts) $ do
  (result, _, _, selectedTargets) <- buildCore False opts
  let selectedDirs = maybe [] (map targetOutputDir) selectedTargets
  unless (optCheckOnly opts) $
    cleanFinderInfo (optRoot opts) ("." : "build" : selectedDirs)
  -- the PDF for print and the PDF for the screen of an earlier build (docs/adr/0326, root ADR 0431)
  forM_ [TargetPdf, TargetPdfScreen] $ \t -> do
    let dir = optRoot opts </> targetOutputDir t
        wasWritten = any ((== dir) . takeDirectory) (brWritten result)
        wasSelected = t `elem` fromMaybe [TargetPdf] selectedTargets
    when (optProfile opts == Prod && not (optCheckOnly opts) && wasSelected && hasErrors (brDiagnostics result) && not wasWritten) $ do
      unsafe <- unsafeOutputDirs (optRoot opts) [t]
      when (null unsafe) (cleanDir dir)
  pure result

targetOutputDir :: Target -> FilePath
targetOutputDir = \case
  TargetHtml -> "build/html"
  TargetEpub -> "build/epub"
  TargetText -> "build/text"
  TargetPdf -> "build/pdf"
  TargetPdfScreen -> "build/pdf-screen"

-- | The PDF of a project built from its files in memory (docs/adr/0199).
data BuildInMemory = BuildInMemory
  { -- | Nothing after an error
    bimPdf :: !(Maybe BS.ByteString),
    -- | after finishDiagnostics
    bimDiagnostics :: ![Diagnostic],
    -- | for renderJson
    bimSources :: !(Map FileId SourceInfo)
  }

{- | The PDF of a project from a table of its files, by their paths from
the root, normalised (docs/adr/0199): the build of golem build --target pdf
with the defaults, in one thread, reading the table only and writing
nothing. The PDF and the diagnostics are those of golem build --target pdf
--format json on the same files.
-}
buildPdfInMemory :: Map FilePath BS.ByteString -> IO BuildInMemory
buildPdfInMemory table = do
  let opts = (defaultOptions ".") {optFiles = memoryFiles table, optTargets = Just [TargetPdf], optParallel = False}
  (r, pdf, _, _) <- buildCore True opts
  pure (BuildInMemory (fst <$> pdf) (brDiagnostics r) (brSources r))

{- | The build; with @inMemory@, the PDF is not written but returned with
its view (golem preflight, golem-cli ADR 0006).
-}
buildCore :: Bool -> BuildOptions -> IO (BuildResult, Maybe (BS.ByteString, View), Maybe (SrcSpan, Sp), Maybe [Target])
buildCore inMemory opts0 = do
  ev <- evaluateProjectWith (optFiles opts0) Map.empty (optProfile opts0) (optRoot opts0)
  case ev of
    Left f -> pure (BuildResult (finishWith Set.empty Set.empty (pfDiagnostics f)) (pfSources f) [], Nothing, Nothing, optTargets opts0)
    Right e -> do
      let project = evProject e
          finish = finishWith (manifestSilencedNotices (projectManifest project)) (manifestSilencedInfo (projectManifest project))
          targets = fromMaybe (targetsOf (projectManifest project)) (optTargets opts0)
          -- the crop marks are those of the PDF for print; the PDF for the screen has none (root ADR 0431)
          opts = if TargetPdf `elem` targets then opts0 else opts0 {optMarks = NoMarks}
          pdfAny = any isPdfTarget targets
      hasStyle <- isPresent (optFiles opts) "style.toml"
      let styleFid = evStyleFile e
          -- style.toml is a source of diagnostics (golem-project ADR 0004, G07002) when it exists
          infos =
            (if hasStyle then Map.insert styleFid (SourceInfo "style.toml" (mkLineIndex (evStyleText e))) else id)
              (withEvaluatedSources e (sourceInfos project))
          -- where diagnostics about style.toml point (golem-driver ADR 0016)
          diagFid = if hasStyle then styleFid else projectManifestFile project
          bleed = Just (mkSpan diagFid 0 0, maybe 0 pageBleed (stPage (evStyle e)))
          -- G07002, and what style.toml decides of the layout (G07001, G07025; golem-driver ADR 0016)
          marksDiags =
            cropMarkDiagnostics opts e diagFid targets
              <> (if pdfAny then styleLayoutDiagnostics diagFid (isJust (markStyle (optMarks opts))) (evStyle e) (Map.elems (localStylesOf e)) else [])
          -- what stops the PDF for the screen: the layout without the crop marks of the PDF for print (root ADR 0431)
          screenStops = if isJust (markStyle (optMarks opts)) then styleLayoutDiagnostics diagFid False (evStyle e) (Map.elems (localStylesOf e)) else marksDiags
          -- G07128: reported, but it holds back neither the layout nor, in dev, the PDF (docs/adr/0389)
          sidenoteDiags = if pdfAny then pdfSidenoteIndents opts e diagFid else []
      -- the files of style.toml, for the targets that use them (golem-project ADR 0004)
      missing <- missingStyleFiles (optFiles opts) (evStyle e)
      -- without code in the book, the role code is not used (golem-driver ADR 0017)
      let fileStyle = maybe id (\b -> codeStyles (bookHasCode (docStyles e) b) (stFonts (evStyle e))) (evBook e) (evStyle e)
          locals = Map.elems (localStylesOf e)
      -- G08019: CFF2 fonts, which the PDF cannot embed (golem-font ADR 0003), and G08110, G08111, G08112:
      -- instances that are not in their fonts (Golem ADR 0358); golem check reports them too
      cff2Diags <-
        if pdfAny
          then pdfFontDiagnostics (optFiles opts) diagFid [(r, fr {frJa = mfilter (`Map.notMember` missing) (frJa fr), frLatin = mfilter (`Map.notMember` missing) (frLatin fr)}) | (r, fr) <- pdfFontRoles fileStyle locals]
          else pure []
      -- G03284: files of the same name and other bytes under fonts/, for the targets that embed the fonts (root ADR 0433)
      let declared = manifestTargets (projectManifest project)
      clashes <-
        if embedsFonts declared (TargetHtml `elem` targets) (TargetEpub `elem` targets)
          then fontClashDiagnostics (optFiles opts) diagFid fileStyle missing
          else pure []
      let perTarget = [(t, map (adjustForProfile (optProfile opts)) (targetFileDiagnostics diagFid declared fileStyle locals missing clashes t <> (if isPdfTarget t then cff2Diags else []))) | t <- targets]
          fileDiags = nub (concatMap snd perTarget)
          -- G07001, G07002 and G07025 stop the PDF before it is laid out; the other targets are written
          writable = [t | (t, ds) <- perTarget, not (hasErrors ds), t /= TargetPdf || null marksDiags, t /= TargetPdfScreen || null screenStops]
          -- the variables of the running heads, after S0, only for the PDF (golem-driver ADR 0022)
          evDiags =
            evDiagnostics e
              <> (if pdfAny then snd (runningVars e) else [])
              <> maybe [] (chapterNoteDiagnostics (evStyle e) targets infos) (evBook e)
              <> maybe [] (pageNumberingDiagnostics (evStyle e) targets) (evBook e)
      case evBook e of
        Just book
          | not (hasErrors (finish evDiags)) && not (optCheckOnly opts) -> do
              -- G08014 stops HTML and EPUB, which copy SVG figures as they are (docs/adr ADR 0039)
              -- and G08102, a figure of the source where they put the images of plugins (docs/adr/0123)
              activeDiags <-
                if any (`elem` writable) [TargetHtml, TargetEpub]
                  then do
                    svgDiags <- if isJust (figureColor (evStyle e)) then pure [] else activeContentDiagnostics (optFiles opts) book
                    pure (pluginImagePathDiagnostics book <> svgDiags)
                  else pure []
              let webWritable = [t | t <- writable, null activeDiags || t `notElem` [TargetHtml, TargetEpub]]
                  -- a list number its format cannot write stops every target (golem-driver ADR 0013)
                  listDiags = listNumberDiagnostics (lsNumbers (stLists (evStyle e))) (maybe False pageVertical (stPage (evStyle e))) book <> noteNumberDiagnostics (all isPdfTarget targets) (evStyle e) book
              (written, outDiags, pdf) <-
                if null listDiags || null webWritable
                  then writeTargets inMemory opts e diagFid book missing webWritable
                  else pure ([], listDiags, Nothing)
              pure (BuildResult (finish (evDiags <> fileDiags <> marksDiags <> sidenoteDiags <> activeDiags <> outDiags)) infos written, pdf, bleed, Just targets)
        _ -> do
          -- G07144 of golem check, which does not lay out the book: its paragraphs of fit-characters composed (root ADR 0466)
          fitDiags <- case evBook e of
            Just book
              | optCheckOnly opts,
                pdfAny,
                not (hasErrors (finish evDiags)),
                null marksDiags,
                any (any (isJust . psFitCharacters) . Map.elems) (stParaStyles (evStyle e) : map lsParaStyles locals) -> do
                  (_, _, bib) <- loadBibliography (optFiles opts) (projectManifest project)
                  fitCharacterDiagnostics (optFonts opts) (pdfInputOf opts e diagFid book bib)
            _ -> pure []
          pure (BuildResult (finish (evDiags <> fileDiags <> marksDiags <> sidenoteDiags <> fitDiags)) infos [], Nothing, bleed, Just targets)
  where
    -- the profile, then the notices silenced by the manifest or by --no-notices (golem-syntax ADR 0002),
    -- then the infos of silence-info, and every info without --verbose (docs/adr 0104)
    finishWith silenced silencedInfo =
      finishDiagnostics (optProfile opts0) (if optNoNotices opts0 then Nothing else Just silenced) silencedInfo (optVerbose opts0)

{- | G08102 (docs/adr/0123): a figure of the source whose image HTML and
EPUB copy (its web image, or itself) would be written under
images/golem-plugin/, where they put the images plugins make. One for
each figure, at its block.
-}
pluginImagePathDiagnostics :: Book -> [Diagnostic]
pluginImagePathDiagnostics book =
  [ diagnostic "G08102" Error sp ("図版の画像の出力のパスが、プラグインの画像を置くフォルダ images/golem-plugin と重なります: " <> path)
  | Document _ bs <- bookDocs book,
    Block sp _ _ (FigureBlock f) <- allFigures bs,
    let path = fromMaybe (figSource f) (figWeb f),
    Right rel <- [normalizeRelative (T.unpack path)],
    "images/golem-plugin/" `isPrefixOf` rel
  ]

{- | G08014 (docs/adr ADR 0039): the SVG files that HTML and EPUB copy (a
figure or its @web@ image, also inside lists) with active content, or
that cannot be read; each file is read once, and each @figure that uses
it gets its own diagnostic at its block. Files that are missing or
outside the root are left to the diagnostics about paths.
-}
activeContentDiagnostics :: Files -> Book -> IO [Diagnostic]
activeContentDiagnostics files book = do
  let figures = [(sp, webSource f) | Document _ bs <- bookDocs book, Block sp _ _ (FigureBlock f) <- allFigures bs, ".svg" `T.isSuffixOf` T.toLower (webSource f)]
  checked <- forM (nub (map snd figures)) $ \path -> case Map.lookup path (bookImages book) of
    -- an image a plugin made (docs/adr/0123)
    Just bytes -> pure (path, activeMessage path (activeContent bytes))
    Nothing -> do
      resolved <- filesResolve files (T.unpack path)
      case resolved of
        Right rel -> (path,) . activeMessage path . activeContent <$> filesRead files rel
        Left _ -> pure (path, Nothing)
  let messages = Map.fromList checked
  pure [diagnostic "G08014" Error sp msg | (sp, path) <- figures, Just (Just msg) <- [Map.lookup path messages]]

{- | G03027 (golem-driver ADR 0026): numbers per file meet in the list of a
chapter of two files or more with notes in two of them, when a target
gathers the notes at the end of the chapter: HTML, EPUB and plain text
always, the PDF with placement = "chapter-end". It points at the first
note of the second file with notes and names the first file of the
chapter.
-}
chapterNoteDiagnostics :: Style -> [Target] -> Map FileId SourceInfo -> Book -> [Diagnostic]
chapterNoteDiagnostics style targets infos book =
  [ diagnostic "G03027" Warning sp ("章末の注の番号が章の中で重なります（" <> pathOf f0 <> "）。[notes] の numbering を \"chapter\" にしてください")
  | stNotesNumbering style == NumberPerFile && gathered,
    ch@(Document f0 _ : _ : _) <- bookChapters book,
    (_ : ((sp, _, _) : _) : _) <- [filter (not . null) (map documentNotes ch)]
  ]
    -- the endnotes, gathered in every target, by the same rule (root ADR 0412)
    <> [ diagnostic "G03027" Warning sp ("章末の注の番号が章の中で重なります（" <> pathOf f0 <> "）。[endnotes] の numbering を \"chapter\" にしてください")
       | stNotesNumbering (endnoteStyle style) == NumberPerFile,
         ch@(Document f0 _ : _ : _) <- bookChapters book,
         (_ : ((sp, _, _) : _) : _) <- [filter (not . null) (map documentEndnotes ch)]
       ]
  where
    gathered = any (`elem` targets) [TargetHtml, TargetEpub, TargetText] || (any isPdfTarget targets && stNotesPlacement style == PlaceChapterEnd)
    pathOf f = maybe "" (T.pack . siPath) (Map.lookup f infos)

{- | G03259 (docs/adr/0383): notes numbered per page, and a target without
fixed pages (HTML, EPUB, plain text), which numbers them in the order of
the book. Once, at the first note or sidenote of the book; none for a
book without them.
-}
pageNumberingDiagnostics :: Style -> [Target] -> Book -> [Diagnostic]
pageNumberingDiagnostics style targets book
  | stNotesNumbering style /= NumberPerPage || not (any (`elem` targets) [TargetHtml, TargetEpub, TargetText]) = []
  | otherwise =
      take 1 [diagnostic "G03259" Warning sp "[notes] の numbering = \"page\" は、ページを持たない出力（HTML、EPUB、プレーンテキスト）では使えないので、注に本の通し番号を振ります" | (_, _, sp) <- bookNoteSites book]

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
    prSkipped :: ![(Text, Text)],
    prBasedOn :: !Text
  }

{- | golem preflight (golem-cli ADR 0006): the rules first (G09001 stops
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
            then Left ([diagnostic "G09100" Error (mkSpan rulesFid 0 0) ("プリフライトの設定のファイルがありません: " <> T.pack path)], "")
            else Right (printRules, "組み込みの print")
      else do
        bytes <- BS.readFile path
        pure $ case TE.decodeUtf8' bytes of
          Left _ -> Left ([diagnostic "G09101" Error (mkSpan rulesFid 0 0) ("プリフライトの設定のファイルが UTF-8 として読めません: " <> T.pack path)], "")
          Right src -> case parseRules rulesFid src of
            Left ds -> Left (ds, src)
            Right r -> Right (r, fromMaybe (T.pack (takeFileName path)) (ruName r))
  case rulesE of
    Left (ds, src) -> pure (PreflightResult (sortDiagnostics ds) (Map.singleton rulesFid (SourceInfo path (mkLineIndex src))) Nothing Nothing "" [] "")
    Right (rules, label) -> do
      let opts = (defaultOptions (poRoot po)) {optTargets = Just [TargetPdf], optProfile = Prod, optMarks = poMarks po, optFonts = poFonts po, optParallel = poParallel po}
      (r, pdf, pageBleedInput, _) <- buildCore True opts
      (sources, bleed) <- case (pdf, pageBleedInput) of
        (Nothing, Nothing) -> independentBleed (optFiles opts) (brSources r)
        _ -> pure (brSources r, pageBleedInput)
      let (diagnostics, skipped) = case pdf of
            Just (_, view) -> (filter ((/= DiagnosticCode "G08100") . diagCode) (brDiagnostics r) <> check rules view, [])
            Nothing ->
              ( brDiagnostics r <> maybe [] (uncurry (checkBleed rules)) bleed,
                [(name, "ページ情報を作れませんでした") | name <- pageChecks rules]
                  <> [("bleed-size", "版面設定を読み取れませんでした") | isNothing bleed, ruBleedSize rules /= LevelOff]
              )
      pure (PreflightResult (sortDiagnostics diagnostics) sources (fst <$> pdf) (snd <$> pdf) label skipped (ruBasedOn rules))

-- | A manifest or source failure can precede the build's first read of the style.
independentBleed :: Files -> Map FileId SourceInfo -> IO (Map FileId SourceInfo, Maybe (SrcSpan, Sp))
independentBleed files infos
  | any ((== "style.toml") . siPath) (Map.elems infos) = pure (infos, Nothing)
  | otherwise =
      filesResolve files "style.toml" >>= \case
        Left _ -> pure (infos, Nothing)
        Right rel -> do
          bytes <- filesRead files rel
          let fid = case Map.lookupMax infos of Nothing -> FileId 0; Just (FileId n, _) -> FileId (n + 1)
          pure $ case readSourceFile fid "style.toml" bytes of
            Right src
              | Right style <- parseStyle fid src ->
                  (Map.insert fid (readInfo "style.toml" bytes) infos, Just (mkSpan fid 0 0, maybe 0 pageBleed (stPage style)))
            _ -> (infos, Nothing)

-- | Files of style.toml that cannot be used: path -> why (resolveInRoot).
missingStyleFiles :: Files -> Style -> IO (Map FilePath PathError)
missingStyleFiles files style = do
  resolved <- forM (styleFilePaths style) $ \p -> (p,) <$> filesResolve files p
  pure (Map.fromList [(p, err) | (p, Left err) <- resolved])

-- | The files style.toml names: the fonts of every role, their license documents (root ADR 0433), then the output intent.
styleFilePaths :: Style -> [FilePath]
styleFilePaths style = nub (map snd (fontFiles style) <> licenses <> maybe [] pure (stIntent style))
  where
    licenses = [l | fr <- Map.elems (stFonts style), Just l <- [frJaLicense fr, frLatinLicense fr]]

{- | The files HTML and EPUB copy to fonts/ when they embed the fonts (root
ADR 0433): each font that is not @missing@, then the license document of
each such font that is not missing, as (output path, source path).
-}
copiedFontFiles :: Style -> Map FilePath PathError -> [(FilePath, FilePath)]
copiedFontFiles style missing =
  [(fontOutput p, p) | p <- present]
    <> [(fontOutput l, l) | f <- fontFilesWithLicenses style, Map.notMember (ffPath f) missing, Just l <- [ffLicense f], Map.notMember l missing]
  where
    present = [p | (_, p) <- fontFiles style, Map.notMember p missing]
    fontOutput p = "fonts" </> takeFileName p

{- | G03284 (root ADR 0433): files that HTML and EPUB would copy to the
same name under fonts/ with other bytes; one error for each name, with its
files in order. Files of the same bytes are copied once and are no error.
-}
fontClashDiagnostics :: Files -> FileId -> Style -> Map FilePath PathError -> IO [Diagnostic]
fontClashDiagnostics files fid style missing = do
  let byName = Map.fromListWith (flip (<>)) [(o, [src]) | (o, src) <- copiedFontFiles style missing]
  clashes <- forM [(o, srcs) | (o, srcs0) <- Map.toAscList byName, let { srcs = sort (nub srcs0) }, length srcs > 1] $ \(o, srcs) -> do
    contents <- forM srcs $ \src -> do
      resolved <- filesResolve files src
      case resolved of
        Left _ -> pure Nothing
        Right rel -> either (const Nothing) Just <$> (try (filesRead files rel) :: IO (Either IOException BS.ByteString))
    pure [(o, srcs) | length (nub contents) > 1]
  pure
    [ diagnostic "G03284" Error (mkSpan fid 0 0) ("fonts に写す同じ名前のファイルの中身が違います: " <> T.pack o <> "（" <> T.intercalate "、" (map T.pack srcs) <> "）")
    | (o, srcs) <- concat clashes
    ]

{- | Diagnostics of the files of style.toml for one target. A path outside
the project (absolute, a URL, out of the root, or a symbolic link out of
it) is G03279, an error for every target and profile (docs/adr/0421); it
is the same diagnostic for every target, so a build reports it once.
Missing files (golem-project ADR 0004): the fonts the PDF uses and its
output intent (errors), every font for HTML and EPUB that embed them
(warnings, errors in prod), nothing for HTML and EPUB that name generic
families (docs/adr/0423) and for plain text. The PDF also needs a body font
with a file (G08007, golem-driver ADR 0016).
-}
targetFileDiagnostics :: FileId -> Targets -> Style -> [LocalStyles] -> Map FilePath PathError -> [Diagnostic] -> Target -> [Diagnostic]
targetFileDiagnostics fid declared style locals missing clashes target =
  outside <> case target of
    TargetPdf ->
      bodyFontDiagnostics fid style
        <> report "G08002" Error "フォントのファイルがありません" (pdfFontPaths style locals)
        <> report "G08006" Error "出力インテントの ICC プロファイルがありません" (maybe [] pure (stIntent style))
    -- the PDF for the screen has no output intent (root ADR 0431)
    TargetPdfScreen ->
      bodyFontDiagnostics fid style
        <> report "G08002" Error "フォントのファイルがありません" (pdfFontPaths style locals)
    TargetHtml -> siteFonts (tgHtmlFonts declared)
    TargetEpub -> siteFonts (tgEpubFonts declared)
    TargetText -> []
  where
    outside =
      [ diagnostic "G03279" Error (mkSpan fid 0 0) (T.pack (pathErrorMessage err <> ": " <> p))
      | p <- styleFilePaths style,
        Just err <- [Map.lookup p missing],
        err /= Missing
      ]
    siteFonts = \case
      WebFontsEmbed ->
        report "G03010" Warning "フォントのファイルがないので、HTML と EPUB に同梱しません" (map snd (fontFiles style))
          -- the license documents of the fonts that are copied (root ADR 0433)
          <> fontLicenseKeyDiagnostics fid style (`Map.notMember` missing)
          <> report "G03283" Warning "フォントのライセンスの文書のファイルがありません" [l | f <- fontFilesWithLicenses style, Map.notMember (ffPath f) missing, Just l <- [ffLicense f]]
          <> clashes
      WebFontsGeneric -> []
    report code sev msg paths =
      [ diagnostic code sev (mkSpan fid 0 0) (T.pack (msg <> ": " <> p))
      | p <- nub paths,
        Map.lookup p missing == Just Missing
      ]

-- | The roles that the PDF uses, with their files (Golem ADR 0358).
pdfFontRoles :: Style -> [LocalStyles] -> [(Text, FontRole)]
pdfFontRoles style locals = [(r, fr) | r <- usedRoles style locals, Just fr <- [Map.lookup r (stFonts style)]]

-- | The font files of the roles the PDF uses.
pdfFontPaths :: Style -> [LocalStyles] -> [FilePath]
pdfFontPaths style locals = [p | r <- usedRoles style locals, Just (FontRole {frJa = ja, frLatin = la}) <- [Map.lookup r (stFonts style)], Just p <- [ja, la]]

{- | G07002 (golem-pdf ADR 0004): Japanese crop marks need bleed, because the
trim line and the bleed line would be drawn on top of each other. Only when
the PDF is a target; at the top of style.toml (or of the manifest without
one), as Style keeps no positions.
-}
cropMarkDiagnostics :: BuildOptions -> Evaluated -> FileId -> [Target] -> [Diagnostic]
cropMarkDiagnostics opts e fid targets =
  [ diagnostic "G07002" Error (mkSpan fid 0 0) "日本式のトンボには塗り足しが要ります。style.toml の [page] の bleed に 0 より大きい長さを書いてください"
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

{- | Writes the targets, after G08013 (docs/adr ADR 0035): @build@ and the
folder of each target that is written must be real folders or missing, not
symbolic links nor other files, or nothing is removed nor written.
-}
writeTargets :: Bool -> BuildOptions -> Evaluated -> FileId -> Book -> Map FilePath PathError -> [Target] -> IO ([FilePath], [Diagnostic], Maybe (BS.ByteString, View))
writeTargets inMemory opts e diagFid book missing targets = do
  let written = [t | t <- targets, not (inMemory && t == TargetPdf)]
  unsafe <- if null written then pure [] else unsafeOutputDirs (optRoot opts) written
  case unsafe of
    [] -> writeTargetsChecked inMemory opts e diagFid book missing targets
    ps -> pure ([], [diagnostic code Error (mkSpan diagFid 0 0) (reason <> ": " <> T.pack path) | (path, code, reason) <- ps], Nothing)

{- | The output folders, relative to the root, that are symbolic links (to
anywhere, or nowhere) or files that are not folders: @build@ and the folder
of each target.
-}
unsafeOutputDirs :: FilePath -> [Target] -> IO [(FilePath, Text, Text)]
unsafeOutputDirs root targets = do
  parent <- unsafe "build"
  case parent of
    Just problem -> pure [problem]
    Nothing -> catMaybes <$> mapM unsafe (nub (map targetDir targets))
  where
    targetDir = \case
      TargetHtml -> "build/html"
      TargetEpub -> "build/epub"
      TargetText -> "build/text"
      TargetPdf -> "build/pdf"
      TargetPdfScreen -> "build/pdf-screen"
    unsafe rel = do
      let p = root </> rel
      link <- fromRight False <$> (try (pathIsSymbolicLink p) :: IO (Either SomeException Bool))
      if link
        then pure (Just (rel, "G08013", "出力先がシンボリックリンクです"))
        else do
          file <- doesFileExist p
          pure (if file then Just (rel, "G08104", "出力先に通常のファイルがあります") else Nothing)

{- | Writes each target in turn: the written files, the diagnostics of the
targets and the PDF kept in memory with its view. The HTML configuration
is made once, for the site that HTML and EPUB share (docs/adr/0173).
-}
writeTargetsChecked :: Bool -> BuildOptions -> Evaluated -> FileId -> Book -> Map FilePath PathError -> [Target] -> IO ([FilePath], [Diagnostic], Maybe (BS.ByteString, View))
writeTargetsChecked inMemory opts e diagFid book missing targets = do
  let root = optRoot opts
      ft = projectFiles (evProject e)
  (_, _, bib) <- loadBibliography (optFiles opts) (projectManifest (evProject e))
  let hcfgOf embed = htmlConfig (optProfile opts == Dev) embed e book missing bib
      originalSite = renderXhtml (hcfgOf True) ft book
      declared = manifestTargets (projectManifest (evProject e))
  (webBook, webDiags) <- if any (`elem` targets) [TargetHtml, TargetEpub] then recolorWebFigures opts (evStyle e) book originalSite else pure (book, [])
  {- the site with the fonts embedded or of generic families (docs/adr/0423),
  in the HTML syntax for HTML and in the XHTML syntax for EPUB (root ADR 0432) -}
  let web render fonts = let hcfg = hcfgOf (fonts == WebFontsEmbed) in (hcfg, render hcfg ft webBook)
  results <- forM targets $ \case
    TargetHtml | not (null webDiags) -> cleanDir (root </> "build" </> "html") >> pure ([], [], Nothing)
    TargetEpub | not (null webDiags) -> cleanDir (root </> "build" </> "epub") >> pure ([], [], Nothing)
    TargetHtml -> let (hcfg, site) = web renderHtml (tgHtmlFonts declared) in writeHtmlTarget root hcfg ft webBook site
    TargetEpub -> let (hcfg, site) = web renderXhtml (tgEpubFonts declared) in writeEpubTarget opts e hcfg ft webBook site
    TargetText -> writeTextTarget root (optProfile opts == Dev) e bib ft book
    -- one layout for the PDF for print and the PDF for the screen (root ADR 0431)
    TargetPdf -> writePdfTarget inMemory True (TargetPdfScreen `elem` targets) opts e diagFid book bib
    TargetPdfScreen
      | TargetPdf `elem` targets -> pure ([], [], Nothing)
      | otherwise -> writePdfTarget inMemory False True opts {optMarks = NoMarks} e diagFid book bib
  pure (concat [w | (w, _, _) <- results], webDiags <> concat [d | (_, d, _) <- results], listToMaybe [x | (_, _, Just x) <- results])

{- | The configuration of the HTML of a book from its style.toml and the
styles of its files: @dev@ for the profile dev, @embed@ for fonts =
"embed" (docs/adr/0423), the fonts that are @missing@ left out, the
entries of the bibliography.
-}
htmlConfig :: Bool -> Bool -> Evaluated -> Book -> Map FilePath PathError -> Map Text [EntryPart] -> HtmlConfig
htmlConfig dev embed e book missing bib =
  HtmlConfig
    { hcTitle = mdTitle md,
      hcLanguage = mdLanguage md,
      hcVertical = vertical,
      hcSeparatorPitch = do
        grid <- stPage style >>= pageGrid
        if gridAlignment grid == AlignFree
          then Just (dimToSp (dimToSp 0 (gridFontSize grid)) (gridLinePitch grid))
          else Nothing,
      hcNumberDefault = stNumbersVertical style,
      hcSwatches = Map.map (\(Swatch c) -> c) (stSwatches style),
      -- missing fonts are left out of the site (golem-project ADR 0004)
      hcFonts = Map.map (\fr -> (present (frJa fr), present (frLatin fr))) (stFonts style),
      -- the resolved styles (docs/adr ADR 0005)
      hcCharStyles = htmlCharStyles style,
      -- table is the style of the cells of tables: its rules for paragraphs only when a paragraph has it (docs/adr/0262)
      hcParaStyles = forParagraphs (htmlParaStyles style),
      -- the styles of each file that differ from those of style.toml (docs/adr ADR 0014)
      hcLocalStyles =
        Map.fromList
          [ ( fid,
              HtmlLocalStyles
                { hlCharStyles = Map.differenceWith changed (htmlCharStyles st) (htmlCharStyles style),
                  hlParaStyles = forParagraphs (Map.differenceWith changed (htmlParaStyles st) (htmlParaStyles style)),
                  hlCaptionFace = mfilter (/= captionFace style) (Just (captionFace st)),
                  hlSidenoteFace = mfilter (/= sidenoteFace style) (Just (sidenoteFace st)),
                  hlTableFaces = Map.differenceWith changed (tableFaces st) (tableFaces style)
                }
            )
          | fid <- Map.keys (localStylesOf e),
            let st = docStyles e fid
          ],
      hcBibliography = bib,
      hcDev = dev,
      hcCaptionFace = captionFace style,
      hcSidenoteFace = sidenoteFace style,
      -- the faces of the cells of tables: table, and the styles given to tables (docs/adr/0262)
      hcTableFaces = tableFaces style,
      -- the paragraph styles without a name (root ADR 0467)
      hcAnonymousStyles = Map.fromList [(r, ps) | r <- anonymous, Just ps <- [htmlAnonymousStyle style r]],
      hcLocalAnonymousStyles =
        Map.fromList
          [ (fid, Map.fromList [(r, ps) | r <- keyedStyleRefs bs, Just ps <- [htmlAnonymousStyle (docStyles e fid) r]])
          | Document fid bs <- bookDocs book,
            Map.member fid (localStylesOf e)
          ],
      hcAnonymousTableFaces = Map.fromList [(r, anonymousFace r) | r <- anonymous],
      hcTableCaptionBelow = stTableCaption style == CaptionBelow,
      hcIndexSectionHeadings = indexSectionHeadings style,
      hcRubyMonoAlign = rubyAlignCss (rdMonoAlign ruby),
      hcRubyGroupAlign = rubyAlignCss (rdGroupAlign ruby),
      hcRubyBaseSpacing = rubyAlignCss (rdBaseSpacing ruby),
      hcRubyReadingStyle = rdReadingStyle ruby,
      hcBreakKinds = Set.fromList [k | Document _ bs <- bookDocs book, Block _ _ _ (ForcedBreak k) <- bs],
      hcNoBreak = or [keepsPageBreak c | Document _ bs <- bookDocs book, Block _ _ _ (PageControl c) <- bs],
      -- only a book with [lists] changes the markers (golem-driver ADR 0013)
      -- the paragraph style code for pre (golem-driver ADR 0017)
      hcCode =
        let d = paraStyle style (Just "code")
         in HtmlCode
              { hcoFont = d >>= psFont,
                hcoSize = cssFontSize style <$> (d >>= psSize),
                hcoBackground = join (d >>= psBackground),
                hcoPadding = cssLength (fromMaybe (Zw 0.5) (d >>= psPadding)),
                -- the border and [code] (golem-driver ADR 0023)
                hcoBorder = join (d >>= psBorder),
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
          else Just (HtmlLists (listBullets (stLists style)) (fromMaybe (pure (defaultNumberFormat vertical)) (lsNumbers (stLists style))) (GT.tlGap (textLists style)) (lsMarkerStyle (stLists style))),
      -- the rules of headings (golem-driver ADR 0027)
      hcHeadingStyles = htmlHeadingStyles style,
      hcLocalHeadingStyles = Map.fromList [(fid, htmlHeadingStyles (docStyles e fid)) | fid <- Map.keys (localStylesOf e)],
      hcHeadingRules =
        Map.fromList
          [ (l, (htmlRule style <$> hsRuleBefore h, htmlRule style <$> hsRuleAfter h))
          | (l, h) <- Map.toList (stHeadings style),
            isJust (hsRuleBefore h) || isJust (hsRuleAfter h)
          ],
      -- the links of notes in the notation of [notes] mark-format (docs/adr/0177)
      hcNoteNotation = mfNotation (stNotesMarkFormat style),
      hcEndnoteNotation = mfNotation (stNotesMarkFormat (endnoteStyle style)),
      -- the fonts embedded, or generic families alone (docs/adr/0423)
      hcEmbedFonts = embed,
      -- the license documents of the fonts that are copied, when they are there (root ADR 0433)
      hcFontLicenses = [l | f <- fontFilesWithLicenses style, Map.notMember (ffPath f) missing, Just l <- [ffLicense f], Map.notMember l missing],
      hcGenericFamilies = Map.mapMaybe (fmap genericFamilyName . frGenericFamily) (stFonts style),
      hcCharacterAdvance = do
        grid <- stPage style >>= pageGrid
        advance <- gridCharacterAdvance grid
        let fs = dimToSp 1 (gridFontSize grid)
        if fs <= 0 then Nothing else Just (GL.emText (toRational (GL.unSp (dimToSp fs advance)) / toRational (GL.unSp fs)) <> "em")
    }
  where
    style = evStyle e
    md = manifestMetadata (projectManifest (evProject e))
    vertical = maybe False pageVertical (stPage style)
    present = mfilter (`Map.notMember` missing)
    changed a b = if a == b then Nothing else Just a
    captionFace st = let c = paraStyle st (Just "caption") in Face (c >>= psFont) (cssFontSize st <$> (c >>= psSize))
    sidenoteFace st = let d = paraStyle st (Just "sidenote") in Face (d >>= psFont) (cssFontSize st <$> (d >>= psSize))
    tableFace st n = let d = paraStyle st (Just n) in Face (d >>= psFont) (cssFontSize st <$> (d >>= psSize))
    forParagraphs = if "table" `elem` paragraphStyles then id else Map.delete "table"
    paragraphStyles = [styleRefName n | Document _ bs <- bookDocs book, Block _ _ _ (Paragraph (Just n) _) <- universeOf bs]
    anonymous = keyedStyleRefs (concatMap docBlocks (bookDocs book))
    anonymousFace r = let d = paraStyleWith style (Just (styleRefName r)) (anonymousValues r) in Face (d >>= psFont) (cssFontSize style <$> (d >>= psSize))
    tableFaces st = Map.fromList [(n, tableFace st n) | n <- "table" : tableStyles]
    tableStyles = Set.toList (Set.fromList [n | Document _ bs <- bookDocs book, Block _ _ _ (TableBlock Table {tableStyle = Just (StyleRef n _)}) <- universeOf bs])
    universeOf = concatMap (\b -> b : universeOf (innerOf (blockBody b)))
    innerOf = \case
      BulletList items -> concatMap itemBlocks items
      OrderedList items -> concatMap itemBlocks items
      DefList gs -> concat (concatMap dgDefs gs)
      FigureBlock f -> figCaption f
      FrameBlock _ bs -> bs
      _ -> []
    ruby = compRuby (stComposition style)

-- | Writes the HTML site to build/html: its pages, its CSS, its index and its images, in the HTML syntax (root ADR 0432).
writeHtmlTarget :: FilePath -> HtmlConfig -> FileTable -> Book -> XhtmlSite -> IO ([FilePath], [Diagnostic], Maybe (BS.ByteString, View))
writeHtmlTarget root hcfg ft book site = do
  let dir = root </> "build" </> "html"
  cleanDir dir
  forM_ (sitePages site) $ \(p, t) -> writeUtf8File (dir </> p) t
  writeUtf8File (dir </> "style.css") (siteCss site)
  writeUtf8File (dir </> "index.html") (indexPage hcfg ft book)
  -- the images plugins made are written from the book (docs/adr/0123)
  copied <- forM (siteAssets site) $ \(o, src) -> do
    case Map.lookup (T.pack src) (bookImages book) of
      Just bytes -> createDirectoryIfMissing True (takeDirectory (dir </> o)) >> BS.writeFile (dir </> o) bytes
      Nothing -> copyFileInto (root </> src) (dir </> o)
    pure (dir </> o)
  pure (map ((dir </>) . fst) (sitePages site) <> [dir </> "style.css", dir </> "index.html"] <> copied, [], Nothing)

-- | Convert only monochrome assets; generated PNG paths cannot shadow an existing asset.
recolorWebFigures :: BuildOptions -> Style -> Book -> XhtmlSite -> IO (Book, [Diagnostic])
recolorWebFigures opts style book site = case figureColor style of
  Nothing -> pure (book, [])
  Just swatch -> do
    checked <- forM (nub (map snd (siteAssets site))) $ \path -> do
      let lower = T.toLower (T.pack path)
          svg = ".svg" `T.isSuffixOf` lower
          raster = any (`T.isSuffixOf` lower) [".png", ".jpg", ".jpeg"]
      result <-
        if not (svg || raster)
          then pure (Right Nothing)
          else do
            readResult <- try (maybe (filesRead (optFiles opts) path) pure (Map.lookup (T.pack path) (bookImages book))) :: IO (Either IOException BS.ByteString)
            case readResult of
              Left problem -> pure (Left (T.pack (show problem)))
              Right bytes
                -- With a swatch this check belongs to the conversion boundary:
                -- G08113 also removes stale target outputs (root ADR 0407).
                | svg, Just why <- activeMessage (T.pack path) (activeContent bytes) -> pure (Left why)
                | svg -> pure $ case Svg.readSvg bytes of
                    Left problem -> Left $ case problem of
                      Svg.SvgMalformed why -> why
                      Svg.SvgUnsupported _ -> "SVG の色の変換で扱えない要素または属性があります"
                    Right parsed ->
                      let original = P.SvgFigure (svgDrawing parsed)
                       in case recolorFigure swatch original of
                            P.SvgFigure drawing | P.SvgFigure drawing /= original -> Right (Just (False, TE.encodeUtf8 (drawingSvg drawing)))
                            _ -> Right Nothing
                | otherwise -> fmap (fmap (fmap (\(_, png) -> (True, png)))) (safeRecolorRasterBytes swatch bytes)
      pure (T.pack path, result)
    let failures = Map.fromList [(path, why) | (path, Left why) <- checked]
        diagnostics = [diagnostic "G08113" Error sp ("図版の色を変換できません: " <> webSource f <> "（" <> why <> "）") | Document _ bs <- bookDocs book, Block sp _ _ (FigureBlock f) <- allFigures bs, Just why <- [Map.lookup (webSource f) failures]]
        taken = Set.fromList (Map.keys (bookImages book) <> [T.pack path | (out, src) <- siteAssets site, path <- [out, src]])
        (paths, images, _) = foldl' allocate (Map.empty, Map.empty, taken) [(path, png, bytes) | (path, Right (Just (png, bytes))) <- checked]
        allocate (pathMap, imageMap, used) (path, png, bytes) =
          let jpeg = any (`T.isSuffixOf` T.toLower path) [".jpg", ".jpeg"]
              base = "images/golem-color/" <> hex (P.sha256 bytes)
              candidate n = base <> (if n == (0 :: Int) then "" else "-" <> T.pack (show n)) <> ".png"
              unused n = if Set.member (candidate n) used then unused (n + 1) else candidate n
              target = if png && jpeg then unused 0 else path
           in (Map.insert path target pathMap, Map.insert target bytes imageMap, Set.insert target used)
        rewrite block' =
          block'
            { blockBody = case blockBody block' of
                FigureBlock f -> let old = webSource f; target = Map.findWithDefault old old paths in FigureBlock f {figWeb = if target == old then figWeb f else Just target, figCaption = map rewrite (figCaption f)}
                BulletList items -> BulletList [item {itemBlocks = map rewrite (itemBlocks item)} | item <- items]
                OrderedList items -> OrderedList [item {itemBlocks = map rewrite (itemBlocks item)} | item <- items]
                DefList groups -> DefList [group {dgDefs = map (map rewrite) (dgDefs group)} | group <- groups]
                FrameBlock name bs -> FrameBlock name (map rewrite bs)
                other -> other
            }
        docs = [Document fid (map rewrite bs) | Document fid bs <- bookDocs book]
    pure (book {bookDocs = docs, bookImages = Map.union images (bookImages book)}, diagnostics)
  where
    hex = T.pack . concatMap (\byte -> let value = showHex byte "" in replicate (2 - length value) '0' <> value) . BS.unpack

-- | Writes the EPUB of the site to build/epub/book.epub.
writeEpubTarget :: BuildOptions -> Evaluated -> HtmlConfig -> FileTable -> Book -> XhtmlSite -> IO ([FilePath], [Diagnostic], Maybe (BS.ByteString, View))
writeEpubTarget opts e hcfg ft book site = do
  let project = evProject e
      manifest = projectManifest project
      style = evStyle e
      root = optRoot opts
      dir = root </> "build" </> "epub"
      out = dir </> "book.epub"
      isbn = fromMaybe Nothing (tgEpub (manifestTargets manifest))
      cfg = epubConfig (manifestMetadata manifest) isbn (maybe False pageVertical (stPage style))
      report (code, message) = ([], [diagnostic code Error (mkSpan (projectManifestFile project) 0 0) ("EPUB の page-map を読み込めません: " <> message)], Nothing)
  pageMap <- case tgEpubPageMap (manifestTargets manifest) of
    Nothing -> pure (Right (Map.empty, []))
    Just path -> do
      resolved <- filesResolve (optFiles opts) path
      case resolved of
        Left err -> pure (Left (if err == Missing then "G03272" else "G03273", T.pack path <> ": " <> T.pack (pathErrorMessage err)))
        Right rel -> do
          readResult <- try (filesRead (optFiles opts) rel) :: IO (Either IOException BS.ByteString)
          pure $ do
            bytes <- first (\err -> ("G03273", T.pack path <> ": " <> T.pack (show err))) readResult
            mapping <- first pageMapFailure (decodePageMap (BL.fromStrict bytes))
            first pageMapFailure $ resolvePageMapWithAst (Map.map sfAst (projectSources project)) (Map.map (\source -> (sfPath source, sfText source)) (projectSources project)) ft book mapping
  case pageMap of
    Left problem -> cleanDir dir >> pure (report problem)
    Right (anchors, links) -> do
      let epubSite = if Map.null anchors then site else renderXhtmlWithPageBreaks hcfg ft book anchors
      cleanDir dir
      createDirectoryIfMissing True dir
      writeEpub root out cfg {epPageList = links} ft book epubSite
      pure ([out], [], Nothing)

-- | Distinct causes of an invalid page map (root ADR 0386).
pageMapFailure :: PageMapError -> (Text, Text)
pageMapFailure = \case
  PageMapJson why -> ("G03274", why)
  PageMapSchema why -> ("G03275", why)
  PageMapStale why -> ("G03276", why)
  PageMapPosition why -> ("G03277", why)

-- | Writes the plain text of each variant to build/text; @dev@ for the profile dev.
writeTextTarget :: FilePath -> Bool -> Evaluated -> Map Text [EntryPart] -> FileTable -> Book -> IO ([FilePath], [Diagnostic], Maybe (BS.ByteString, View))
writeTextTarget root dev e bib ft book = do
  let manifest = projectManifest (evProject e)
      style = evStyle e
      md = manifestMetadata manifest
      dir = root </> "build" </> "text"
      -- without [targets.text], both variants, as when variants is omitted (golem-cli ADR 0002)
      variants = case tgText (manifestTargets manifest) of
        [] -> [TextVertical, TextHorizontal]
        vs -> vs
  cleanDir dir
  files <- forM variants $ \v -> do
    let (sub, gv) = case v of
          TextVertical -> ("vertical", GT.Vertical)
          TextHorizontal -> ("horizontal", GT.Horizontal)
    -- each document with the indents of its style (docs/adr ADR 0014)
    let pages = GT.renderText (mdLanguage md) (stNumbersVertical style) dev (textIndents . docStyles e) (textLists style) (stTableCaption style == CaptionBelow) bib gv ft book
    forM pages $ \(p, t) -> do
      writeUtf8File (dir </> sub </> p) t
      pure (dir </> sub </> p)
  pure (concat files, [], Nothing)

{- | Writes the PDF for print to build/pdf with pages.json, where each of
its pages starts in the source (docs/adr ADR 0195), when @printed@, and the
PDF for the screen of the same layout to build/pdf-screen when @screen@
(root ADR 0431), or keeps the PDF for print in memory with its view for
golem preflight (@inMemory@), with the notices of the PDF.
-}
writePdfTarget :: Bool -> Bool -> Bool -> BuildOptions -> Evaluated -> FileId -> Book -> Map Text [EntryPart] -> IO ([FilePath], [Diagnostic], Maybe (BS.ByteString, View))
writePdfTarget inMemory printed screen opts e diagFid book bib = do
  let root = optRoot opts
      project = evProject e
      style = evStyle e
      dir = root </> targetOutputDir TargetPdf
      screenDir = root </> targetOutputDir TargetPdfScreen
      name = pdfFileName (mdId (manifestMetadata (projectManifest project)))
      out = dir </> name
      screenOut = screenDir </> name
      pagesOut = dir </> "pages.json"
      dirs = [dir | printed] <> [screenDir | screen]
      -- the PDF/UA of [targets.pdf-screen] (root ADR 0431)
      screenUa = if screen then Just (join (tgPdfScreen (manifestTargets (projectManifest project)))) else Nothing
  r <- renderPdfOutputs printed screenUa golemVersion (optFonts opts) (pdfInputOf opts e diagFid book bib)
  -- G08008: code in the body role without [fonts.code] (golem-driver ADR 0017)
  -- G07045: kenten the PDF does not draw, with ruby (golem-driver ADR 0019)
  let fontNotice = codeFontNotice diagFid style book <> kentenRubyNotices book
  case r of
    Left ds -> do
      when (not inMemory && any ((`elem` [DiagnosticCode "G08113", DiagnosticCode "G07145"]) . diagCode) ds) (mapM_ cleanDir dirs)
      pure ([], ds <> fontNotice, Nothing)
    Right (bytes, notices, view, starts, screenBytes)
      -- golem preflight keeps the PDF in memory (golem-cli ADR 0006)
      | inMemory -> pure ([], notices <> fontNotice <> glyphs, Just (bytes, view))
      -- G08100, G08103, G07127 and G07128 are errors in prod and stop the PDF; the PDF of an earlier build goes too (docs/adr 0081, docs/adr/0268, docs/adr/0389)
      -- G07128 is reported by buildCore, and only stops the PDF here
      | hasErrors (map (adjustForProfile (optProfile opts)) (glyphs <> notices <> pdfSidenoteIndents opts e diagFid)) -> do
          mapM_ cleanDir dirs
          pure ([], notices <> fontNotice <> glyphs, Nothing)
      | otherwise -> do
          printedFiles <-
            if printed
              then do
                cleanDir dir
                createDirectoryIfMissing True dir
                BS.writeFile out bytes
                -- where each page starts in the source, next to the PDF (docs/adr ADR 0195)
                writeUtf8File pagesOut (pagesJson (Map.map (\sf -> (sfPath sf, sfText sf)) (projectSources project)) starts)
                pure [out, pagesOut]
              else pure []
          -- the PDF for the screen alone, without pages.json (root ADR 0431)
          screenFiles <- case screenBytes of
            Just sb | screen -> do
              cleanDir screenDir
              createDirectoryIfMissing True screenDir
              BS.writeFile screenOut sb
              pure [screenOut]
            _ -> pure []
          pure (printedFiles <> screenFiles, notices <> fontNotice <> glyphs, Nothing)
      where
        -- G08100: the characters drawn as glyph 0, from the characters of the view (docs/adr 0081)
        glyphs = [(diagnostic "G08100" Warning (mgSpan m) (mgMessage m)) {diagFacts = mgFacts m} | m <- missingGlyphs view]

-- | G07128 of an evaluated project, as the PDF is set (docs/adr/0389).
pdfSidenoteIndents :: BuildOptions -> Evaluated -> FileId -> [Diagnostic]
pdfSidenoteIndents opts e diagFid = sidenoteIndentDiagnostics diagFid (isJust (markStyle (optMarks opts))) (evStyle e) (Map.elems (localStylesOf e))

-- | The input of the PDF of an evaluated project.
pdfInputOf :: BuildOptions -> Evaluated -> FileId -> Book -> Map Text [EntryPart] -> PdfInput
pdfInputOf opts e diagFid book bib =
  let project = evProject e
      -- the manifest, style.toml, the sources and the options that change the output (golem-pdf ADR 0004)
      inputs = projectManifestText project : evStyleText e : [sfText sf | sf <- Map.elems (projectSources project)] <> [optionsInput opts]
   in PdfInput (optFiles opts) project (evStyle e) book (optParallel opts) (map TE.encodeUtf8 inputs) bib (markStyle (optMarks opts)) (localStylesOf e) (Map.fromList [(fid, m) | (fid, Just m) <- projectChapters project]) diagFid (fst (runningVars e)) (projectVarTexts (manifestVars (projectManifest project))) (evStyleText e)

-- | Evaluate and compose the body, without serializing or writing a PDF.
manuscriptLines :: BuildOptions -> IO (Either (Map FileId SourceInfo, [Diagnostic]) ([Text], Integer))
manuscriptLines opts = do
  ev <- evaluateProjectWith (optFiles opts) Map.empty (optProfile opts) (optRoot opts)
  case ev of
    Left failure -> pure (Left (pfSources failure, pfDiagnostics failure))
    Right e -> do
      let sources = withEvaluatedSources e (sourceInfos (evProject e))
          failure ds = Left (sources, ds)
      case evBook e of
        Just book | not (hasErrors (evDiagnostics e)) -> do
          (ds, _, bib) <- loadBibliography (optFiles opts) (projectManifest (evProject e))
          if hasErrors ds
            then pure (failure ds)
            else do
              result <- masterFlowText (optFonts opts) (pdfInputOf opts e (evStyleFile e) book bib)
              pure (either failure Right result)
        _ -> pure (failure (evDiagnostics e))

{- | The structure tree of the PDF of a project as text (docs/adr ADR 0183),
for the tests: what the PDF would be tagged with.
-}
pdfStructure :: BuildOptions -> IO (Either [Diagnostic] Text)
pdfStructure opts = do
  ev <- evaluateProjectWith (optFiles opts) Map.empty (optProfile opts) (optRoot opts)
  case ev of
    Left f -> pure (Left (pfDiagnostics f))
    Right e -> case evBook e of
      Nothing -> pure (Left (evDiagnostics e))
      Just book -> do
        (_, _, bib) <- loadBibliography (optFiles opts) (projectManifest (evProject e))
        renderPdfStructure golemVersion (optFonts opts) (pdfInputOf opts e (evStyleFile e) book bib)

{- | Each leaf of the structure tree of the PDF of a project with the
text it draws in the order of the content streams and the text of its
glyphs in the order of the text, for the tests (docs/adr ADR 0227).
-}
pdfLeafTexts :: BuildOptions -> IO (Either [Diagnostic] [(P.LeafId, Text, Text)])
pdfLeafTexts opts = do
  ev <- evaluateProjectWith (optFiles opts) Map.empty (optProfile opts) (optRoot opts)
  case ev of
    Left f -> pure (Left (pfDiagnostics f))
    Right e -> case evBook e of
      Nothing -> pure (Left (evDiagnostics e))
      Just book -> do
        (_, _, bib) <- loadBibliography (optFiles opts) (projectManifest (evProject e))
        renderPdfLeafTexts golemVersion (optFonts opts) (pdfInputOf opts e (evStyleFile e) book bib)

{- | The PDF of a project with its structure tree changed by a function
before it is checked and written, for the tests of G07107 only (docs/adr
ADR 0216): a stand-in for a mistake of Golem.
-}
pdfWithTree :: (P.StructElem -> P.StructElem) -> BuildOptions -> IO (Either [Diagnostic] BS.ByteString)
pdfWithTree tamper opts = do
  ev <- evaluateProjectWith (optFiles opts) Map.empty (optProfile opts) (optRoot opts)
  case ev of
    Left f -> pure (Left (pfDiagnostics f))
    Right e -> case evBook e of
      Nothing -> pure (Left (evDiagnostics e))
      Just book -> do
        (_, _, bib) <- loadBibliography (optFiles opts) (projectManifest (evProject e))
        renderPdfWithTree tamper golemVersion (optFonts opts) (pdfInputOf opts e (evStyleFile e) book bib)

{- | The PDF of a project with the destinations of its links inside the
document changed by a function before they are used, for the tests of
G07120 only (docs/adr/0267): a stand-in for a mistake of Golem.
-}
pdfWithDests :: (Map.Map LinkDest P.Dest -> Map.Map LinkDest P.Dest) -> BuildOptions -> IO (Either [Diagnostic] BS.ByteString)
pdfWithDests tamper opts = do
  ev <- evaluateProjectWith (optFiles opts) Map.empty (optProfile opts) (optRoot opts)
  case ev of
    Left f -> pure (Left (pfDiagnostics f))
    Right e -> case evBook e of
      Nothing -> pure (Left (evDiagnostics e))
      Just book -> do
        (_, _, bib) <- loadBibliography (optFiles opts) (projectManifest (evProject e))
        renderPdfWithDests tamper golemVersion (optFonts opts) (pdfInputOf opts e (evStyleFile e) book bib)

-- | Removes a folder and what it holds, if it is there.
cleanDir :: FilePath -> IO ()
cleanDir dir = do
  ex <- doesDirectoryExist dir
  when ex (removeDirectoryRecursive dir)

-- | Writes a text in UTF-8 whatever the locale (docs/adr/0002-determinism.md), with its folders.
writeUtf8File :: FilePath -> Text -> IO ()
writeUtf8File p t = createDirectoryIfMissing True (takeDirectory p) >> BS.writeFile p (TE.encodeUtf8 t)

-- | Copies a file, with the folders of its destination.
copyFileInto :: FilePath -> FilePath -> IO ()
copyFileInto src dst = createDirectoryIfMissing True (takeDirectory dst) >> BS.readFile src >>= BS.writeFile dst

{- | The markers of [lists] in plain text (golem-driver ADR 0013): a gap is
written when [lists] gap is not 0, or by the last character without it.
-}
textLists :: Style -> GT.TextLists
textLists style =
  let l = stLists style
      nonZero = \case
        Abs x -> x /= 0
        Zw r -> r /= 0
   in GT.TextLists (textBullets l) (lsNumbers l) (nonZero <$> lsGap l)

{- | The ideographic spaces that start the lines of a paragraph of a style
in plain text, when indent and first-line-indent are both in zw, none
otherwise (docs/adr ADR 0006): the whole part of their sum before the
first line, and before each line after a line break the same in a keep
paragraph, the whole part of indent in a join paragraph (docs/adr ADR
0049); never negative.
-}
textIndents :: Style -> Maybe Text -> (Int, Int)
textIndents style st = case paraStyle style st of
  Just ParaStyleDef {psIndent = Just (Zw a), psFirstLineIndent = Just (Zw b), psLineBreaks = lb} ->
    let firstLine = max 0 (truncate (a + b))
     in (firstLine, if lb == Just KeepLines then firstLine else max 0 (truncate a))
  _ -> (0, 0)
