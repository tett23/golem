{-# LANGUAGE DuplicateRecordFields #-}

{- | The language server over standard input and output (golem-lsp ADR
0001). Positions are exchanged in UTF-16: the lsp package (2.8) fixes
the server's position encoding to UTF-16 and does not negotiate.
-}
module Golem.Lsp.Server
  ( runGolemLsp,
    serverDefinition,
    findRoot,
  )
where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM
import Control.Monad (forM_, join, void, when)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.Features qualified as F
import Golem.Lsp.Workspace
import Golem.Syntax qualified as S
import Language.LSP.Protocol.Message
import Language.LSP.Protocol.Types
import Language.LSP.Server
import Language.LSP.VFS (virtualFileText)
import System.Directory (doesFileExist, makeAbsolute)
import System.FilePath (makeRelative, takeDirectory, (</>))

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
runGolemLsp = serverDefinition >>= runServer

serverDefinition :: IO (ServerDefinition ())
serverDefinition = do
  wsVar <- newTVarIO Nothing
  gen <- newTVarIO 0
  rootVar <- newTVarIO "."
  pure $
    ServerDefinition
      { parseConfig = const (const (Right ())),
        onConfigChange = const (pure ()),
        defaultConfig = (),
        configSection = "golem",
        doInitialize = \env _ -> do
          root <- findRoot (fromMaybe "." (resRootPath env))
          atomically (writeTVar rootVar root)
          pure (Right env),
        staticHandlers = \_ -> handlers rootVar wsVar gen,
        interpretHandler = \env -> Iso (runLspT env) liftIO,
        options =
          defaultOptions
            { optTextDocumentSync = Just (TextDocumentSyncOptions (Just True) (Just TextDocumentSyncKind_Full) Nothing Nothing Nothing),
              optCompletionTriggerCharacters = Just ['[', ' ']
            }
      }

handlers :: TVar FilePath -> TVar (Maybe Workspace) -> TVar Int -> Handlers (LspM ())
handlers rootVar wsVar gen =
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
        r <- atPosition doc pos $ \ws p off ->
          pure (map (toLocation ws) (F.definition ws p off))
        respond (Right (InR (InL (maybe [] (map toLink) r)))),
      requestHandler SMethod_TextDocumentReferences $ \(TRequestMessage _ _ _ (ReferenceParams doc pos _ _ _)) respond -> do
        r <- atPosition doc pos $ \ws p off -> pure (map (toLspLocation . toLocation ws) (F.references ws p off))
        respond (Right (InL (fromMaybe [] r))),
      requestHandler SMethod_TextDocumentRename $ \(TRequestMessage _ _ _ (RenameParams _ doc pos newName)) respond -> do
        r <- atPosition doc pos $ \ws p off -> pure (fmap (toEdit ws) (F.renameLabel ws p off newName))
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
        mws <- liftIO (readTVarIO wsVar)
        let edits = fromMaybe [] $ do
              ws <- mws
              p <- relPath st docUri
              src <- sourceOf ws p
              new <- F.formatting ws p
              let li = S.mkLineIndex (srcText src)
                  end = S.offsetToUtf16LineCol li (byteLength (srcText src))
              pure [TextEdit (Range (Position 0 0) (toPosition end)) new]
        respond (Right (InL edits)),
      requestHandler SMethod_TextDocumentDocumentSymbol $ \(TRequestMessage _ _ _ (DocumentSymbolParams _ _ (TextDocumentIdentifier docUri))) respond -> do
        st <- state
        mws <- liftIO (readTVarIO wsVar)
        let syms = fromMaybe [] $ do
              ws <- mws
              p <- relPath st docUri
              src <- sourceOf ws p
              let li = S.mkLineIndex (srcText src)
              pure (map (symbol li) (F.outline ws p))
        respond (Right (InR (InL syms)))
    ]
  where
    state = do
      root <- liftIO (readTVarIO rootVar)
      pure (State root)
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
      mws <- liftIO (readTVarIO wsVar)
      let TextDocumentIdentifier docUri = doc
      case (mws, relPath st docUri) of
        (Just ws, Just p) | Just src <- sourceOf ws p -> do
          let li = S.mkLineIndex (srcText src)
          case F.fromLineCol F.Utf16 li (fromPosition pos) of
            Just off -> Just <$> k ws p off
            Nothing -> pure Nothing
        _ -> pure Nothing
    relPath st uri = makeRelative (stRoot st) <$> uriToFilePath uri
    toLocation ws (F.Location p s e) = (ws, p, s, e)
    toLspLocation (ws, p, s, e) = Location (fileUri ws p) (rangeIn ws p s e)
    toLink (ws, p, s, e) = DefinitionLink (LocationLink Nothing (fileUri ws p) (rangeIn ws p s e) (rangeIn ws p s e))
    fileUri ws p = filePathToUri (wsRoot ws </> p)
    toEdit ws pairs =
      WorkspaceEdit
        (Just (Map.fromListWith (<>) [(fileUri ws p, [TextEdit (rangeIn ws p s e) t]) | (F.Location p s e, t) <- pairs]))
        Nothing
        Nothing
    renameMessage = \case
      F.NotALabel -> "ラベルの上で名前を変更してください"
      F.LabelExists l -> "すでにあるラベルの名前です: " <> l
      F.InvalidName l -> "ラベルに使えない名前です: " <> l
    publishAll old ws = do
      let now = diagnosticsFor ws
          cleared = Map.map (const []) (Map.difference old now)
      forM_ (Map.toList (Map.union now cleared)) $ \(p, ds) -> do
        let li = maybe (S.mkLineIndex "") (S.mkLineIndex . srcText) (sourceOf ws p)
        sendNotification SMethod_TextDocumentPublishDiagnostics (PublishDiagnosticsParams (fileUri ws p) Nothing (map (toDiagnostic li) ds))

rangeIn :: Workspace -> FilePath -> Int -> Int -> Range
rangeIn ws p s e =
  let li = maybe (S.mkLineIndex "") (S.mkLineIndex . srcText) (sourceOf ws p)
   in Range (toPosition (S.offsetToUtf16LineCol li s)) (toPosition (S.offsetToUtf16LineCol li e))

toPosition :: S.LineCol -> Position
toPosition (S.LineCol l c) = Position (fromIntegral l) (fromIntegral c)

fromPosition :: Position -> S.LineCol
fromPosition (Position l c) = S.LineCol (fromIntegral l) (fromIntegral c)

byteLength :: Text -> Int
byteLength = BS.length . TE.encodeUtf8

toDiagnostic :: S.LineIndex -> S.Diagnostic -> Diagnostic
toDiagnostic li d =
  let sp = S.diagSpan d
      S.DiagnosticCode code = S.diagCode d
   in Diagnostic
        (Range (toPosition (S.offsetToUtf16LineCol li (S.spanStart sp))) (toPosition (S.offsetToUtf16LineCol li (S.spanEnd sp))))
        (Just (if S.diagSeverity d == S.Error then DiagnosticSeverity_Error else DiagnosticSeverity_Warning))
        (Just (InR code))
        Nothing
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

symbol :: S.LineIndex -> F.Outline -> DocumentSymbol
symbol li o =
  let r = Range (toPosition (S.offsetToUtf16LineCol li (F.olStart o))) (toPosition (S.offsetToUtf16LineCol li (F.olEnd o)))
   in DocumentSymbol (if T.null (F.olTitle o) then "（無題）" else F.olTitle o) Nothing SymbolKind_String Nothing Nothing r r (Just (map (symbol li) (F.olChildren o)))
