-- | The golem command (golem-cli ADR 0001): a thin layer over the modules.
module Main (main) where

import Control.Monad (forM_, unless, when)
import Data.ByteString qualified as BS
import Data.Char (isDigit, isSpace, toLower)
import Data.Containers.ListUtils (nubOrd, nubOrdOn)
import Data.Either (partitionEithers, rights)
import Data.List (intercalate, isPrefixOf, isSuffixOf, sortOn, stripPrefix)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Ord (Down (..))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.UUID qualified as UUID
import Data.UUID.V4 qualified as UUID
import Golem.Cli.BuildCommand (BuildMode (..), jsonResult, runBuild)
import Golem.Doc.Cbor (encodeDocument)
import Golem.Driver
import Golem.Driver.Explain (Explanation (..), Status (..), catalog, explainHint)
import Golem.Driver.Functions (formatFunctionFile)
import Golem.Driver.Lint (lintProject)
import Golem.Driver.New
import Golem.Driver.Version (golemVersion)
import Golem.Eval.File (EvalResult (..))
import Golem.Fmt (FormatResult (..), format, formatTable, preprocess)
import Golem.Lsp.Server (runGolemLsp)
import Golem.Parser (parseAst, parseFile)
import Golem.Parser.CST (pretty)
import Golem.Parser.Read (readInfo)
import Golem.Plugin (pluginCodeForm)
import Golem.Plugin.Lock (defaultCacheDir, fetchPlugins, httpsFetcher, lockPlugins, parseLock, renderLock)
import Golem.Project (Project (..), ProjectFailure (..), SourceFile (..), loadProjectWith)
import Golem.Project.Files (diskFiles)
import Golem.Project.Manifest (Manifest (..), PluginDecl (..), PluginSource (..), parseManifest)
import Golem.Project.Paths (resolveInRoot)
import Golem.Syntax
import Golem.Syntax.Sha256 (sha256)
import Golem.Syntax.ShowTree (showTree)
import Options.Applicative
import Options.Applicative.Extra (helperWith)
import Repl qualified
import Stats (printStats)
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath (joinPath, makeRelative, normalise, splitDirectories, takeDirectory, takeExtension, (</>))
import System.IO (hFlush, hPutStrLn, hSetEncoding, stderr, stdout, utf8)
import Text.Printf (printf)

data Format = Human | Json

data InspectAs = AsCst | AsAst | AsIr | AsCbor

data Command
  = New FilePath Language Bool Bool
  | Build [Target] Profile CropMarks Bool Bool Format
  | Check Profile CropMarks Bool Bool Format
  | Stats Integer Integer
  | Preflight (Maybe FilePath) CropMarks Format
  | PluginFetch
  | PluginLock
  | Inspect FilePath InspectAs
  | Lint Profile Bool Bool Format
  | Fmt Bool [FilePath]
  | EmetRepl
  | Lsp
  | Explain [T.Text]

main :: IO ()
main = do
  -- stdout and stderr are UTF-8 whatever the locale (docs/adr/0002-determinism.md)
  mapM_ (`hSetEncoding` utf8) [stdout, stderr]
  args <- getArgs
  -- no backtracking: the options of golem (--version) are not options of
  -- its commands, so golem build --version is a usage error (docs/adr/0004)
  case execParserPure (prefs (showHelpOnEmpty <> noBacktrack)) cli args of
    Success cmd -> run cmd >>= exitWith
    Failure failure -> do
      let (msg, code) = renderFailure failure "golem"
      hPutStrLn (if code == ExitSuccess then stdout else stderr) (localize msg)
      exitWith code
    r@(CompletionInvoked _) -> handleParseResult r >>= run >>= exitWith

{- | Usage errors exit with 2 (golem-cli ADR 0001, ADR 0004); the messages
are in Japanese.
-}
cli :: ParserInfo Command
cli = info (commands <**> helpOption <**> versionOption) (fullDesc <> progDesc "Golem の組版システム" <> failureCode 2)

helpOption :: Parser (a -> a)
helpOption = helperWith (long "help" <> short 'h' <> help "このヘルプを表示する")

{- | golem --version prints @golem@ and the version (docs/adr/0004).
simpleVersioner is not used because its help is in English.
-}
versionOption :: Parser (a -> a)
versionOption = infoOption ("golem " <> T.unpack golemVersion) (long "version" <> hidden <> help "バージョンを表示する")

