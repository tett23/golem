{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}

{- | The language server over standard input and output (golem-lsp ADR
0001). The position encoding is negotiated (ADR 0002): UTF-8 when the
client offers it, UTF-16 otherwise. The lsp package (2.8) always answers
UTF-16 in the initialize response, so the response is rewritten on its
way out; with full-text sync the package never interprets positions
itself.
-}
module Golem.Lsp.Server
  ( runGolemLsp,
    runGolemLspWithHandles,
    rewriteInitializeResponse,
    findRoot,
    lspSeverity,
  )
where

import Colog.Core (LogAction, WithSeverity (..))
import Colog.Core qualified as L
import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM
import Control.Monad (forM_, guard, join, void, when)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson qualified as J
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Builder.Extra (defaultChunkSize)
import Data.ByteString.Lazy qualified as BSL
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver.Explain (codeDescriptionUrl)
import Golem.Lsp.Features qualified as F
import Golem.Lsp.Workspace
import Golem.Syntax qualified as S
import Language.LSP.Logging (defaultClientLogger)
import Language.LSP.Protocol.Message
import Language.LSP.Protocol.Types
import Language.LSP.Server
import Language.LSP.VFS (virtualFileText)
import Prettyprinter (pretty, viaShow)
import System.Directory (doesFileExist, makeAbsolute)
import System.FilePath (makeRelative, takeDirectory, (</>))
import System.IO (BufferMode (..), Handle, hFlush, hSetBuffering, hSetEncoding, stdin, stdout, utf8)

newtype State = State {stRoot :: FilePath}

-- | The nearest directory upwards that has manifest.toml.
findRoot :: FilePath -> IO FilePath
findRoot dir0 = do
  dir <- makeAbsolute dir0
  let go d = do
        e <- doesFileExist (d </> "manifest.toml")
        if e || takeDirectory d == d then pure (if e then d else dir) else go (takeDirectory d)
  go dir

-- | Waits this long after the last change before evaluating.
debounceMicros :: Int
debounceMicros = 250000

runGolemLsp :: IO Int
runGolemLsp = runGolemLspWithHandles stdin stdout

