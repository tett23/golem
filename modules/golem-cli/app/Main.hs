-- | The golem command (golem-cli ADR 0001): a thin layer over the modules.
module Main (main) where

import Control.Monad (forM_, unless, when)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.UUID qualified as UUID
import Data.UUID.V4 qualified as UUID
import Golem.Doc.Cbor (encodeDocument)
import Golem.Driver
import Golem.Driver.Lint (lintProject)
import Golem.Driver.New
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
import System.Directory (doesFileExist)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))
import System.IO (stderr)
import Text.Printf (printf)

data Format = Human | Json

data Command
  = New FilePath Language Bool
  | Build [String] Profile Format
  | Check Profile Format
  | PluginFetch
  | PluginLock
  | Inspect FilePath String
  | Lint Profile Format
  | Fmt Bool [FilePath]
  | Lsp

main :: IO ()
main = do
  cmd <- customExecParser (prefs showHelpOnEmpty) (info (commands <**> helper) (fullDesc <> progDesc "Golem typesetting system"))
  code <- run cmd
  exitWith code

profileOpt :: Parser Profile
profileOpt =
  option
    (eitherReader (\case "dev" -> Right Dev; "prod" -> Right Prod; s -> Left ("unknown profile: " <> s)))
    (long "profile" <> value Dev <> metavar "dev|prod" <> help "Build profile")

languageOpt :: Parser Language
languageOpt =
  option
    (eitherReader (\case "ja" -> Right Japanese; "en" -> Right English; s -> Left ("unknown language: " <> s)))
    (long "language" <> value Japanese <> metavar "ja|en" <> help "Language of the template")

formatOpt :: Parser Format
formatOpt =
  option
    (eitherReader (\case "human" -> Right Human; "json" -> Right Json; s -> Left ("unknown format: " <> s)))
    (long "format" <> value Human <> metavar "human|json" <> help "Diagnostic format")

commands :: Parser Command
commands =
  hsubparser
    ( command "new" (info (New <$> strArgument (metavar "DIR") <*> languageOpt <*> switch (long "no-fonts" <> help "Do not download the fonts")) (progDesc "Create a project"))
        <> command "build" (info (Build <$> many (strOption (long "target" <> metavar "html|epub|text|pdf")) <*> profileOpt <*> formatOpt) (progDesc "Build the targets"))
        <> command "check" (info (Check <$> profileOpt <*> formatOpt) (progDesc "Check without writing output"))
        <> command "plugin" (info (hsubparser (command "fetch" (info (pure PluginFetch) mempty) <> command "lock" (info (pure PluginLock) mempty))) (progDesc "Manage plugins"))
        <> command "lint" (info (Lint <$> profileOpt <*> formatOpt) (progDesc "Apply the lint rules"))
        <> command "fmt" (info (Fmt <$> switch (long "check" <> help "Only list unformatted files") <*> many (strArgument (metavar "FILE"))) (progDesc "Format the sources"))
        <> command "lsp" (info (pure Lsp) (progDesc "Run the language server on standard input and output"))
        <> command "inspect" (info (Inspect <$> strArgument (metavar "FILE") <*> strOption (long "as" <> value "cst" <> metavar "cst|ast|ir")) (progDesc "Show the CST, AST or IR of a file"))
    )

run :: Command -> IO ExitCode
run = \case
  New dir lang noFonts -> newProject dir lang noFonts
  Build ts profile fmt -> do
    targets <- traverse parseTarget ts
    case sequence targets of
      Nothing -> TIO.hPutStrLn stderr "unknown target" >> pure (ExitFailure 2)
      Just tgs -> report fmt =<< build (defaultOptions ".") {optTargets = Just (if null tgs then allTargets else tgs), optProfile = profile}
  Check profile fmt -> report fmt =<< build (defaultOptions ".") {optProfile = profile, optCheckOnly = True}
  PluginFetch -> pluginFetch
  PluginLock -> pluginLock
  Inspect path mode -> inspect path mode
  Lint profile fmt -> do
    (infos, ds) <- lintProject profile "."
    report fmt (BuildResult ds infos [])
  Fmt check files -> formatFiles check files
  Lsp -> (\c -> if c == 0 then ExitSuccess else ExitFailure c) <$> runGolemLsp
  where
    parseTarget = \case
      "html" -> pure (Just TargetHtml)
      "epub" -> pure (Just TargetEpub)
      "text" -> pure (Just TargetText)
      "pdf" -> pure (Just TargetPdf)
      _ -> pure Nothing

report :: Format -> BuildResult -> IO ExitCode
report fmt r = do
  let ds = brDiagnostics r
  case fmt of
    Human -> TIO.hPutStr stderr (renderHuman (brSources r) ds)
    Json -> TIO.hPutStr stderr (renderJson (brSources r) ds)
  pure (if hasErrors ds then ExitFailure 1 else ExitSuccess)

inspect :: FilePath -> String -> IO ExitCode
inspect path mode = do
  bytes <- BS.readFile path
  case parseFile (FileId 0) bytes of
    Left ds -> TIO.hPutStr stderr (T.pack (show ds)) >> pure (ExitFailure 1)
    Right (cst, ds) -> do
      case mode of
        "cst" -> TIO.putStr (pretty cst)
        "ast" -> do
          let (ast, _, _) = parseAst (FileId 0) (TE.decodeUtf8Lenient bytes)
          print ast
        "ir" -> do
          ev <- evaluateProject Dev "."
          case ev of
            Left eds -> TIO.hPutStr stderr (T.pack (show eds))
            Right e -> forM_ (Map.elems (evResults e)) $ \res -> print (erDocument res) >> printf "CBOR: %d bytes\n" (BS.length (encodeDocument (erDocument res)))
        _ -> TIO.hPutStrLn stderr "--as は cst、ast、ir のいずれかです"
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
          Left ds -> TIO.hPutStr stderr (renderHuman Map.empty ds) >> pure Nothing
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
          TIO.hPutStr stderr (renderHuman (Map.singleton (FileId 0) (SourceInfo path (mkLineIndex src))) ds)
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
    Left ds -> TIO.hPutStr stderr (renderHuman Map.empty ds) >> pure (ExitFailure 1)
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
    Left ds -> TIO.hPutStr stderr (renderHuman Map.empty ds) >> pure (ExitFailure 1)
    Right lock -> do
      fetcher <- httpsFetcher
      cache <- defaultCacheDir
      r <- fetchPlugins fetcher cache lock
      case r of
        Left es -> mapM_ (TIO.hPutStrLn stderr) es >> pure (ExitFailure 1)
        Right () -> pure ExitSuccess