-- | Reads one of the given words.
choice :: String -> [(String, a)] -> ReadM a
choice what values =
  eitherReader $ \s -> maybe (Left ("未知の" <> what <> "です: " <> s <> "（" <> intercalate "、" (map fst values) <> " のいずれか）")) Right (lookup s values)

profileOpt :: Parser Profile
profileOpt =
  option
    (choice "プロファイル" [("dev", Dev), ("prod", Prod)])
    (long "profile" <> value Dev <> metavar "dev|prod" <> help "ビルドのプロファイル（既定は dev）")

languageOpt :: Parser Language
languageOpt =
  option
    (choice "言語" [("ja", Japanese), ("en", English)])
    (long "language" <> value Japanese <> metavar "ja|en" <> help "雛形の言語（既定は ja）")

formatOpt :: Parser Format
formatOpt =
  option
    (choice "出力形式" [("human", Human), ("json", Json)])
    (long "format" <> value Human <> metavar "human|json" <> help "診断の出力形式（既定は human）")

-- | --no-notices: no notice for this run (golem-syntax ADR 0002).
noNoticesOpt :: Parser Bool
noNoticesOpt = switch (long "no-notices" <> help "お知らせを表示しない")

{- | --verbose (-v): the infos too (docs/adr 0104). -v is not --version,
which has no short form.
-}
verboseOpt :: Parser Bool
verboseOpt = switch (long "verbose" <> short 'v' <> help "情報（info）の diagnostic も表示する")

targetOpt :: Parser Target
targetOpt =
  option
    (choice "ターゲット" [("html", TargetHtml), ("epub", TargetEpub), ("text", TargetText), ("pdf", TargetPdf)])
    (long "target" <> metavar "html|epub|text|pdf" <> help "作るターゲット（省くとすべて）")

-- | The crop marks of the PDF (golem-pdf ADR 0004).
marksOpt :: Parser CropMarks
marksOpt =
  option
    (choice "トンボの形" [("japanese", JapaneseMarks), ("western", WesternMarks), ("none", NoMarks)])
    (long "marks" <> value NoMarks <> metavar "japanese|western|none" <> help "PDF に付けるトンボ（既定は none）")

statsDimension :: String -> String -> Parser Integer
statsDimension optionName description =
  option (eitherReader positive) (long optionName <> metavar "N" <> value 20 <> showDefault <> help description)
  where
    positive raw | not (null raw) && all isDigit raw, n > 0 = Right n
      where
        n = read raw
    positive _ = Left "正の整数を指定してください"

inspectAsOpt :: Parser InspectAs
inspectAsOpt =
  option
    (choice "表示の種類" [("cst", AsCst), ("ast", AsAst), ("ir", AsIr), ("cbor", AsCbor)])
    (long "as" <> value AsCst <> metavar "cst|ast|ir|cbor" <> help "表示するもの（既定は cst）")

{- | A diagnostic code documented in docs/diagnostics.md, in any case, put
into upper case (golem-cli ADR 0005); anything else is the message of the
error. golem explain checks every code it is given, after the parsing of the
arguments, so that it reports every bad one (golem-cli ADR 0009).
-}
checkCode :: T.Text -> Either T.Text T.Text
checkCode s
  | not (isCodeShape code) =
      Left ("診断のコードは " <> codeShapeWording <> "を続けたものです: " <> s)
  | Map.member code catalog = Right code
  | otherwise = Left ("未知の診断のコードです: " <> s <> "。プラグインが出す診断は、プラグインの文書を参照してください")
  where
    code = T.toUpper s

