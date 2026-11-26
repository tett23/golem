{- | The evaluation of a project (root ADR 0434): project → parse → S0 →
S1, with the plugins, the functions of the .emet, the assets and the
bibliography. golem-driver writes the outputs from what this evaluates.
-}
module Golem.Evaluate
  ( Evaluated (..),
    evaluateProject,
    evaluateProjectWith,
    evaluateLoose,
    hostContext,
    functionPaths,
    loadBibliography,
    metadataValues,
    localStylesOf,
    docStyles,
    runningVars,
    projectVarTexts,
    sourceInfos,
    withEvaluatedSources,
    assetRefs,
    AssetUse (..),
    keepStyles,
    sourceSettingsOf,
    builtinKeepStyles,
    isPresent,
    readMaybeBytes,
    readMaybeText,
  )
where

import Control.Applicative ((<|>))
import Control.Exception (SomeException, try)
import Control.Monad (forM)
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (fromRight, lefts, rights)
import Data.List (nub, sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isNothing, listToMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Unsafe (lengthWord8)
import Data.Time.Calendar (showGregorian, toGregorian)
import Golem.Assemble
import Golem.Bibliography (CslEntry (..), EntryPart, formatEntry)
import Golem.Bibliography.Csl (CslJsonError (..), decodeCslJson)
import Golem.Doc.IR
import Golem.Emet (Export (..), Handlers (..), Kind (..), Program, programExports)
import Golem.Emet.Gm (filterOf, functionNamespaces, separatorFunction)
import Golem.Eval.Builtin (unPluginCommandName)
import Golem.Eval.Expr (embedValue, evalExpr, plainEnv)
import Golem.Eval.File
import Golem.Eval.Functions (BlockFunction (..), FunctionTable (..), noFunctions)
import Golem.Eval.Value
import Golem.Evaluate.Functions (LoadedFunctions (..), RequiredFiles (..), loadFunctions, loadRequiredFiles, requiredFileSet, requirementHandlers)
import Golem.Evaluate.Plugins (FunctionFilter, HostContext (..), LoadedPlugins (..), defaultCacheDir, loadPlugins)
import Golem.Evaluate.ProjectVars (projectVarDiagnostics, projectVarTexts)
import Golem.Evaluate.TitleFormats (localTitleFormatDiagnostics, resolveTitleFormats, titleFormatSetDiagnostics, titleFormatStyleDiagnostics, titleFormatsOf)
import Golem.Evaluate.Verse (numberVerseDocument)
import Golem.Parser (parseAst)
import Golem.Parser.AST qualified as A
import Golem.Parser.Read (ReadFailure (..), checkText, readInfo, readSourceFile, readTableSource)
import Golem.Parser.SourceSettings (SourceSettings, defaultSourceSettings)
import Golem.Project
import Golem.Project.Files (Files (..), diskFiles)
import Golem.Project.Paths (PathError (..), normalizeRelative, pathErrorMessage)
import Golem.Project.Style
import Golem.Syntax

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
    -- | the diagnostics of the project stage: G03007, G03023, G03120, plugins, the bibliography, table files (golem-lsp ADR 0004)
    evProjectDiagnostics :: ![Diagnostic],
    -- | the diagnostics of S1 (golem-lsp ADR 0004)
    evS1Diagnostics :: ![Diagnostic],
    {- | S1 again from the S0 results of every file, in the context of the
    last evaluation; without S1 when there is an error among the
    diagnostics of the project stage and of S0 (golem-lsp ADR 0004).
    -} evReassemble :: Map FileId EvalResult -> (Maybe Book, [Diagnostic]),
    {- | S0 of one file again, in the context of the last evaluation
    (the LSP re-evaluates the edited file alone when nothing that other
    files depend on has changed).
    -} evReevaluate :: FileId -> SourceFile -> EvalResult,
    {- | the names of the commands of the plugins, in order, for completion;
    empty when the plugins failed to load (docs/adr ADR 0031)
    -} evPluginCommands :: ![Text],
    {- | the functions of the .emet the project uses (docs/adr/0162): the
    program, Nothing after an error, and the .emet read
    -} evFunctions :: !(Maybe Program),
    evFunctionSources :: !(Map FileId SourceInfo)
  }

-- | The styles each file defines, of the files that define any (docs/adr ADR 0014).
localStylesOf :: Evaluated -> Map FileId LocalStyles
localStylesOf = Map.filter (/= noLocalStyles) . Map.map erStyles . evResults

-- | The style of each document: style.toml with the styles its file defines over it.
docStyles :: Evaluated -> FileId -> Style
docStyles e fid = maybe (evStyle e) (withLocalStyles (evStyle e)) (Map.lookup fid (localStylesOf e))

