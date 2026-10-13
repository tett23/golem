-- | The golem command (golem-cli ADR 0001): a thin layer over the modules.
module Main (main) where

import Control.Monad (forM_, unless, when)
import Data.ByteString qualified as BS
import Data.Char (isDigit)
import Data.List (intercalate, isPrefixOf, stripPrefix)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.UUID qualified as UUID
import Data.UUID.V4 qualified as UUID
import Golem.Doc.Cbor (encodeDocument)
import Golem.Driver
import Golem.Driver.Explain (Explanation (..), Status (..), catalog, explainHint)
import Golem.Driver.Lint (lintProject)
import Golem.Driver.New
import Golem.Driver.Version (golemVersion)
import Golem.Eval.File (erDocument)
import Golem.Fmt (FormatResult (..), format)
import Golem.Lsp.Server (runGolemLsp)
import Golem.Parser (parseAst, parseFile)
import Golem.Parser.CST (pretty)
import Golem.Plugin.Lock (defaultCacheDir, fetchPlugins, httpsFetcher, lockPlugins, parseLock, renderLock)
import Golem.Project (Project (..), SourceFile (..), loadProject)
import Golem.Project.Manifest (Manifest (..), PluginDecl (..), parseManifest)
import Golem.Syntax
import Options.Applicative
import Options.Applicative.Extra (helperWith)
import System.Directory (doesFileExist)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr, stdout)
import Text.Printf (printf)

data Format = Human | Json

data InspectAs = AsCst | AsAst | AsIr

data Command
  = New FilePath Language Bool
  | Build [Target] Profile CropMarks Format
  | Check Profile CropMarks Format
  | PluginFetch
  | PluginLock
  | Inspect FilePath InspectAs
  | Lint Profile Format
  | Fmt Bool [FilePath]
  | Lsp
  | Explain (Maybe T.Text)

main :: IO ()
main = do
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
versionOption = infoOption ("golem " <> T.unpack golemVersion) (long "version" <> hidden <> help "版を表示する")

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

inspectAsOpt :: Parser InspectAs
inspectAsOpt =
  option
    (choice "表示の種類" [("cst", AsCst), ("ast", AsAst), ("ir", AsIr)])
    (long "as" <> value AsCst <> metavar "cst|ast|ir" <> help "表示するもの（既定は cst）")

{- | A diagnostic code documented in docs/diagnostics.md, in any case
(golem-cli ADR 0005). Anything else is a usage error, as in ADR 0004.
-}
codeArg :: ReadM T.Text
codeArg = eitherReader $ \s ->
  let code = T.toUpper (T.pack s)
   in if T.length code /= 5 || T.take 1 code /= "G" || not (T.all isDigit (T.drop 1 code))
        then Left ("診断のコードは G と 4 桁の数字です: " <> s)
        else
          if Map.member code catalog
            then Right code
            else Left ("未知の診断のコードです: " <> s <> "。プラグインが出す診断は、プラグインの文書を参照してください")