{- | An argument of golem explain with a /, a code of a plugin's diagnostic
(docs/adr/0108): @Just (Right line)@, one line that golem has no section
for it, when the part after the / is of the form of docs/adr/0139
('pluginCodeForm'), and @Just (Left message)@ otherwise (docs/adr/0151).
The message names the first place that is wrong, in the order the number of
/, the part before it, the part after it (docs/adr/0164).
An argument without a / is a code of Golem: 'Nothing'.
-}
pluginCode :: T.Text -> Maybe (Either T.Text T.Text)
pluginCode s
  | not (T.any (== '/') s) = Nothing
  | [name, c] <- T.splitOn "/" s = Just (check name c)
  | otherwise = Just (Left (bad "/ は一つだけです"))
  where
    check name c
      | T.null name || T.any isSpace name = Left (bad "/ の前はプラグインの宣言の名前で、空でなく、空白を含みません")
      | not (pluginCodeForm c) = Left (bad "/ の後は英小文字で始まり、英小文字、数字、- だけからなります")
      | otherwise = Right (s <> ": プラグインの診断のコードです。説明は golem にはないので、プラグインの文書を参照してください")
    bad why = "プラグインの診断のコードの形が不正です: " <> s <> "。" <> why

{- | The key by which golem explain drops a repeated argument: a code of
Golem in upper case, as it is in any case (golem-cli ADR 0009), and a code
of a plugin as it is spelled, as its check tells the cases apart
(docs/adr/0164). Two arguments of one key are checked alike.
-}
dedupKey :: T.Text -> T.Text
dedupKey s
  | T.any (== '/') s = s
  | otherwise = T.toUpper s

commands :: Parser Command
commands =
  subparser
    ( commandGroup "コマンド:"
        <> metavar "COMMAND"
        <> cmd "new" (New <$> strArgument (metavar "DIR") <*> languageOpt <*> switch (long "no-fonts" <> help "フォントを取得しない") <*> switch (long "screen" <> help "画面向けのプリフライト設定を作る")) "プロジェクトを作る"
        <> cmd "build" (Build <$> many targetOpt <*> profileOpt <*> marksOpt <*> noNoticesOpt <*> verboseOpt <*> formatOpt) "出力を build/ に書く"
        <> cmd "check" (Check <$> profileOpt <*> marksOpt <*> noNoticesOpt <*> verboseOpt <*> formatOpt) "出力を書かずに検査する"
        <> cmd "preflight" (Preflight <$> optional (strOption (long "rules" <> metavar "FILE" <> help "プリフライトの設定のファイル（既定は preflight.toml）")) <*> marksOpt <*> formatOpt) "入稿の前に PDF を検査する"
        <> cmd
          "plugin"
          ( subparser
              ( commandGroup "コマンド:"
                  <> metavar "COMMAND"
                  <> cmd "fetch" (pure PluginFetch) "plugins.lock のとおりにプラグインを取得する"
                  <> cmd "lock" (pure PluginLock) "プラグインを取得し、ハッシュを plugins.lock に書く"
              )
          )
          "プラグインを管理する"
        <> cmd "lint" (Lint <$> profileOpt <*> noNoticesOpt <*> verboseOpt <*> formatOpt) "lint の規則を適用する"
        <> cmd "fmt" (Fmt <$> switch (long "check" <> help "整形が必要なファイルを示すだけにする") <*> many (strArgument (metavar "FILE"))) "原稿を整形する"
        <> cmd "repl" (subparser (commandGroup "コマンド:" <> metavar "LANGUAGE" <> cmd "emet" (pure EmetRepl) "Emet の式を対話的に評価する")) "対話的に式を評価する"
        <> cmd "lsp" (pure Lsp) "標準入出力で LSP サーバーを動かす"
        <> cmd "stats" (Stats <$> statsDimension "chars-per-line" "換算する1行の文字数" <*> statsDimension "lines-per-page" "換算する1ページの行数") "本文の文字数、ワード数、組版行数と換算ページ数を表示する"
        <> cmd "inspect" (Inspect <$> strArgument (metavar "FILE") <*> inspectAsOpt) "ファイルの CST、AST、IR を表示する"
        <> cmd "explain" (Explain <$> many (strArgument (metavar "CODE..."))) "診断のコードの説明を表示する"
    )
  where
    cmd name p desc = command name (info (p <**> helpOption) (progDesc desc))

