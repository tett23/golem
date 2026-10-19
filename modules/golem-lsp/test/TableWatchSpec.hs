{-# LANGUAGE GADTs #-}

-- | Diagnostics on table files, and watching them (golem-eval ADR 0004).
module TableWatchSpec (tableWatchTests) where

import Control.Concurrent (forkIO)
import Control.Monad (forM_, void)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString qualified as BS
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Lsp.Server (runGolemLspWithHandles)
import Golem.Lsp.Workspace
import Golem.Syntax
import Language.LSP.Protocol.Message qualified as M
import Language.LSP.Protocol.Types qualified as L
import Language.LSP.Test qualified as LT
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (createPipe)
import Test.Tasty
import Test.Tasty.HUnit

manifest :: BS.ByteString
manifest = "chapters = [\"a.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n"

-- | A project whose a.gm refers to a ragged TSV and a ragged CSV.
withTableProject :: (FilePath -> IO a) -> IO a
withTableProject act = withSystemTempDirectory "golem-lsp-tables" $ \tmp0 -> do
  tmp <- canonicalizePath tmp0
  forM_
    [ ("manifest.toml", manifest),
      ("a.gm", "@table src=data/x.tsv\n\n@table src=data/x.csv\n"),
      ("data/x.tsv", "a\tb\nc\n"),
      ("data/x.csv", "a,b\nc\n"),
      ("data/y.tsv", "a\tb\n1\t2\n")
    ]
    $ \(p, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> p)) >> BS.writeFile (tmp </> p) bytes
  act tmp

codesOf :: Workspace -> FilePath -> [Text]
codesOf ws p = [c | d <- fromMaybe [] (Map.lookup p (diagnosticsFor ws)), let DiagnosticCode c = diagCode d]