{- | The server over the given input and output. Messages pass through
'rewriteInitializeResponse' until the initialize response has been
rewritten; the header is added afterwards, since the length may change.
-}
runGolemLspWithHandles :: Handle -> Handle -> IO Int
runGolemLspWithHandles hin hout = do
  hSetBuffering hin NoBuffering
  hSetEncoding hin utf8
  hSetBuffering hout NoBuffering
  hSetEncoding hout utf8
  encVar <- newTVarIO F.Utf16
  initIdVar <- newTVarIO Nothing
  rewritten <- newTVarIO False
  def <- serverDefinition encVar initIdVar
  let rewrite out = do
        done <- readTVarIO rewritten
        if done
          then pure out
          else do
            mid <- readTVarIO initIdVar
            enc <- readTVarIO encVar
            case mid >>= \i -> rewriteInitializeResponse i enc out of
              Just out' -> atomically (writeTVar rewritten True) >> pure out'
              Nothing -> pure out
  runServerWithConfig
    ServerConfig
      { ioLogger = ioLog,
        lspLogger = L.cmap (fmap (T.pack . show . pretty)) defaultClientLogger <> L.hoistLogAction liftIO ioLog,
        inwards = BS.hGetSome hin defaultChunkSize,
        outwards = \out -> do
          out' <- rewrite out
          BSL.hPut hout (prependHeader out')
          hFlush hout,
        prepareOutwards = id,
        parseInwards = parseHeaders
      }
    def
  where
    -- the same as the lsp package's runServer: every log line to stderr
    ioLog :: LogAction IO (WithSeverity LspServerLog)
    ioLog = L.cmap (\l -> show ("[" <> viaShow (L.getSeverity l) <> "] " <> pretty (L.getMsg l))) L.logStringStderr

{- | Sets @capabilities.positionEncoding@ of the initialize response with
the given id to the negotiated encoding. Anything else is 'Nothing'.
-}
rewriteInitializeResponse :: LspId Method_Initialize -> F.Encoding -> BSL.ByteString -> Maybe BSL.ByteString
rewriteInitializeResponse lid enc bytes = do
  J.Object msg <- J.decode bytes
  i <- KM.lookup "id" msg
  guard (i == J.toJSON lid)
  J.Object result <- KM.lookup "result" msg
  J.Object caps <- KM.lookup "capabilities" result
  let caps' = KM.insert "positionEncoding" (J.toJSON (F.encodingKind enc)) caps
      result' = KM.insert "capabilities" (J.Object caps') result
  pure (J.encode (J.Object (KM.insert "result" (J.Object result') msg)))

serverDefinition :: TVar F.Encoding -> TVar (Maybe (LspId Method_Initialize)) -> IO (ServerDefinition ())
serverDefinition encVar initIdVar = do
  wsVar <- newTVarIO Nothing
  gen <- newTVarIO 0
  rootVar <- newTVarIO "."
  pure $
    ServerDefinition
      { parseConfig = const (const (Right ())),
        onConfigChange = const (pure ()),
        defaultConfig = (),
        configSection = "golem",
        -- called before the lsp package sends the initialize response
        doInitialize = \env (TRequestMessage _ lid _ params) -> do
          root <- findRoot (fromMaybe "." (resRootPath env))
          atomically $ do
            writeTVar rootVar root
            writeTVar encVar (F.chooseEncoding (offeredEncodings params))
            writeTVar initIdVar (Just lid)
          pure (Right env),
        staticHandlers = \_ -> handlers encVar rootVar wsVar gen,
        interpretHandler = \env -> Iso (runLspT env) liftIO,
        options =
          defaultOptions
            { optTextDocumentSync = Just (TextDocumentSyncOptions (Just True) (Just TextDocumentSyncKind_Full) Nothing Nothing Nothing),
              optCompletionTriggerCharacters = Just ['[', ' ']
            }
      }

-- | @capabilities.general.positionEncodings@ of the initialize request.
offeredEncodings :: InitializeParams -> Maybe [PositionEncodingKind]
offeredEncodings (InitializeParams _ _ _ _ _ _ (ClientCapabilities _ _ _ _ general _) _ _ _) =
  general >>= \(GeneralClientCapabilities _ _ _ encs) -> encs

handlers :: TVar F.Encoding -> TVar FilePath -> TVar (Maybe Workspace) -> TVar Int -> Handlers (LspM ())
handlers encVar rootVar wsVar gen =
  mconcat
    [ notificationHandler SMethod_Initialized $ \_ -> do
        root <- liftIO (readTVarIO rootVar)
        ws <- liftIO (openWorkspace root)
        liftIO (atomically (writeTVar wsVar (Just ws)))
        publishAll Map.empty ws,
      notificationHandler SMethod_TextDocumentDidOpen $ \(TNotificationMessage _ _ (DidOpenTextDocumentParams (TextDocumentItem uri _ _ _))) ->
        changed uri,
      notificationHandler SMethod_TextDocumentDidChange $ \(TNotificationMessage _ _ (DidChangeTextDocumentParams (VersionedTextDocumentIdentifier uri _) _)) ->
        changed uri,
      notificationHandler SMethod_TextDocumentDidSave $ \_ -> pure (),
      notificationHandler SMethod_WorkspaceDidChangeConfiguration $ \_ -> pure (),
      notificationHandler SMethod_TextDocumentDidClose $ \(TNotificationMessage _ _ (DidCloseTextDocumentParams (TextDocumentIdentifier uri))) -> do
        st <- state
        forM_ (relPath st uri) $ \p -> withWs $ \ws -> do
          ws' <- liftIO (closeFile ws p)
          liftIO (atomically (writeTVar wsVar (Just ws')))
          publishAll (diagnosticsFor ws) ws',
      requestHandler SMethod_TextDocumentDefinition $ \(TRequestMessage _ _ _ (DefinitionParams doc pos _ _)) respond -> do
        enc <- encoding
        r <- atPosition doc pos $ \ws p off ->
          pure (map (toLocation ws) (F.definition ws p off))
        respond (Right (InR (InL (maybe [] (map (toLink enc)) r)))),
      requestHandler SMethod_TextDocumentReferences $ \(TRequestMessage _ _ _ (ReferenceParams doc pos _ _ _)) respond -> do
        enc <- encoding
        r <- atPosition doc pos $ \ws p off -> pure (map (toLspLocation enc . toLocation ws) (F.references ws p off))
        respond (Right (InL (fromMaybe [] r))),
      requestHandler SMethod_TextDocumentRename $ \(TRequestMessage _ _ _ (RenameParams _ doc pos newName)) respond -> do
        enc <- encoding
        r <- atPosition doc pos $ \ws p off -> pure (fmap (toEdit enc ws) (F.renameLabel ws p off newName))
        case r of
          Just (Right edit) -> respond (Right (InL edit))
          Just (Left e) -> respond (Left (TResponseError (InR ErrorCodes_InvalidRequest) (renameMessage e) Nothing))
          Nothing -> respond (Right (InR Null)),
      requestHandler SMethod_TextDocumentCompletion $ \(TRequestMessage _ _ _ (CompletionParams doc pos _ _ _)) respond -> do
        r <- atPosition doc pos $ \ws p off -> pure (F.completions ws p off)
        respond (Right (InL (maybe [] (map completionItem) r))),
      requestHandler SMethod_TextDocumentHover $ \(TRequestMessage _ _ _ (HoverParams doc pos _)) respond -> do
        r <- atPosition doc pos $ \ws p off -> pure (F.hover ws p off)
        respond (Right (maybe (InR Null) (\t -> InL (Hover (InL (MarkupContent MarkupKind_PlainText t)) Nothing)) (join r))),
      requestHandler SMethod_TextDocumentFormatting $ \(TRequestMessage _ _ _ (DocumentFormattingParams _ (TextDocumentIdentifier docUri) _)) respond -> do
        st <- state
        enc <- encoding
        mws <- liftIO (readTVarIO wsVar)
        let edits = fromMaybe [] $ do
              ws <- mws
              p <- relPath st docUri
              src <- sourceOf ws p
              new <- F.formatting ws p
              let end = F.toLineCol enc (lineIndexOf ws p) (byteLength (srcText src))
              pure [TextEdit (Range (Position 0 0) (toPosition end)) new]
        respond (Right (InL edits)),
      requestHandler SMethod_TextDocumentDocumentSymbol $ \(TRequestMessage _ _ _ (DocumentSymbolParams _ _ (TextDocumentIdentifier docUri))) respond -> do
        st <- state
        enc <- encoding
        mws <- liftIO (readTVarIO wsVar)
        let syms = fromMaybe [] $ do
              ws <- mws
              p <- relPath st docUri
              _ <- sourceOf ws p
              pure (map (symbol enc (lineIndexOf ws p)) (F.outline ws p))
        respond (Right (InR (InL syms)))
    ]
  where
    state = do
      root <- liftIO (readTVarIO rootVar)
      pure (State root)
    encoding = liftIO (readTVarIO encVar)
    withWs k = liftIO (readTVarIO wsVar) >>= maybe (pure ()) k
    -- full-text sync: the VFS holds the text; evaluate after a pause
    changed uri = do
      st <- state
      forM_ (relPath st uri) $ \p -> do
        g <- liftIO (atomically (modifyTVar' gen (+ 1) >> readTVar gen))
        env <- getLspEnv
        void . liftIO . forkIO $ do
          threadDelay debounceMicros
          current <- readTVarIO gen
          when (current == g) $ runLspT env $ do
            mvf <- getVirtualFile (toNormalizedUri uri)
            forM_ mvf $ \vf -> withWs $ \ws -> do
              ws' <- liftIO (updateFile ws p (virtualFileText vf))
              liftIO (atomically (writeTVar wsVar (Just ws')))
              publishAll (diagnosticsFor ws) ws'
    atPosition doc pos k = do
      st <- state
      enc <- encoding
      mws <- liftIO (readTVarIO wsVar)
      let TextDocumentIdentifier docUri = doc
      case (mws, relPath st docUri) of
        (Just ws, Just p) | Just _ <- sourceOf ws p -> do
          case F.fromLineCol enc (lineIndexOf ws p) (fromPosition pos) of
            Just off -> Just <$> k ws p off
            Nothing -> pure Nothing
        _ -> pure Nothing
    relPath st uri = makeRelative (stRoot st) <$> uriToFilePath uri
    toLocation ws (F.Location p s e) = (ws, p, s, e)
    toLspLocation enc (ws, p, s, e) = Location (fileUri ws p) (rangeIn enc ws p s e)
    toLink enc (ws, p, s, e) = DefinitionLink (LocationLink Nothing (fileUri ws p) (rangeIn enc ws p s e) (rangeIn enc ws p s e))
    fileUri ws p = filePathToUri (wsRoot ws </> p)
    toEdit enc ws pairs =
      WorkspaceEdit
        (Just (Map.fromListWith (<>) [(fileUri ws p, [TextEdit (rangeIn enc ws p s e) t]) | (F.Location p s e, t) <- pairs]))
        Nothing
        Nothing
    renameMessage = \case
      F.NotALabel -> "ラベルの上で名前を変更してください"
      F.LabelExists l -> "すでにあるラベルの名前です: " <> l
      F.InvalidName l -> "ラベルに使えない名前です: " <> l
    publishAll old ws = do
      enc <- encoding
      let now = diagnosticsFor ws
          cleared = Map.map (const []) (Map.difference old now)
      forM_ (Map.toList (Map.union now cleared)) $ \(p, ds) ->
        sendNotification SMethod_TextDocumentPublishDiagnostics (PublishDiagnosticsParams (fileUri ws p) Nothing (map (toDiagnostic enc (lineIndexOf ws p)) ds))

rangeIn :: F.Encoding -> Workspace -> FilePath -> Int -> Int -> Range
rangeIn enc ws p s e =
  let li = lineIndexOf ws p
   in Range (toPosition (F.toLineCol enc li s)) (toPosition (F.toLineCol enc li e))

toPosition :: S.LineCol -> Position
toPosition (S.LineCol l c) = Position (fromIntegral l) (fromIntegral c)

fromPosition :: Position -> S.LineCol
fromPosition (Position l c) = S.LineCol (fromIntegral l) (fromIntegral c)

byteLength :: Text -> Int
byteLength = BS.length . TE.encodeUtf8

{- | A notice is Information, not Hint: editors list Information among the
problems, and a notice is meant to be read (golem-syntax ADR 0002).
-}
lspSeverity :: S.Severity -> DiagnosticSeverity
lspSeverity = \case
  S.Error -> DiagnosticSeverity_Error
  S.Warning -> DiagnosticSeverity_Warning
  S.Notice -> DiagnosticSeverity_Information

toDiagnostic :: F.Encoding -> S.LineIndex -> S.Diagnostic -> Diagnostic
toDiagnostic enc li d =
  let sp = S.diagSpan d
      S.DiagnosticCode code = S.diagCode d
   in Diagnostic
        (Range (toPosition (F.toLineCol enc li (S.spanStart sp))) (toPosition (F.toLineCol enc li (S.spanEnd sp))))
        (Just (lspSeverity (S.diagSeverity d)))
        (Just (InR code))
        -- the section of docs/diagnostics.md on main (golem-cli ADR 0005)
        (CodeDescription . Uri <$> codeDescriptionUrl (S.diagCode d))
        (Just "golem")
        (S.diagMessage d)
        Nothing
        Nothing
        Nothing

completionItem :: F.Completion -> CompletionItem
completionItem (F.Completion label kind) =
  CompletionItem label Nothing (Just k) Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing
  where
    k = case kind of
      F.CkCommand -> CompletionItemKind_Function
      F.CkLabel -> CompletionItemKind_Reference
      F.CkPath -> CompletionItemKind_File
      F.CkSwatch -> CompletionItemKind_Color
      F.CkCharStyle -> CompletionItemKind_Value
      F.CkParaStyle -> CompletionItemKind_Value
      F.CkSettingKey -> CompletionItemKind_Property
      F.CkSettingValue -> CompletionItemKind_EnumMember
      F.CkStyleKind -> CompletionItemKind_Keyword

symbol :: F.Encoding -> S.LineIndex -> F.Outline -> DocumentSymbol
symbol enc li o =
  let r = Range (toPosition (F.toLineCol enc li (F.olStart o))) (toPosition (F.toLineCol enc li (F.olEnd o)))
   in DocumentSymbol (if T.null (F.olTitle o) then "（無題）" else F.olTitle o) Nothing SymbolKind_String Nothing Nothing r r (Just (map (symbol enc li) (F.olChildren o)))