{- | Puts into Japanese the phrases that optparse-applicative 0.19.0.0
writes itself (golem-cli ADR 0004). The golden tests of golem-cli catch a
phrase that a new version changes.
-}
localize :: String -> String
localize = intercalate "\n" . go . lines
  where
    go = \case
      [] -> []
      l : ls
        | Just rest <- stripPrefix "Usage: " l ->
            -- 使い方 is one column wider than Usage, so continued lines move by one
            let (cont, after) = span (" " `isPrefixOf`) ls
             in ("使い方: " <> rest) : map (' ' :) cont <> go after
        | otherwise -> line l : go ls
    line l
      | l == "Available options:" = "オプション:"
      | l `elem` ["Did you mean this?", "Did you mean one of these?"] = "次のことですか？"
      | Just x <- between "Invalid option `" "'" l = "未知のオプションです: " <> x
      | Just x <- between "Invalid argument `" "'" l = "未知の引数です: " <> x
      | Just x <- between "The option `" "` expects an argument." l = "オプション " <> x <> " には値が必要です"
      | Just x <- stripPrefix "Missing: " l = "足りない引数があります: " <> x
      | Just x <- stripPrefix "option " l = "オプション " <> x
      | otherwise = l
    between pre post l = stripPrefix pre l >>= \r -> reverse <$> stripPrefix (reverse post) (reverse r)

run :: Command -> IO ExitCode
run = \case
  EmetRepl -> Repl.run
  New dir lang noFonts screen -> newProject dir lang noFonts screen
  Build tgs profile marks quiet verbose fmt -> report fmt =<< runBuild "." (WriteTargets tgs) profile marks quiet verbose
  Check profile marks quiet verbose fmt -> report fmt =<< runBuild "." CheckOnly profile marks quiet verbose
  Preflight rules marks fmt -> preflightRun rules marks fmt
  PluginFetch -> pluginFetch
  PluginLock -> pluginLock
  Stats charsPerLine rows -> do
    root <- getCurrentDirectory
    result <- manuscriptLines (defaultOptions root)
    case result of
      Left (sources, ds) -> putHuman sources ds >> pure (ExitFailure 1)
      Right body -> printStats charsPerLine rows body >> pure ExitSuccess
  Inspect path mode -> inspect path mode
  Lint profile quiet verbose fmt -> do
    (infos, ds) <- lintProject profile quiet verbose "."
    report fmt (BuildResult ds infos [])
  Fmt check files -> formatFiles check files
  Lsp -> (\c -> if c == 0 then ExitSuccess else ExitFailure c) <$> runGolemLsp
  Explain code -> explain code

{- | golem explain (golem-cli ADR 0005, 0009): the sections of the codes in
the order given, each once (by 'dedupKey', docs/adr/0164), a blank
line between them, and then one line on stderr for each bad code, which
makes the exit code 2; or every code with its title.
-}
explain :: [T.Text] -> IO ExitCode
explain = \case
  [] -> do
    forM_ (Map.elems catalog) $ \e ->
      TIO.putStrLn (exCode e <> "  " <> exTitle e <> (if exStatus e == Retired then "（廃止）" else ""))
    pure ExitSuccess
  args -> do
    -- a code of a plugin is not one of Golem: the line of pluginCode (docs/adr/0108, 0151)
    let (bad, good) = partitionEithers [maybe (Right <$> checkCode a) (fmap Left) (pluginCode a) | a <- nubOrdOn dedupKey args]
        bodies = [either id (maybe "" exBody . (`Map.lookup` catalog)) c | c <- good]
    unless (null bodies) (TIO.putStrLn (T.intercalate "\n\n" bodies))
    hFlush stdout
    mapM_ (TIO.hPutStrLn stderr) bad
    pure (if null bad then ExitSuccess else ExitFailure 2)

{- | The diagnostics in the human format, followed by one line on golem
explain when a code of them is documented (golem-cli ADR 0005).
-}
putHuman :: Map.Map FileId SourceInfo -> [Diagnostic] -> IO ()
putHuman sources ds = do
  TIO.hPutStr stderr (renderHuman sources ds)
  let hint = explainHint ds
  unless (T.null hint) (TIO.hPutStrLn stderr hint)

report :: Format -> BuildResult -> IO ExitCode
report fmt r = do
  let ds = brDiagnostics r
  case fmt of
    Human -> putHuman (brSources r) ds >> pure (if hasErrors ds then ExitFailure 1 else ExitSuccess)
    Json -> let (code, text) = jsonResult r in TIO.hPutStr stderr text >> pure code