commands :: Parser Command
commands =
  subparser
    ( commandGroup "コマンド:"
        <> metavar "COMMAND"
        <> cmd "new" (New <$> strArgument (metavar "DIR") <*> languageOpt <*> switch (long "no-fonts" <> help "フォントを取得しない")) "プロジェクトを作る"
        <> cmd "build" (Build <$> many targetOpt <*> profileOpt <*> marksOpt <*> formatOpt) "出力を build/ に書く"
        <> cmd "check" (Check <$> profileOpt <*> marksOpt <*> formatOpt) "出力を書かずに検査する"
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
        <> cmd "lint" (Lint <$> profileOpt <*> formatOpt) "lint の規則を適用する"
        <> cmd "fmt" (Fmt <$> switch (long "check" <> help "整形が必要なファイルを示すだけにする") <*> many (strArgument (metavar "FILE"))) "原稿を整形する"
        <> cmd "lsp" (pure Lsp) "標準入出力で LSP サーバーを動かす"
        <> cmd "inspect" (Inspect <$> strArgument (metavar "FILE") <*> inspectAsOpt) "ファイルの CST、AST、IR を表示する"
        <> cmd "explain" (Explain <$> optional (argument codeArg (metavar "CODE"))) "診断のコードの説明を表示する"
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
  New dir lang noFonts -> newProject dir lang noFonts
  Build tgs profile marks fmt -> report fmt =<< build (defaultOptions ".") {optTargets = Just (if null tgs then allTargets else tgs), optProfile = profile, optMarks = marks}
  Check profile marks fmt -> report fmt =<< build (defaultOptions ".") {optTargets = Just allTargets, optProfile = profile, optCheckOnly = True, optMarks = marks}
  PluginFetch -> pluginFetch
  PluginLock -> pluginLock
  Inspect path mode -> inspect path mode
  Lint profile fmt -> do
    (infos, ds) <- lintProject profile "."
    report fmt (BuildResult ds infos [])
  Fmt check files -> formatFiles check files
  Lsp -> (\c -> if c == 0 then ExitSuccess else ExitFailure c) <$> runGolemLsp
  Explain code -> explain code

{- | golem explain (golem-cli ADR 0005): the section of one code as it is
written, or every code with its title.
-}
explain :: Maybe T.Text -> IO ExitCode
explain = \case
  Just code -> do
    mapM_ (TIO.putStrLn . exBody) (Map.lookup code catalog)
    pure ExitSuccess
  Nothing -> do
    forM_ (Map.elems catalog) $ \e ->
      TIO.putStrLn (exCode e <> "  " <> exTitle e <> (if exStatus e == Retired then "（廃止）" else ""))
    pure ExitSuccess

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
    Human -> putHuman (brSources r) ds
    Json -> TIO.hPutStr stderr (renderJson (brSources r) ds)
  pure (if hasErrors ds then ExitFailure 1 else ExitSuccess)

inspect :: FilePath -> InspectAs -> IO ExitCode
inspect path mode = do
  bytes <- BS.readFile path
  case parseFile (FileId 0) bytes of
    Left ds -> TIO.hPutStr stderr (T.pack (show ds)) >> pure (ExitFailure 1)
    Right (cst, ds) -> do
      case mode of
        AsCst -> TIO.putStr (pretty cst)
        AsAst -> do
          let (ast, _, _) = parseAst (FileId 0) (TE.decodeUtf8Lenient bytes)
          print ast
        AsIr -> do
          ev <- evaluateProject Dev "."
          case ev of
            Left eds -> TIO.hPutStr stderr (T.pack (show eds))
            Right e -> forM_ (Map.elems (evResults e)) $ \res -> print (erDocument res) >> printf "CBOR: %d bytes\n" (BS.length (encodeDocument (erDocument res)))
      unless (null ds) $ TIO.hPutStr stderr (T.pack (show ds))
      pure ExitSuccess

-- | golem new (golem-cli ADR 0003).
newProject :: FilePath -> Language -> Bool -> IO ExitCode
newProject dir lang noFonts = do
  uuid <- UUID.nextRandom
  fetch <- httpsFetcher
  let fonts = templateFonts lang
  r <- createProject dir (templateFiles lang (UUID.toText uuid)) (if noFonts then Nothing else Just (fetch, fonts))
  case r of
    Left es -> mapM_ (TIO.hPutStrLn stderr) es >> pure (ExitFailure 1)
    Right () -> do
      when noFonts $ do
        TIO.hPutStrLn stderr "フォントを取得しませんでした。次のファイルを置いてください。"
        forM_ fonts $ \f -> TIO.hPutStrLn stderr ("  " <> T.pack (dir </> fsPath f) <> " (" <> fsUrl f <> ")")
      pure ExitSuccess

-- | golem fmt (golem-fmt ADR 0001).
formatFiles :: Bool -> [FilePath] -> IO ExitCode
formatFiles check files0 = do
  files <-
    if null files0
      then
        loadProject "." >>= \case
          Left ds -> putHuman Map.empty ds >> pure Nothing
          Right p -> pure (Just (map sfPath (Map.elems (projectSources p))))
      else pure (Just files0)
  case files of
    Nothing -> pure (ExitFailure 1)
    Just fs -> do
      results <- mapM one fs
      pure (if and results then ExitSuccess else ExitFailure 1)
  where
    one path = do
      bytes <- BS.readFile path
      case TE.decodeUtf8' bytes of
        Left _ -> TIO.hPutStrLn stderr (T.pack path <> ": UTF-8 として読めないため整形しません") >> pure False
        Right src -> formatOne path bytes src
    formatOne path bytes src =
      case format src of
        Unformattable ds -> do
          putHuman (Map.singleton (FileId 0) (SourceInfo path (mkLineIndex src))) ds
          pure False
        Formatted out
          | TE.encodeUtf8 out == bytes -> pure True
          | check -> putStrLn path >> pure False
          | otherwise -> BS.writeFile path (TE.encodeUtf8 out) >> pure True

-- | golem plugin lock (golem-plugin ADR 0002).
pluginLock :: IO ExitCode
pluginLock = do
  bytes <- BS.readFile "manifest.toml"
  case parseManifest (FileId 0) (TE.decodeUtf8Lenient bytes) of
    Left ds -> putHuman Map.empty ds >> pure (ExitFailure 1)
    Right m -> do
      fetcher <- httpsFetcher
      cache <- defaultCacheDir
      r <- lockPlugins fetcher cache (Map.map pdUrl (manifestPlugins m))
      case r of
        Left es -> mapM_ (TIO.hPutStrLn stderr) es >> pure (ExitFailure 1)
        Right lock -> TIO.writeFile "plugins.lock" (renderLock lock) >> pure ExitSuccess

-- | golem plugin fetch (golem-plugin ADR 0002).
pluginFetch :: IO ExitCode
pluginFetch = do
  exists <- doesFileExist "plugins.lock"
  text <- if exists then TE.decodeUtf8Lenient <$> BS.readFile "plugins.lock" else pure ""
  case parseLock (FileId 0) text of
    Left ds -> putHuman Map.empty ds >> pure (ExitFailure 1)
    Right lock -> do
      fetcher <- httpsFetcher
      cache <- defaultCacheDir
      r <- fetchPlugins fetcher cache lock
      case r of
        Left es -> mapM_ (TIO.hPutStrLn stderr) es >> pure (ExitFailure 1)
        Right () -> pure ExitSuccess