{- | The FileId of plugins.lock, where G06011 points (golem-plugin ADR 0003):
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

{- | The context of the book a plugin may ask for (docs/adr/0121): the
values the layout uses, horizontal writing without [page] and kanji
without [numbers] vertical.
-}
hostContext :: Style -> HostContext
hostContext style = HostContext (if maybe False pageVertical (stPage style) then "vertical" else "horizontal") (stNumbersVertical style)

-- | Everything up to S1. Stops after a stage that produced errors.
evaluateProject :: Profile -> FilePath -> IO (Either ProjectFailure Evaluated)
evaluateProject profile root = evaluateProjectWith (diskFiles root) Map.empty profile root

{- | @files@ reads the files of the project (docs/adr/0199); @overlay@
replaces file contents (unsaved edits in the LSP).
-}
evaluateProjectWith :: Files -> Map FilePath Text -> Profile -> FilePath -> IO (Either ProjectFailure Evaluated)
evaluateProjectWith files overlay profile root = do
  lp <- loadProjectWith files overlay root
  case lp of
    Left f -> pure (Left f)
    Right project -> do
      styleBytes <- readMaybeBytes files "style.toml"
      let -- G03023: the default style, when there is no style.toml (golem-syntax ADR 0002)
          defaultStyleNotice = [notice "G03023" (mkSpan (projectManifestFile project) 0 0) "style.toml がないので、既定の体裁で組みます" | isNothing styleBytes]
          -- G03120: no paragraph-separator in [source], read in the line style (docs/adr/0193)
          defaultSeparatorNotice = [notice "G03120" (mkSpan (projectManifestFile project) 0 0) "段落の区切り方を書いていないので、改行の様式（paragraph-separator = \"line\"）で読みます" | not (manifestParagraphSeparatorWritten (projectManifest project))]
          manifest0 = projectManifest project
          styleFid = styleFileId project
      -- style.toml passes the reading stage too (golem-parser ADR 0009)
      let styleRead = traverse (readSourceFile styleFid "style.toml") styleBytes
          styleText = fromRight Nothing styleRead
          -- G03100: a zero indent of table (golem-driver ADR 0043, docs/adr/0367)
          styleNoticeDiags = maybe [] (styleNotices styleFid) styleText
          synDiags = defaultStyleNotice <> defaultSeparatorNotice <> styleNoticeDiags <> concatMap sfSyntaxDiagnostics (Map.elems (projectSources project))
      case first (map noFix . rfDiagnostics) styleRead >>= loadStyle styleFid of
        -- style.toml is where its errors point (golem-project ADR 0006)
        Left ds -> pure (Left (ProjectFailure ds (Map.insert styleFid (maybe (SourceInfo "style.toml" (mkLineIndex "")) (readInfo "style.toml") styleBytes) (sourceInfos project))))
        Right style -> do
          {- the plugins are loaded with or without a syntax error: loading
          reads the manifest, plugins.lock and the cache, not the sources
          (docs/adr ADR 0031) -}
          cacheDir <- defaultCacheDir
          lockText <- readMaybeText files "plugins.lock"
          -- the files functions may read, whether or not a chapter calls a function (docs/adr/0161)
          required <- loadRequiredFiles files overlay (projectManifestFile project) manifest0
          -- the functions of the .emet of @import and [[filters]] (docs/adr/0162)
          (filterRootDiags, emetRoots) <- functionRoots files project style
          functions <-
            if null emetRoots
              then pure (LoadedFunctions [] Map.empty Nothing)
              else loadFunctions files overlay (functionsFileBase project) manifest0 emetRoots
          let handlers = requirementHandlers required
              table = functionTableOf handlers project emetRoots functions
              functionFilter = functionFilterOf handlers project (lfProgram functions)
              filterNameDiags = unknownFilters project (lfProgram functions)
          LoadedPlugins hookE checkWarnings pluginSources <- loadPlugins root overlay cacheDir (projectManifestFile project) (lockFileId project) (fromMaybe "" lockText) (dataFileBase project) (hostContext style) functionFilter manifest0
          -- after the plugins failed, a name one might have given is G02282 (root ADR 0461)
          let (pluginErrors, hook) = either (,noPlugins {phFailed = True}) ([],) hookE
              -- the warnings of the checks of the data (docs/adr/0120) do not stop the plugins
              pluginDiags = pluginErrors <> checkWarnings <> rqDiagnostics required <> filterRootDiags <> lfDiagnostics functions <> filterNameDiags
              functionFiles = Set.fromList [siPath si | si <- Map.elems (lfSources functions)]
              pluginCommands = sort (map unPluginCommandName (Map.keys (phCommands hook)))
              -- G03111 and G03112 of {vars.<name>} of the running heads, once for the project (docs/adr/0185)
              -- and G03297 to G03299 of the title formats of style.toml, once for each slot (root ADR 0463)
              runningVarDiags = projectVarDiagnostics styleFid (fromMaybe "" styleText) (manifestVars manifest0) <> titleFormatStyleDiagnostics styleFid (fromMaybe "" styleText) manifest0
              -- style.toml, which the context comes from, when a plugin asks for it: the LSP watches it (docs/adr/0121)
              contextFiles = Set.fromList ["style.toml" | not (null (phContextNames hook))]
          if hasErrors synDiags
            then do
              loaded <- loadAssets files overlay table hook project
              let assets = laAssets loaded
              (bibDiags, citeKeys, _) <- loadBibliography files manifest0
              let projectDiags = pluginDiags <> laDiagnostics loaded <> bibDiags <> runningVarDiags
              pure (Right (Evaluated project style styleFid (fromMaybe "" styleText) lockText Map.empty Nothing (synDiags <> projectDiags) (laSources loaded <> pluginSources <> lfSources functions) (laTableFiles loaded <> pluginDataFiles manifest0 <> requiredFileSet manifest0 <> contextFiles <> functionFiles) projectDiags [] (const (Nothing, [])) (reeval profile project style assets citeKeys hook table Map.empty) pluginCommands (lfProgram functions) (lfSources functions)))
            else do
              let manifest = manifest0
                  -- one G03007 for each name, in the order of the chapters (golem-project ADR 0006)
                  masterDiags =
                    [ diagnostic "G03007" Error (mkSpan (projectManifestFile project) 0 0) ("style.toml にないマスターページです: " <> m)
                    | m <- nub [m | (_, Just m) <- projectChapters project],
                      not (Map.member m (stMasters style))
                    ]
              loaded <- loadAssets files overlay table hook project
              let assets = laAssets loaded
              -- G03026 and G03003 of the bibliography, for every target (golem-doc ADR 0004)
              (bibDiags, citeKeys, _) <- loadBibliography files manifest
              let results = evalAll profile project style assets citeKeys hook table
                  s0Diags = concatMap erDiagnostics (Map.elems results)
                  -- the syntax diagnostics short of errors: the info G01031 (root ADR 0459)
                  syntaxInfos = concatMap sfSyntaxDiagnostics (Map.elems (projectSources project))
                  projectDiags = defaultStyleNotice <> defaultSeparatorNotice <> styleNoticeDiags <> syntaxInfos <> masterDiags <> runningVarDiags <> pluginDiags <> laDiagnostics loaded <> bibDiags
                  reassemble = assembleResults (phChannels hook) handlers (lfProgram functions) style styleFid (fromMaybe "" styleText) manifest project projectDiags
                  (book, s1Diags) = reassemble results
                  again = reeval profile project style assets citeKeys hook table results
              pure (Right (Evaluated project style styleFid (fromMaybe "" styleText) lockText results book (projectDiags <> s0Diags <> s1Diags) (laSources loaded <> pluginSources <> lfSources functions) (laTableFiles loaded <> pluginDataFiles manifest0 <> requiredFileSet manifest0 <> contextFiles <> functionFiles) projectDiags s1Diags reassemble again pluginCommands (lfProgram functions) (lfSources functions)))

{- | The files the plugins take as data (docs/adr/0105) and the .wasm of
the plugins of the project (docs/adr/0109), which the LSP watches with
the files of @table: a change of one evaluates the project again. Paths
of the wrong shape are left out; G03003 reports them.
-}
pluginDataFiles :: Manifest -> Set.Set FilePath
pluginDataFiles m = Set.fromList [rel | d <- Map.elems (manifestPlugins m), Right rel <- map normalizeRelative (ownPath d <> Map.elems (pdData d))]
  where
    ownPath d = case pdSource d of
      PluginPath p -> [p]
      PluginUrl _ -> []

{- | S1 from the S0 results of the files (golem-lsp ADR 0004): the book
and the diagnostics of S1; nothing when the diagnostics of the project
stage or of S0 have an error.
-}
assembleResults :: Map Text ChannelDecl -> Handlers -> Maybe Program -> Style -> FileId -> Text -> Manifest -> Project -> [Diagnostic] -> Map FileId EvalResult -> (Maybe Book, [Diagnostic])
assembleResults channels handlers program style styleFid styleText manifest project projectDiags results
  | hasErrors (projectDiags <> concatMap erDiagnostics (Map.elems results) <> localFormatDiags) = (Nothing, localFormatDiags)
  | otherwise =
      let -- the chapter of the manifest of each file: a top-level entry, a nested array as one (golem-driver ADR 0018)
          chapterOfFile = [i | (i, e) <- zip [0 :: Int ..] (manifestChapters manifest), _ <- chapterFiles [e]] <> [length (manifestChapters manifest) ..]
          chapterRuns = [(erDocument r, ch) | ((fid, _), ch) <- zip (projectChapters project) chapterOfFile, Just r <- [Map.lookup fid results]]
          (resolvedDocs, resolvedSeparators, separatorDiags) = resolveSeparators handlers program style styleFid styleText (map fst chapterRuns)
          -- where G04007 points (golem-syntax ADR 0002)
          numberSites = Map.unions (map erNumberSites (Map.elems results))
          cfg = AssembleConfig (Map.mapMaybe hsNumber (stHeadings style)) (stFigureNumber style) numberSites (stNotesNumbering style) (map snd chapterRuns) (cdNumber (stCode style)) (stTableNumber style) channels pageLines (stNotesNumbering (endnoteStyle style))
          -- the lines of a page; without [page.grid], no limit (docs/adr ADR 0047)
          pageLines = maybe maxBound (fromIntegral . gridLines) (stPage style >>= pageGrid)
          (book, s1Diags) = assemble cfg evalDeferred resolvedDocs
          -- the separators between numbers and titles, by file: a heading's from
          -- its [headings.<l>], a caption's from the paragraph style caption (Golem ADR 0372)
          separators =
            Map.fromList
              ( [ ((fid, Nothing), separator)
                | (fid, r) <- Map.toList results,
                  Just separator <- [paraStyle (withLocalStyles style (erStyles r)) (Just "caption") >>= psNumberTitleSeparator]
                ]
                  <> [ ((fid, Just l), separator)
                     | fid <- Map.keys results,
                       (l, h) <- Map.toList (stHeadings style),
                       Just separator <- [hsNumberTitleSeparator h]
                     ]
              )
          -- the title formats of the numbered headings and captions, their variables in place (root ADR 0463)
          formats = titleFormatsOf style results
          fileVar = fileVariable project results
          formatDiags = titleFormatSetDiagnostics fileVar formats book
          numberedDocs =
            [ numberVerseDocument (maybe style (withLocalStyles style . erStyles) (Map.lookup fid results)) doc
            | doc@(Document fid _) <- bookDocs book
            ]
          -- G03289: a @frame of a name [frames] does not have (root ADR 0438)
          frameDiags =
            [ diagnostic "G03289" Error sp ("[frames] にないフレームの名前です: " <> name)
            | Document _ bs <- resolvedDocs,
              Block sp _ _ (FrameBlock name _) <- framesIn bs,
              Map.notMember name (stFrames style)
            ]
       in (Just book {bookDocs = numberedDocs, bookTitleSeparators = separators, bookTitleFormats = resolveTitleFormats fileVar manifest formats, bookImages = Map.unions (map erImages (Map.elems results)), bookSeparators = resolvedSeparators}, localFormatDiags <> separatorDiags <> frameDiags <> formatDiags <> s1Diags)
  where
    -- G03297 to G03299 of the title formats of @style-def, at the definitions (root ADR 0463)
    localFormatDiags = localTitleFormatDiagnostics manifest project results

-- | The text frames of blocks, at any depth, in order (root ADR 0438).
framesIn :: [Block] -> [Block]
framesIn = concatMap $ \b -> case blockBody b of
  FrameBlock {} -> [b]
  BulletList items -> framesIn (concatMap itemBlocks items)
  OrderedList items -> framesIn (concatMap itemBlocks items)
  DefList gs -> framesIn (concat (concatMap dgDefs gs))
  _ -> []

-- | Resolve names only after plugin and Emet filters have run (root ADR 0398).
resolveSeparators :: Handlers -> Maybe Program -> Style -> FileId -> Text -> [Document] -> ([Document], Map (SrcSpan, Text) SeparatorAppearance, [Diagnostic])
resolveSeparators handlers program style styleFid styleText docs =
  let (docs', pairs) = unzip [let (bss, entries) = unzip (map resolveBlock bs) in (Document fid (concat bss), concat entries) | Document fid bs <- docs]
      appearances = Map.fromList [(key, appearance) | Right (key, appearance) <- concat pairs]
      diagnostics = lefts (concat pairs)
   in (docs', appearances, diagnostics)
  where
    fontSize = maybe 0 (dimToSp 0 . gridFontSize) (stPage style >>= pageGrid)
    dimension = unSp . dimToSp fontSize
    stroke = \case
      RuleSolid -> StrokeSolid
      RuleMulti ratios -> StrokeMulti ratios
      RuleDashed dash gap -> StrokeDashed (unSp dash) (unSp gap)
      RuleDotted gap -> StrokeDotted (unSp gap)
      RuleJapaneseDots gap -> StrokeJapaneseDots (unSp gap)
      RuleWavy -> StrokeWavy
    resolveBlock b@(Block sp lbl lang (Separator name)) =
      let definition = if name == "default" then Just (fromMaybe (SeparatorBlank 1) (Map.lookup name (stSeparators style))) else Map.lookup name (stSeparators style)
       in case definition of
            Nothing -> ([b], [Left (diagnostic "G04105" Error sp ("区切りスタイルがありません: " <> name))])
            Just (SeparatorBlank n) -> ([Block sp lbl lang (BlankLines (fromIntegral n))], [])
            Just (SeparatorText before after align content characterName) -> ([b], [Right ((sp, name), SeparatorTextAppearance before after align content characterName)])
            Just (SeparatorRule before after align rule) ->
              ([b], [Right ((sp, name), SeparatorRuleAppearance before after align (dimension <$> rsLength rule) (unSp (rsWeight rule)) (rsColor rule) (stroke (rsStyle rule)))])
            Just (SeparatorFunction path command) ->
              case [e | p <- maybe [] pure program, e <- Map.findWithDefault [] path (programExports p), exKind e == KindBlock, exName e == command, null (exArgs e)] of
                e : _ | Just p <- program ->
                  case bfCall (separatorFunction handlers p e) [] [] sp of
                    Right blocks' -> (blocks', [])
                    Left ds -> ([], map Left ds)
                _ -> ([], [Left (diagnostic "G03006" Error (separatorSettingSite styleFid styleText name "command") ("区切りの Emet 関数が見つからないか、引数があります: " <> command))])
    resolveBlock b = ([b], [])

separatorSettingSite :: FileId -> Text -> Text -> Text -> SrcSpan
separatorSettingSite fid src name key =
  let section = "[separators." <> name <> "]"
      (before, rest) = T.breakOn section src
      (through, found) = T.breakOn key rest
      prefix = if T.null found then before else before <> through
      off = BS.length (TE.encodeUtf8 prefix)
   in mkSpan fid off off

readMaybeText :: Files -> FilePath -> IO (Maybe Text)
readMaybeText files p = fmap TE.decodeUtf8Lenient <$> readMaybeBytes files p

{- | A file of the root by its name, when it is there; one that is a link
out of the root is read, as before (docs/adr/0199).
-}
readMaybeBytes :: Files -> FilePath -> IO (Maybe BS.ByteString)
readMaybeBytes files p = do
  e <- isPresent files p
  if e then Just <$> filesRead files p else pure Nothing

-- | Whether a file of the root by its name is there: anything but Missing.
isPresent :: Files -> FilePath -> IO Bool
isPresent files p = (/= Left Missing) <$> filesResolve files p

-- | golem fmt does not format style.toml, so its G01003 has no fix (golem-parser ADR 0009).
noFix :: Diagnostic -> Diagnostic
noFix d = d {diagFixes = []}

-- | A deferred expression; G02008 is at the inline @sp@ (golem-eval ADR 0003).
evalDeferred :: DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic Text
evalDeferred dv sp (DeferredExpr e) =
  let docNs = Map.fromList [("chapters", VHash (Map.fromList [("count", VNat (fromInteger (dvChapterCount dv)))]))]
      en = plainEnv Map.empty (Map.singleton "doc" docNs)
   in evalExpr en e >>= embedValue sp

-- | Evaluates files in import order so that imports see their exports.
evalAll :: Profile -> Project -> Style -> Map FilePath Asset -> Set.Set Text -> PluginHook -> FunctionTable -> Map FileId EvalResult
evalAll profile project style assets citeKeys hook table = foldl' step Map.empty (projectOrder project)
  where
    step acc fid = case Map.lookup fid (projectSources project) of
      Nothing -> acc
      Just sf -> Map.insert fid (reeval profile project style assets citeKeys hook table acc fid sf) acc

-- | S0 of one file, with the exports of its imports taken from @acc@.
reeval :: Profile -> Project -> Style -> Map FilePath Asset -> Set.Set Text -> PluginHook -> FunctionTable -> Map FileId EvalResult -> FileId -> SourceFile -> EvalResult
reeval profile project style assets citeKeys hook table acc fid sf =
  let meta = metadataValues (manifestMetadata (projectManifest project))
      importsOfFile f = let ImportGraph g = projectImports project in Map.findWithDefault [] f g
      -- each @import line gives the exports of the file the import graph says it points at,
      -- by the path as the line writes it, whatever its ./, .. or links (root ADR 0455)
      exports =
        ResolvedImports $
          Map.fromList
            [ (isPath site, erExports r)
            | (tfid, site) <- importsOfFile fid,
              Just r <- [Map.lookup tfid acc]
            ]
      ctx =
        EvalContext
          { ctxFile = fid,
            ctxPath = sfPath sf,
            ctxProfile = profile,
            ctxMeta = meta,
            ctxVars = projectVarValues (manifestVars (projectManifest project)),
            ctxImports = exports,
            ctxSwatches = Map.keysSet (stSwatches style),
            ctxCharStyles = Map.keysSet (stCharStyles style),
            ctxParaStyles = paraLineBreaks style,
            ctxDefaultKenten = compKenten (stComposition style),
            ctxCiteKeys = citeKeys,
            ctxAssets = assets,
            ctxPlugins = hook,
            ctxSource = sourceSettingsOf project fid,
            ctxStyle = style,
            ctxLocalStyles = noLocalStyles,
            ctxFunctions = table
          }
   in evalFile ctx (sfAst sf)

{- | S0 of a file outside any project, FileId 0, with the built-in styles
and no plugins (golem-cli ADR 0007): what the LSP shows of an open file
the manifest does not reach, and what golem inspect --as ir shows without
manifest.toml. The diagnostics are a BOM or CR of the text and the syntax;
the evaluation of a file with syntax errors is not reported (golem-parser
ADR 0009).
-}
evaluateLoose :: FilePath -> Text -> EvalResult
evaluateLoose path text =
  let fid = FileId 0
      (ast, _, synDiags) = parseAst fid text
      -- a file outside the project knows the built-in styles only (docs/adr ADR 0005)
      -- the imports of variable files are not resolved, as those of the .emet (root ADR 0455)
      ctx = EvalContext fid path Dev Map.empty Map.empty UnresolvedImports Set.empty (Map.keysSet (stCharStyles defaultStyle)) (paraLineBreaks defaultStyle) "sesame" Set.empty Map.empty noPlugins defaultSourceSettings defaultStyle noLocalStyles noFunctions
      res = evalFile ctx ast
      syntax = checkText fid text <> synDiags
   in res {erDiagnostics = if hasErrors syntax then syntax else syntax <> erDiagnostics res}

-- | How a file of the project is read (docs/adr ADR 0013).
sourceSettingsOf :: Project -> FileId -> SourceSettings
sourceSettingsOf project fid = Map.findWithDefault (manifestSource (projectManifest project)) fid (projectSourceSettings project)

-- | The paragraph styles that keep their lines (lint G05001, docs/adr ADR 0005).
keepStyles :: Style -> Set.Set Text
keepStyles = Map.keysSet . Map.filter (== KeepLines) . paraLineBreaks

-- | The built-in paragraph styles that keep their lines: verse.
builtinKeepStyles :: Set.Set Text
builtinKeepStyles = keepStyles defaultStyle

-- | @meta@: the text of the metadata a running head shows too, and the creators.
metadataValues :: Metadata -> Map Text Value
metadataValues md =
  Map.fromList
    ( [("creators", VArray [VString (crName c) | c <- mdCreators md])]
        <> [("publisher_person", VString p) | Just p <- [mdPublisherPerson md]]
        <> [("roles", VHash roles) | not (Map.null roles)]
        <> [("printing", printingValue p) | Just p <- [lastMaybe (mdPrintings md)]]
        <> [("printings", VArray (map printingValue (mdPrintings md))) | not (null (mdPrintings md))]
    )
    <> (VString <$> runningMetadata md)
  where
    -- the names by role, creators first, each in the order of the manifest (docs/adr ADR 0033)
    roles =
      Map.fromListWith
        (flip (<>))
        [(T.replace "-" "_" (roleWord (crRole c)), [c]) | c <- mdCreators md <> mdContributors md]
        & Map.map (\cs -> VArray [VString (crName c) | c <- cs])
    printingValue p =
      let (y, m, d) = toGregorian (prDate p)
       in VHash
            ( Map.fromList
                [ ("edition", VInt (toInteger (prEdition p))),
                  ("number", VInt (toInteger (prNumber p))),
                  ("year", VInt y),
                  ("month", VInt (toInteger m)),
                  ("day", VInt (toInteger d)),
                  ("date", VString (T.pack (showGregorian (prDate p))))
                ]
            )
    lastMaybe xs = if null xs then Nothing else Just (last xs)
    x & f = f x

{- | The variables the running heads show, as text, for each chapter file
by its master page (golem-driver ADR 0022): its own (@{set.<name>}@) and
those of its imports (@{set.<namespace>.<name>}@). G02067 for a variable
without @?@ that the file does not have, G02068 for a value that is not a
string or a number; at the top of the file, once for each file and name.
-}
runningVars :: Evaluated -> (Map FileId (Map [Text] Text), [Diagnostic])
runningVars e =
  let project = evProject e
      style = evStyle e
      masters = stMasters style
      masterOf name = (name >>= \n -> (n,) <$> Map.lookup n masters) <|> (("body",) <$> Map.lookup "body" masters) <|> Map.lookupMin masters
      perFile (fid, name) = case (masterOf name, Map.lookup fid (evResults e)) of
        (Just (mname, MasterDef {mdRunningHead = Just rh}), Just _) ->
          let refs = Map.fromListWith (&&) [(n, q) | c <- [rhOdd rh, rhEven rh], (RefVar n, q) <- runningRefs c]
              lookupVar = fileVariable project (evResults e) fid
              at = mkSpan fid 0 0
              related = [(mkSpan (evStyleFile e) 0 0, "マスターページ " <> mname <> " の柱の書式")]
              one (n, optional) = case lookupVar n of
                Nothing
                  | optional -> ([], [])
                  | otherwise -> ([], [(diagnostic "G02067" Error at ("柱が参照する変数 " <> T.intercalate "." n <> " が、このファイルにありません（マスターページ " <> mname <> "）")) {diagRelated = related}])
                -- strings and numbers as they are embedded in prose
                Just v -> case embedValue at v of
                  Right t -> ([(n, t)], [])
                  Left _ -> ([], [(diagnostic "G02068" Error at ("柱に出せるのは文字列と数です: " <> T.intercalate "." n <> " は " <> typeName v)) {diagRelated = related}])
              (vals, ds) = foldMap one (Map.toList refs)
           in (Map.singleton fid (Map.fromList vals), ds)
        _ -> (Map.empty, [])
   in foldMap perFile (nub [(fid, name) | (fid, name) <- projectChapters project])

{- | A variable of a file by its path in @{set.<name>}@ or
@{set.<namespace>.<name>}@ (golem-driver ADR 0022): its own or one an
@import lists, by its alias (root ADR 0451, root ADR 0458), or one of a
file it imports with the namespace.
-}
fileVariable :: Project -> Map FileId EvalResult -> FileId -> [Text] -> Maybe Value
fileVariable project results fid = \case
  [v] -> (Map.lookup fid results >>= Map.lookup v . erExports) <|> imported (\site -> [lnName l | l <- importNames site, lnAlias l == v])
  [ns, v] -> imported (\site -> [v | importNamespace site == Just ns])
  _ -> Nothing
  where
    ImportGraph graph = projectImports project
    imported origs = listToMaybe [x | (tfid, site) <- Map.findWithDefault [] fid graph, o <- origs site, Just tr <- [Map.lookup tfid results], Just x <- [Map.lookup o (erExports tr)]]

-- | How a file is referred to: by @figure, @table or @listing (golem-eval ADR 0004).
data AssetUse = UseImage | UseTable | UseListing
  deriving stock (Eq, Ord, Show)

-- | What 'loadAssets' read (golem-eval ADR 0004).
data LoadedAssets = LoadedAssets
  { laAssets :: !(Map FilePath Asset),
    -- | the files read as text, where their diagnostics point
    laSources :: !(Map FileId SourceInfo),
    -- | the reading stage of the table files: G01001 and G02082
    laDiagnostics :: ![Diagnostic],
    -- | the table files the last evaluation read, for the LSP to watch (golem-eval ADR 0004)
    laTableFiles :: !(Set.Set FilePath)
  }

-- | The paths the sources refer to as assets, with their uses.
assetUses :: Project -> Map FilePath (Set.Set AssetUse)
assetUses = assetUsesWith (const noOverrides)

-- | 'assetUses' of the commands that call the built-in ones alone, by the overrides of each file (root ADR 0471).
assetUsesWith :: (A.File -> Overrides) -> Project -> Map FilePath (Set.Set AssetUse)
assetUsesWith overridesOf project = Map.fromListWith Set.union [(p, Set.singleton u) | sf <- Map.elems (projectSources project), (p, u) <- assetRefsWith (overridesOf (sfAst sf)) (sfAst sf)]

-- | The paths of the assets read as text, which have a FileId each ('loadAssets').
assetTextPaths :: Project -> [FilePath]
assetTextPaths project = [p | (p, us) <- Map.toList (assetUses project), any (`Set.member` us) [UseTable, UseListing]]

{- | The .emet the project uses (docs/adr/0162), in the order they are met:
those of @import of the sources, in the order of the files, then those of
[[filters]]. A .emet of [[filters]] that is missing is G03002, one outside
the root G03003, at the top of manifest.toml; the project checks those of
@import as it checks the .gm.
-}
functionRoots :: Files -> Project -> Style -> IO ([Diagnostic], [FilePath])
functionRoots files project style = do
  let imported = [p | sf <- Map.elems (projectSources project), site <- sfImports sf, ".emet" `T.isSuffixOf` isPath site, Right p <- [normalizeRelative (T.unpack (isPath site))]]
      filtered = [(p, Nothing) | FilterDecl (FilterFunction p) _ _ _ _ <- manifestFilters (projectManifest project)] <> [(p, Just name) | (name, SeparatorFunction p _) <- Map.toList (stSeparators style)]
      at = mkSpan (projectManifestFile project) 0 0
  styleText <- maybe "" TE.decodeUtf8Lenient <$> readMaybeBytes files "style.toml"
  checked <- forM filtered $ \(p, separatorName) ->
    filesResolve files p >>= \case
      Left Missing ->
        pure
          ( Left
              ( case separatorName of
                  Just name -> diagnostic "G03006" Error (separatorSettingSite (styleFileId project) styleText name "function") ("区切りの function のファイルがありません: " <> T.pack p)
                  Nothing -> diagnostic "G03002" Error at ("[[filters]] の function のファイルがありません: " <> T.pack p)
              )
          )
      Left e ->
        pure
          ( Left
              ( case separatorName of
                  Just name -> diagnostic "G03006" Error (separatorSettingSite (styleFileId project) styleText name "function") (T.pack (pathErrorMessage e <> ": " <> p))
                  Nothing -> diagnostic "G03003" Error at (T.pack (pathErrorMessage e <> ": " <> p))
              )
          )
      Right rel -> pure (Right rel)
  pure (lefts checked, nub (imported <> rights checked))

{- | The .emet a project uses (docs/adr/0162), those of @import and
[[filters]] and those they import, as far as they can be read; for golem
fmt without arguments.
-}
functionPaths :: FilePath -> Project -> IO [FilePath]
functionPaths root project = do
  let files = diskFiles root
  style <- maybe defaultStyle (fromRight defaultStyle . parseStyle (styleFileId project) . TE.decodeUtf8Lenient) <$> readMaybeBytes files "style.toml"
  (_, roots) <- functionRoots files project style
  if null roots
    then pure []
    else do
      lf <- loadFunctions files Map.empty (functionsFileBase project) (projectManifest project) roots
      pure (sort [siPath si | si <- Map.elems (lfSources lf)])

{- | The table of the functions for golem-eval (docs/adr/0162): the
namespaces of the program, or, after an error of the .emet, none, whose
calls are G02279 (root ADR 0461).
-}
functionTableOf :: Handlers -> Project -> [FilePath] -> LoadedFunctions -> FunctionTable
functionTableOf hs project roots lf =
  let filterFiles = Set.fromList [rel | FilterDecl (FilterFunction _) _ fs _ _ <- manifestFilters (projectManifest project), f <- fs, Right rel <- [normalizeRelative f]]
   in case lfProgram lf of
        Just p -> FunctionTable (functionNamespaces hs p) False filterFiles
        Nothing
          | null roots -> noFunctions
          | otherwise -> FunctionTable Map.empty True filterFiles

{- | The filters of the .emet (docs/adr/0162), with the size of each .gm in
bytes for their limit of steps. None after an error of the .emet.
-}
functionFilterOf :: Handlers -> Project -> Maybe Program -> FunctionFilter
functionFilterOf hs project program emet name _path doc = do
  p <- program
  rel <- either (const Nothing) Just (normalizeRelative emet)
  f <- filterOf hs p rel name
  let bytes = maybe 0 (lengthWord8 . sfText) (Map.lookup (docFile doc) (projectSources project))
  pure ((,[]) <$> f bytes doc)

{- | G03001 at the top of manifest.toml for a filter of [[filters]] its .emet
does not have (docs/adr/0162).
-}
unknownFilters :: Project -> Maybe Program -> [Diagnostic]
unknownFilters project = \case
  Nothing -> []
  Just p ->
    [ diagnostic "G03001" Error (mkSpan (projectManifestFile project) 0 0) ("function の .emet にないフィルタです: " <> T.pack emet <> " の " <> name)
    | FilterDecl (FilterFunction emet) name _ _ _ <- manifestFilters (projectManifest project),
      Right rel <- [normalizeRelative emet],
      Nothing <- [filterOf (Handlers (const Nothing)) p rel name]
    ]

{- | The first FileId of the .emet (docs/adr/0162): after the files of data
of the plugins, as many as their declarations name at most.
-}
functionsFileBase :: Project -> FileId
functionsFileBase project =
  let FileId base = dataFileBase project
   in FileId (base + sum [Map.size (pdData d) | d <- Map.elems (manifestPlugins (projectManifest project))])

{- | The first FileId of the files of data that the checks of the data of
the plugins point at (docs/adr/0120): the one after the assets read as
text.
-}
dataFileBase :: Project -> FileId
dataFileBase project = let FileId lock = lockFileId project in FileId (lock + 1 + length (assetTextPaths project))

{- | Files referenced by @figure, @table and @listing: text content for
tables and listings, presence for images, and why a path cannot be used
(golem-eval ADR 0003). A path any reference reads as text is read as
text, from @overlay@ when the editor has it open. Each file read as text
has a FileId, from the one after plugins.lock's, in the order of the paths
(golem-eval ADR 0004). A table file passes the reading stage of table
files ('readTableSource'); a listing is read as before. A table file
over 'tableMaxBytes' is not read for the table (docs/adr ADR 0043).
A file a command reads whose name a file overrides is not read (root ADR
0471); the FileId of each text file is that of every reference, so that
the overrides change no other FileId.
-}
loadAssets :: Files -> Map FilePath Text -> FunctionTable -> PluginHook -> Project -> IO LoadedAssets
loadAssets files overlay table hook project = do
  let refs = assetUsesWith (fileOverrides table hook) project
      FileId lock = lockFileId project
      fids = Map.fromList (zip (assetTextPaths project) (map FileId [lock + 1 ..]))
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
      r <- filesResolve files path
      case (r, Map.lookup path fids) of
        (Left e, _) -> pure (AssetInvalid e, Nothing, [], Nothing)
        (Right rel, Just fid) -> do
          let open = Map.lookup rel overlay <|> Map.lookup path overlay
              readBytes = maybe (filesRead files rel) (pure . TE.encodeUtf8) open
          -- the size of a table file is known before it is read (G02088, docs/adr ADR 0043)
          size <- maybe (filesSize files rel) (pure . toInteger . lengthWord8) open
          if Set.member UseTable uses && size > toInteger tableMaxBytes
            then do
              -- a listing of the same file still reads it, as before
              listed <- if Set.member UseListing uses then Just . TE.decodeUtf8Lenient <$> readBytes else pure Nothing
              pure (AssetTableTooLarge size listed, Nothing, [], Just rel)
            else do
              bytes <- readBytes
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
assetRefs = assetRefsWith noOverrides

{- | 'assetRefs' of the commands that call the built-in @figure, @table
and @listing where they are written (root ADR 0471).
-}
assetRefsWith :: Overrides -> A.File -> [(FilePath, AssetUse)]
assetRefsWith overrides (A.File _ bs) = concatMap blk bs
  where
    blk (A.Located sp b) = case b of
      A.BlockCommand (A.Located _ name) args body -> [r | callsBuiltin overrides BlockSpace name (spanStart sp), r <- cmd name args] <> concatMap blk body
      A.Attributed cs t -> concatMap blk cs <> maybe [] blk t
      A.Fenced inner -> concatMap blk inner
      A.BulletList items -> concatMap (concatMap blk) items
      A.OrderedList items -> concatMap (concatMap blk) items
      A.DefList gs -> concatMap (concatMap (concatMap blk) . A.dgDefs) gs
      _ -> []
    cmd name args =
      let pos = [t | A.Located _ (A.Positional v) <- args, Just t <- [txt v]]
          kw k = [t | A.Located _ (A.Keyword (A.Located _ k') v) <- args, k' == k, Just t <- [txt v]]
       in case name of
            "figure" -> [(T.unpack p, UseImage) | p <- take 1 pos <> kw "web"]
            "table" ->
              [ (T.unpack p, UseTable)
              | not (any isSrc args),
                [A.Located _ (A.Positional v)] <- [filter isPositional args],
                Just p <- [txt v]
              ]
            "listing" ->
              [ (T.unpack p, UseListing)
              | not (any isSrc args),
                [A.Located _ (A.Positional v)] <- [filter isPositional args],
                Just p <- [txt v]
              ]
            _ -> []
    isSrc (A.Located _ (A.Keyword (A.Located _ "src") _)) = True
    isSrc _ = False
    isPositional (A.Located _ (A.Positional _)) = True
    isPositional _ = False
    txt = \case
      A.Word t -> Just t
      A.StringLit t -> Just t
      _ -> Nothing

{- | CSL-JSON: G03026 and G03003 for the files of the bibliography that
cannot be read, G03108 for those with a character that cannot be written to
the output (docs/adr/0159), the keys, and the entries formatted by golem-doc
(golem-doc ADR 0004, 0005). The diagnostics point at the head of manifest.toml,
FileId 0, as G03002 does, because the manifest keeps no positions.
-}
loadBibliography :: Files -> Manifest -> IO ([Diagnostic], Set.Set Text, Map Text [EntryPart])
loadBibliography files manifest = do
  results <- forM (manifestBibliography manifest) $ \p -> do
    res <- filesResolve files p
    case res of
      Left Missing -> pure (Left (unreadable ("参考文献のファイルがありません: " <> T.pack p)))
      Left e -> pure (Left (diagnostic "G03003" Error manifestHead (T.pack (pathErrorMessage e <> ": " <> p))))
      Right rel -> do
        r <- try (BL.fromStrict <$> filesRead files rel) :: IO (Either SomeException BL.ByteString)
        pure $ case decodeCslJson <$> r of
          Left _ -> Left (unreadable ("参考文献のファイルがありません: " <> T.pack p))
          Right (Left (CslNotJson err)) -> Left (unreadable ("参考文献のファイルを JSON として読めません: " <> T.pack p <> "（" <> T.pack err <> "）"))
          Right (Left CslNotArray) -> Left (unreadable ("参考文献のファイルは CSL-JSON の配列で書きます: " <> T.pack p))
          Right (Left (CslUnwritable c ptr more)) ->
            Left
              ( diagnostic "G03108" Error manifestHead $
                  "参考文献のファイルに出力に書けない文字（"
                    <> codePointText c
                    <> "）があります: "
                    <> T.pack p
                    <> "（"
                    <> ptr
                    <> "）"
                    <> (if more == 0 then "" else "、ほか " <> T.pack (show more) <> " 件")
              )
          Right (Right es) -> Right es
  let m = Map.fromList [(ceId c, formatEntry c) | c <- concat (rights results)]
  pure (lefts results, Map.keysSet m, m)
  where
    manifestHead = mkSpan (FileId 0) 0 0
    unreadable = diagnostic "G03026" Error manifestHead