{- | golem preflight (golem-cli ADR 0006): the diagnostics, and in the human
format a summary as the last line when the PDF was made.
-}
preflightRun :: Maybe FilePath -> CropMarks -> Format -> IO ExitCode
preflightRun rules marks fmt = do
  r <- preflight (defaultPreflightOptions ".") {poRules = rules, poMarks = marks}
  let ds = prDiagnostics r
      count sev = length (filter ((== sev) . diagSeverity) ds)
      skips = prSkipped r
      summaryFacts =
        [("error-count", FactInt (toInteger (count Error)))]
          <> [("skipped-checks", FactTexts (map fst skips)), ("skipped-reasons", FactTexts (map snd skips))]
  case fmt of
    Json -> do
      let withSummary = case (prPdf r, ds) of
            (Nothing, firstDiag : rest) -> firstDiag {diagFacts = diagFacts firstDiag <> summaryFacts} : rest
            _ -> ds
      TIO.hPutStr stderr (renderJson (prSources r) withSummary)
    Human -> do
      putHuman (prSources r) ds
      when (isNothing (prPdf r)) $ do
        TIO.hPutStrLn stderr ("プリフライト: エラー " <> T.pack (show (count Error)))
        forM_ skips $ \(name, reason) -> TIO.hPutStrLn stderr ("未検査: " <> name <> "（" <> reason <> "）")
      forM_ (prPdf r) $ \pdf ->
        TIO.hPutStrLn stderr $
          "プリフライト（設定: "
            <> prRulesLabel r
            <> "、基にした設定: "
            <> prBasedOn r
            <> "）: エラー "
            <> T.pack (show (count Error))
            <> "、警告 "
            <> T.pack (show (count Warning))
            <> "。PDF/X-4 の適合の判定ではないので、入稿の前に商用のプリフライトでも確かめます。検査した PDF の SHA-256: "
            <> T.pack (concatMap (printf "%02x") (BS.unpack (sha256 pdf)))
  pure (if hasErrors ds then ExitFailure 1 else ExitSuccess)

{- | golem inspect (golem-cli ADR 0001, ADR 0007): the CST, the AST or
the semantic IR of one file on stdout, and the diagnostics in the human
format on stderr; 1 when there is an error among them.
-}
inspect :: FilePath -> InspectAs -> IO ExitCode
inspect path mode =
  readArgument path >>= \case
    Nothing -> missingArgument path
    Just bytes -> case mode of
      AsCst -> syntaxTree bytes
      AsAst -> syntaxTree bytes
      AsIr -> semantic bytes
      AsCbor -> semantic bytes
  where
    fileInfo bytes = Map.singleton (FileId 0) (readInfo path bytes)
    syntaxTree bytes = case parseFile (FileId 0) bytes of
      Left ds -> putHuman (fileInfo bytes) ds >> pure (ExitFailure 1)
      Right (cst, ds) -> do
        case mode of
          AsCst -> TIO.putStr (pretty cst)
          _ -> let (ast, _, _) = parseAst (FileId 0) (TE.decodeUtf8Lenient bytes) in TIO.putStrLn (showTree (FileId 0) (show ast))
        finishWith (fileInfo bytes) ds
    semantic bytes = do
      hasManifest <- doesFileExist "manifest.toml"
      if hasManifest then inProject bytes else outsideProject bytes
    -- the file alone, with the built-in styles (no manifest.toml)
    outsideProject bytes = case parseFile (FileId 0) bytes of
      Left ds -> putHuman (fileInfo bytes) ds >> pure (ExitFailure 1)
      Right (_, ds)
        | hasErrors ds -> finishWith (fileInfo bytes) ds
        | otherwise -> do
            let res = evaluateLoose path (TE.decodeUtf8Lenient bytes)
            showDocument (FileId 0) (erDocument res)
            finishWith (fileInfo bytes) (erDiagnostics res)
    inProject bytes =
      evaluateProject Dev "." >>= \case
        Left f -> putHuman (pfSources f) (pfDiagnostics f) >> pure (ExitFailure 1)
        Right e -> do
          rel <- relativePath path
          let project = evProject e
              sources = Map.insert (evStyleFile e) (SourceInfo "style.toml" (mkLineIndex (evStyleText e))) (withEvaluatedSources e (sourceInfos project))
              manifest = projectManifest project
              -- the same finishing as golem build, check and lint, without --verbose (docs/adr 0104)
              finish = finishDiagnostics Dev (Just (manifestSilencedNotices manifest)) (manifestSilencedInfo manifest) False
          case [(fid, sf) | (fid, sf) <- Map.toList (projectSources project), sfPath sf == rel] of
            -- a file of the project: its document of the evaluation, and every diagnostic of it
            (fid, _) : _ -> do
              mapM_ (showDocument fid . erDocument) (Map.lookup fid (evResults e))
              finishWith sources (finish (evDiagnostics e))
            -- another file: S0 in the context of the project, with a FileId of its own
            [] -> do
              let FileId top = maximum (nextFile (evStyleFile e) : Map.keys sources)
                  fid = FileId (top + 1)
                  projectStage = [d | d <- evDiagnostics e, spanFile (diagSpan d) `elem` [projectManifestFile project, evStyleFile e, nextFile (evStyleFile e)]]
                  sources' = Map.insert fid (readInfo path bytes) sources
              case parseFile fid bytes of
                Left ds -> finishWith sources' (finish (projectStage <> ds))
                Right (cst, synDiags)
                  | hasErrors synDiags -> finishWith sources' (finish (projectStage <> synDiags))
                  | otherwise -> do
                      let text = TE.decodeUtf8Lenient bytes
                          (ast, _, _) = parseAst fid text
                          res = evReevaluate e fid (SourceFile rel text cst ast [] synDiags)
                      showDocument fid (erDocument res)
                      finishWith sources' (finish (projectStage <> synDiags <> erDiagnostics res))
    nextFile (FileId n) = FileId (n + 1)
    showDocument fid doc = case mode of
      AsCbor -> BS.putStr (encodeDocument doc)
      _ -> TIO.putStrLn (showTree fid (show doc))
    -- golem inspect has no --verbose: it never shows an info (docs/adr 0104)
    finishWith sources ds = do
      putHuman sources (dropInfo ds)
      pure (if hasErrors ds then ExitFailure 1 else ExitSuccess)