tableWatchTests :: TestTree
tableWatchTests =
  testGroup
    "table files (golem-eval ADR 0004)"
    [ testCase "G0285 is published on the table file" $ withTableProject $ \dir -> do
        ws <- openWorkspace dir
        codesOf ws "data/x.tsv" @?= ["G0285"]
        codesOf ws "data/x.csv" @?= ["G0285"],
      testCase "the editor's text of an open table file comes before the disk" $ withTableProject $ \dir -> do
        ws0 <- openWorkspace dir
        ws <- updateFile ws0 "data/x.tsv" "a\tb\nc\td\n"
        codesOf ws "data/x.tsv" @?= []
        codesOf ws "data/x.csv" @?= ["G0285"],
      testCase "the table files to watch, and which notifications re-evaluate" $ withTableProject $ \dir -> do
        ws <- openWorkspace dir
        tablesToWatch ws @?= Set.fromList ["data/x.csv", "data/x.tsv"]
        tableFilesChanged ws {wsWatchedTables = tablesToWatch ws} ["data/x.tsv"] @?= True
        tableFilesChanged ws {wsWatchedTables = tablesToWatch ws} ["data/y.tsv", "a.gm"] @?= False
        open <- updateFile ws "data/x.tsv" "a\tb\nc\n"
        tableFilesChanged open {wsWatchedTables = tablesToWatch ws} ["data/x.tsv"] @?= False,
      testCase "a client with dynamic registration watches the table files; a fixed file clears G0285" $ withTableProject $ \dir -> do
        (regs, cleared, afterSwitch, unchanged) <- lspSession True dir $ do
          _ <- waitDiagnostics dir "data/x.tsv" (not . null)
          regs <- watched
          liftIO (BS.writeFile (dir </> "data/x.tsv") "a\tb\nc\td\n")
          LT.sendNotification M.SMethod_WorkspaceDidChangeWatchedFiles (L.DidChangeWatchedFilesParams [L.FileEvent (L.filePathToUri (dir </> "data/x.tsv")) L.FileChangeType_Changed])
          cleared <- waitDiagnostics dir "data/x.tsv" null
          doc <- LT.openDoc "a.gm" "golem"
          LT.changeDoc doc [L.TextDocumentContentChangeEvent (L.InR (L.TextDocumentContentChangeWholeDocument "@table src=data/y.tsv\n"))]
          afterSwitch <- waitRegistration
          LT.changeDoc doc [L.TextDocumentContentChangeEvent (L.InR (L.TextDocumentContentChangeWholeDocument "本文。\n\n@table src=data/y.tsv\n"))]
          unchanged <- registrationsUntilDiagnostics dir "a.gm"
          pure (regs, cleared, afterSwitch, unchanged)
        regs @?= ["data/x.csv", "data/x.tsv"]
        cleared @?= []
        afterSwitch @?= ["data/y.tsv"]
        unchanged @?= 0,
      testCase "a client without dynamic registration is not asked to watch" $ withTableProject $ \dir -> do
        regs <- lspSession False dir $ do
          _ <- waitDiagnostics dir "data/x.tsv" (not . null)
          watched
        regs @?= [],
      testCase "a large table is G0288 at its @table (docs/adr ADR 0043)" $ withTableProject $ \dir -> do
        BS.writeFile (dir </> "data/big.tsv") (BS.concat (replicate 10001 "a\tb\n"))
        ws0 <- openWorkspace dir
        ws <- updateFile ws0 "a.gm" "本文。\n\n@table src=data/big.tsv\n"
        [(c, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- fromMaybe [] (Map.lookup "a.gm" (diagnosticsFor ws)), let DiagnosticCode c = diagCode d]
          @?= [("G0288", 11, 35)]
    ]

-- | A session against the server, with or without dynamic registration of watched files.
lspSession :: Bool -> FilePath -> LT.Session a -> IO a
lspSession dynamic dir s = do
  (serverIn, clientOut) <- createPipe
  (clientIn, serverOut) <- createPipe
  void (forkIO (void (runGolemLspWithHandles serverIn serverOut)))
  let caps = if dynamic then LT.fullLatestClientCaps else noWatching LT.fullLatestClientCaps
  r <- LT.runSessionWithHandles clientOut clientIn LT.defaultConfig {LT.ignoreRegistrationRequests = False} caps dir s
  hClose clientOut
  pure r
  where
    noWatching (L.ClientCapabilities w t n win gen ex) =
      L.ClientCapabilities (fmap (\ws -> ws {L._didChangeWatchedFiles = Nothing}) w) t n win gen ex

-- | The patterns of the registered watchers.
watched :: LT.Session [FilePath]
watched = sort . concatMap patterns <$> LT.getRegisteredCapabilities
  where
    patterns :: M.SomeRegistration -> [FilePath]
    patterns (M.SomeRegistration (M.TRegistration _ M.SMethod_WorkspaceDidChangeWatchedFiles (Just (L.DidChangeWatchedFilesRegistrationOptions ws)))) =
      [T.unpack p | L.FileSystemWatcher (L.GlobPattern (L.InR (L.RelativePattern _ (L.Pattern p)))) _ <- ws]
    patterns _ = []

-- | The diagnostics published for a file once they satisfy @ok@, by code.
waitDiagnostics :: FilePath -> FilePath -> ([Text] -> Bool) -> LT.Session [Text]
waitDiagnostics dir p ok = do
  msg <- LT.anyMessage
  case msg of
    M.FromServerMess M.SMethod_TextDocumentPublishDiagnostics (M.TNotificationMessage _ _ (L.PublishDiagnosticsParams u _ ds))
      | L.uriToFilePath u == Just (dir </> p),
        let cs = [c | L.Diagnostic _ _ (Just (L.InR c)) _ _ _ _ _ _ <- ds],
        ok cs ->
          pure cs
    _ -> waitDiagnostics dir p ok

-- | The patterns after the next registration.
waitRegistration :: LT.Session [FilePath]
waitRegistration = do
  msg <- LT.anyMessage
  case msg of
    M.FromServerMess M.SMethod_ClientRegisterCapability _ -> watched
    _ -> waitRegistration

-- | How many registrations come before the next diagnostics of a file.
registrationsUntilDiagnostics :: FilePath -> FilePath -> LT.Session Int
registrationsUntilDiagnostics dir p = go 0
  where
    go :: Int -> LT.Session Int
    go n = do
      msg <- LT.anyMessage
      case msg of
        M.FromServerMess M.SMethod_ClientRegisterCapability _ -> go (n + 1)
        M.FromServerMess M.SMethod_ClientUnregisterCapability _ -> go (n + 1)
        M.FromServerMess M.SMethod_TextDocumentPublishDiagnostics (M.TNotificationMessage _ _ (L.PublishDiagnosticsParams u _ _))
          | L.uriToFilePath u == Just (dir </> p) -> pure n
        _ -> go n