{- | The bytes of a file named on the command line; Nothing when it is not
there or is not a regular file (golem-cli ADR 0007).
-}
readArgument :: FilePath -> IO (Maybe BS.ByteString)
readArgument path = do
  exists <- doesFileExist path
  if exists then Just <$> BS.readFile path else pure Nothing

-- | G03002 for a file named on the command line that is not there (golem-cli ADR 0007).
missingArgument :: FilePath -> IO ExitCode
missingArgument path = do
  putHuman (Map.singleton (FileId 0) (SourceInfo path (mkLineIndex ""))) [diagnostic "G03002" Error (mkSpan (FileId 0) 0 0) ("ファイルがありません: " <> T.pack path)]
  pure (ExitFailure 1)

-- | A path relative to the working directory, without @.@ and with @..@ resolved.
relativePath :: FilePath -> IO FilePath
relativePath p = do
  cwd <- getCurrentDirectory
  let resolve acc = \case
        "." -> acc
        ".." -> drop 1 acc
        s -> s : acc
      parts = reverse (foldl resolve [] (splitDirectories (cwd </> p)))
  pure (makeRelative cwd (joinPath parts))

-- | golem new (golem-cli ADR 0003).
newProject :: FilePath -> Language -> Bool -> Bool -> IO ExitCode
newProject dir lang noFonts screen = do
  uuid <- UUID.nextRandom
  fetch <- httpsFetcher
  let fonts = templateFonts lang
  r <- createProject dir (templateFilesFor screen lang (UUID.toText uuid)) (if noFonts then Nothing else Just (fetch, fonts))
  case r of
    Left (FetchFailed es) -> mapM_ (TIO.hPutStrLn stderr) es >> pure (ExitFailure 1)
    Left (Conflicts cs) -> putNewDiagnostics (map conflictDiagnostic cs) >> pure (ExitFailure 1)
    Right plan -> do
      -- after the project is written (docs/adr/0273)
      when (planKeepsGitignore plan) $
        putNewDiagnostics [(shown ".gitignore", "G03134", Notice, ".gitignore がすでにあるので書きませんでした。build/ を除外してください: ")]
      when noFonts $ do
        TIO.hPutStrLn stderr "フォントを取得しませんでした。次のファイルを置いてください。"
        forM_ fonts $ \f -> TIO.hPutStrLn stderr ("  " <> T.pack (dir </> fsPath f) <> " (" <> fsUrl f <> ")")
      pure ExitSuccess
  where
    -- the argument and the path of the template, as written on the command line
    shown p = normalise (dir </> p)
    conflictDiagnostic = \case
      NotADirectory -> (normalise dir, "G03133", Error, "ディレクトリではありません: ")
      ProjectExists p -> (shown p, "G03131", Error, "プロジェクトのファイルがすでにあります: ")
      PathTaken p -> (shown p, "G03132", Error, "雛形のファイルを書くパスに、すでにエントリがあります: ")

{- | The diagnostics of golem new (docs/adr/0273), each at the start of its
path, followed by the path in the message.
-}
putNewDiagnostics :: [(FilePath, T.Text, Severity, T.Text)] -> IO ()
putNewDiagnostics ds =
  putHuman
    (Map.fromList [(FileId i, SourceInfo p (mkLineIndex "")) | (i, (p, _, _, _)) <- numbered])
    [diagnostic code sev (mkSpan (FileId i) 0 0) (msg <> T.pack p) | (i, (p, code, sev, msg)) <- numbered]
  where
    numbered = zip [0 ..] ds

-- | How golem fmt formats a file: as a source, or as a table file (docs/adr/0186).
data FmtKind = FmtSource | FmtTable

-- | golem fmt (golem-fmt ADR 0001).
formatFiles :: Bool -> [FilePath] -> IO ExitCode
formatFiles check files0 = do
  files <-
    if null files0
      then
        projectSourcePaths >>= \case
          Left f -> putHuman (pfSources f) (pfDiagnostics f) >> pure Nothing
          Right (project, ps) -> do
            -- and the .emet the project uses (docs/adr/0162)
            emets <- loadProjectWith (diskFiles ".") Map.empty "." >>= either (const (pure [])) (functionPaths ".")
            -- and the table files the sources read by @table (docs/adr/0186)
            tables <- tablePaths project
            let others = ps <> emets
            pure (Just (map (,FmtSource) others <> [(t, FmtTable) | t <- tables, t `notElem` others]))
      else pure (Just [(f, kindOf f) | f <- files0])
  case files of
    Nothing -> pure (ExitFailure 1)
    Just fs -> do
      unless check $ cleanFinderInfo "." ("." : map (takeDirectory . fst) fs)
      results <- mapM (uncurry one) fs
      pure (if and results then ExitSuccess else ExitFailure 1)
  where
    -- a file given is a table file by its extension (docs/adr/0186)
    kindOf path
      | map toLower (takeExtension path) `elem` [".csv", ".tsv"] = FmtTable
      | otherwise = FmtSource
    -- a file that is not there is G03002, and the others are formatted (golem-cli ADR 0007)
    one path kind =
      readArgument path >>= \case
        Nothing -> missingArgument path >> pure False
        Just bytes -> case TE.decodeUtf8' bytes of
          Left _ -> TIO.hPutStrLn stderr (T.pack path <> ": UTF-8 として読めないため整形しません") >> pure False
          Right src -> case kind of
            FmtTable -> written path bytes (formatTable src)
            FmtSource -> formatOne path bytes src
    formatOne path bytes src
      -- a .emet, through golem-driver (docs/adr/0162)
      | ".emet" `isSuffixOf` path = case formatFunctionFile src of
          Left ds -> do
            putHuman (Map.singleton (FileId 0) (SourceInfo path (mkLineIndex src))) ds
            pure False
          Right out -> written path bytes out
      | otherwise = case format src of
          Unformattable ds -> do
            putHuman (Map.singleton (FileId 0) (SourceInfo path (mkLineIndex src))) ds
            pure False
          Formatted out -> written path bytes out
    written path bytes out
      | TE.encodeUtf8 out == bytes = pure True
      | check = putStrLn path >> pure False
      | otherwise = BS.writeFile path (TE.encodeUtf8 out) >> pure True

{- | The table files the sources read by @table, as the build collects them
('assetRefs'), without reading them (docs/adr/0186): those whose path is
written as an expression are not known, and a missing one and one outside
the root are left to the build, which reports them.
-}
tablePaths :: Project -> IO [FilePath]
tablePaths project = do
  let paths = nubOrd [p | sf <- Map.elems (projectSources project), (p, UseTable) <- assetRefs (sfAst sf)]
  resolved <- mapM (resolveInRoot ".") paths
  pure (nubOrd (rights resolved))

{- | The sources of the project for golem fmt without arguments. Recoverable
CR and missing quotes are fixed only in the loading overlay. The original
source is still passed to the formatter and is never written after an error.
-}
projectSourcePaths :: IO (Either ProjectFailure (Project, [FilePath]))
projectSourcePaths = go Map.empty
  where
    go overlay =
      loadProjectWith (diskFiles ".") overlay "." >>= \case
        Right p -> pure (Right (p, map sfPath (Map.elems (projectSources p))))
        Left f -> case recoverSources f of
          Just grouped -> do
            fixed <-
              traverse
                ( \(path, ds) -> do
                    original <- maybe (TE.decodeUtf8Lenient <$> BS.readFile path) pure (Map.lookup path overlay)
                    let next = if any ((== DiagnosticCode "G01003") . diagCode) ds then preprocess original else quoteOverlay original ds
                    pure (path, next)
                )
                grouped
            let overlay' = Map.union (Map.fromList fixed) overlay
            if overlay' /= overlay then go overlay' else pure (Left f)
          _ -> pure (Left f)
    -- Only these syntax errors permit discovering the remaining source paths.
    recoverSources f =
      let errs = filter ((== Error) . diagSeverity) (pfDiagnostics f)
          pathOf d = siPath <$> Map.lookup (spanFile (diagSpan d)) (pfSources f)
       in if not (null errs) && all ((`elem` [DiagnosticCode "G01003", DiagnosticCode "G01102"]) . diagCode) errs
            then traverse (\d -> (,d) <$> pathOf d) errs >>= \pairs -> if any ((== "manifest.toml") . fst) pairs then Nothing else Just (Map.toList (Map.fromListWith (<>) [(p, [d]) | (p, d) <- pairs]))
            else Nothing
    quoteOverlay original ds =
      let edits = sortOn (Down . spanStart . fst) (concatMap (concatMap fixEdits . diagFixes) ds)
          replace bytes (sp, replacement) = BS.take (spanStart sp) bytes <> TE.encodeUtf8 replacement <> BS.drop (spanEnd sp) bytes
       in TE.decodeUtf8Lenient (foldl' replace (TE.encodeUtf8 original) edits)

-- | golem plugin lock (golem-plugin ADR 0002).
pluginLock :: IO ExitCode
pluginLock = do
  bytes <- BS.readFile "manifest.toml"
  case parseManifest (FileId 0) (TE.decodeUtf8Lenient bytes) of
    Left ds -> putHuman Map.empty ds >> pure (ExitFailure 1)
    Right m -> do
      fetcher <- httpsFetcher
      cache <- defaultCacheDir
      -- a plugin of the project's path is not fetched nor locked (docs/adr/0109)
      r <- lockPlugins fetcher cache (Map.mapMaybe (\d -> case pdSource d of PluginUrl u -> Just u; PluginPath _ -> Nothing) (manifestPlugins m))
      case r of
        Left es -> mapM_ (TIO.hPutStrLn stderr) es >> pure (ExitFailure 1)
        Right lock -> BS.writeFile "plugins.lock" (TE.encodeUtf8 (renderLock lock)) >> pure ExitSuccess

-- | golem plugin fetch (golem-plugin ADR 0002).
pluginFetch :: IO ExitCode
pluginFetch = do
  exists <- doesFileExist "plugins.lock"
  text <- if exists then TE.decodeUtf8Lenient <$> BS.readFile "plugins.lock" else pure ""
  -- G06011 points into plugins.lock (golem-plugin ADR 0003)
  case parseLock (FileId 0) text of
    Left ds -> putHuman (Map.singleton (FileId 0) (SourceInfo "plugins.lock" (mkLineIndex text))) ds >> pure (ExitFailure 1)
    Right lock -> do
      fetcher <- httpsFetcher
      cache <- defaultCacheDir
      r <- fetchPlugins fetcher cache lock
      case r of
        Left es -> mapM_ (TIO.hPutStrLn stderr) es >> pure (ExitFailure 1)
        Right () -> pure ExitSuccess
