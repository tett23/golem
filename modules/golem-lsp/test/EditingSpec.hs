{-# LANGUAGE GADTs #-}

{- | Tests of renaming, formatting, closing a document and references
across imports (golem-lsp ADR 0001): the features over the fixture
project, and the requests over a client session.
-}
module EditingSpec (editingTests) where

import Control.Concurrent (forkIO)
import Control.Monad (void)
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.Features
import Golem.Lsp.Server (runGolemLspWithHandles)
import Golem.Lsp.Workspace
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..), Severity (..))
import Language.LSP.Protocol.Message qualified as M
import Language.LSP.Protocol.Types qualified as L
import Language.LSP.Test qualified as LT
import System.Directory (makeAbsolute)
import System.FilePath ((</>))
import System.IO (hClose)
import System.Process (createPipe)
import Test.Tasty
import Test.Tasty.HUnit

root :: FilePath
root = "test/fixtures/proj"

textOf :: Workspace -> FilePath -> Text
textOf ws p = maybe "" srcText (sourceOf ws p)

-- | The byte offset of the k-th byte of the first occurrence of a needle in a file.
at :: Workspace -> FilePath -> Text -> Int -> Int
at ws p needle k = BS.length (TE.encodeUtf8 (fst (T.breakOn needle (textOf ws p)))) + k

-- | A location as its file and the text it spans.
slice :: Workspace -> Location -> (FilePath, Text)
slice ws (Location p s e) = (p, TE.decodeUtf8 (BS.take (e - s) (BS.drop s (TE.encodeUtf8 (textOf ws p)))))

errorsIn :: Workspace -> FilePath -> [Text]
errorsIn ws p = [c | d <- fromMaybe [] (Map.lookup p (diagnosticsFor ws)), diagSeverity d == Error, let DiagnosticCode c = diagCode d]

featureTests :: [TestTree]
featureTests =
  [ testCase "references of an imported variable from its definition include the namespaced uses" $ do
      ws <- openWorkspace root
      map (slice ws) (references ws "common/values.gm" (at ws "common/values.gm" "version" 0))
        @?= [("common/values.gm", "version"), ("a.gm", "values.version")],
    testCase "references of a namespaced variable find its definition in the imported file" $ do
      ws <- openWorkspace root
      map (slice ws) (references ws "a.gm" (at ws "a.gm" "values.version" 8))
        @?= [("common/values.gm", "version"), ("a.gm", "values.version")],
    testCase "definition of a variable of the file is its @set" $ do
      ws0 <- openWorkspace root
      ws <- updateFile ws0 "b.gm" "@set count = 3\n\n@label second\n# 次の章\n\n[= count]\n"
      definition ws "b.gm" (at ws "b.gm" "count]" 1) @?= [Location "b.gm" 5 10],
    testCase "references of a variable of the file are its @set and its uses" $ do
      ws0 <- openWorkspace root
      ws <- updateFile ws0 "b.gm" "@set count = 3\n\n@label second\n# 次の章\n\n[= count]と[= count + 1]\n"
      map (slice ws) (references ws "b.gm" (at ws "b.gm" "count]" 1)) @?= [("b.gm", "count"), ("b.gm", "count"), ("b.gm", "count")],
    testCase "rename refuses a name with a space" $ do
      ws <- openWorkspace root
      renameLabel ws "a.gm" (at ws "a.gm" "intro" 0) "two words" @?= Left (InvalidName "two words"),
    testCase "rename refuses an empty name" $ do
      ws <- openWorkspace root
      renameLabel ws "a.gm" (at ws "a.gm" "intro" 0) "" @?= Left (InvalidName ""),
    testCase "rename from a reference rewrites the definition too" $ do
      ws <- openWorkspace root
      fmap (map (first (slice ws))) (renameLabel ws "b.gm" (at ws "b.gm" "intro]" 0) "opening")
        @?= Right [(("a.gm", "intro"), "opening"), (("b.gm", "intro"), "opening"), (("b.gm", "intro"), "opening")],
    testCase "formatting a formatted file is no edit" $ do
      ws <- openWorkspace root
      formatting ws "b.gm" @?= Nothing,
    testCase "closing a file drops its unsaved text and its diagnostics" $ do
      ws0 <- openWorkspace root
      edited <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n[strong: 閉じない\n"
      closed <- closeFile edited "b.gm"
      (errorsIn edited "b.gm" /= [], errorsIn closed "b.gm", textOf closed "b.gm")
        @?= (True, [], "@label second\n# 次の章\n\n[ref-title intro]と[ref-page intro]を見る。\n")
  ]

-- ------------------------------------------------------------------ sessions

withUtf16 :: L.ClientCapabilities -> L.ClientCapabilities
withUtf16 (L.ClientCapabilities w t n win gen ex) =
  let L.GeneralClientCapabilities st re md _ = fromMaybe (L.GeneralClientCapabilities Nothing Nothing Nothing Nothing) gen
   in L.ClientCapabilities w t n win (Just (L.GeneralClientCapabilities st re md (Just [L.PositionEncodingKind_UTF16]))) ex

{- | A UTF-16 client session against the server on the fixture project; a
message that does not come within 10 seconds fails the test.
-}
inSession :: (FilePath -> LT.Session a) -> IO a
inSession act = do
  absRoot <- makeAbsolute root
  (serverIn, clientOut) <- createPipe
  (clientIn, serverOut) <- createPipe
  void (forkIO (void (runGolemLspWithHandles serverIn serverOut)))
  r <- LT.runSessionWithHandles clientOut clientIn LT.defaultConfig {LT.messageTimeout = 10} (withUtf16 LT.fullLatestClientCaps) absRoot (act absRoot)
  hClose clientOut
  pure r

docOf :: FilePath -> FilePath -> L.TextDocumentIdentifier
docOf absRoot p = L.TextDocumentIdentifier (L.filePathToUri (absRoot </> p))

-- | The diagnostic codes of the next publication for a file that satisfies a condition.
publishedFor :: FilePath -> ([Text] -> Bool) -> LT.Session [Text]
publishedFor path ok = do
  msg <- LT.anyMessage
  case msg of
    M.FromServerMess M.SMethod_TextDocumentPublishDiagnostics (M.TNotificationMessage _ _ (L.PublishDiagnosticsParams u _ ds))
      | L.uriToFilePath u == Just path,
        let codes = [c | L.Diagnostic _ _ (Just (L.InR c)) _ _ _ _ _ _ <- ds],
        ok codes ->
          pure codes
    _ -> publishedFor path ok

{- | The edits of a workspace edit as file, range and new text, in the
order of the document: the edits of a file apply together, so their order
in the list carries no meaning.
-}
editsOf :: FilePath -> L.WorkspaceEdit -> [(Maybe FilePath, L.Range, Text)]
editsOf absRoot (L.WorkspaceEdit changes _ _) =
  sortOn
    (\(p, L.Range (L.Position l c) _, _) -> (p, l, c))
    [ (drop (length absRoot + 1) <$> L.uriToFilePath u, r, t)
    | (u, es) <- Map.toList (fromMaybe Map.empty changes),
      L.TextEdit r t <- es
    ]

range :: Int -> Int -> Int -> Int -> L.Range
range l1 c1 l2 c2 = L.Range (L.Position (fromIntegral l1) (fromIntegral c1)) (L.Position (fromIntegral l2) (fromIntegral c2))

sessionTests :: [TestTree]
sessionTests =
  [ testCase "rename answers one workspace edit over both files" $ do
      r <- inSession $ \absRoot -> do
        M.TResponseMessage _ _ res <- LT.request M.SMethod_TextDocumentRename (L.RenameParams Nothing (docOf absRoot "a.gm") (L.Position 2 8) "opening")
        pure (either (const []) (\case L.InL e -> editsOf absRoot e; L.InR _ -> []) res)
      -- a.gm line 2 is "@label intro"; b.gm line 3 is "[ref-title intro]と[ref-page intro]を見る。"
      r
        @?= [ (Just "a.gm", range 2 7 2 12, "opening"),
              (Just "b.gm", range 3 11 3 16, "opening"),
              (Just "b.gm", range 3 28 3 33, "opening")
            ],
    testCase "rename to an existing label is refused with an error response" $ do
      r <- inSession $ \absRoot -> do
        M.TResponseMessage _ _ res <- LT.request M.SMethod_TextDocumentRename (L.RenameParams Nothing (docOf absRoot "a.gm") (L.Position 2 8) "second")
        pure (either (\(M.TResponseError code _ _) -> Just code) (const Nothing) res)
      r @?= Just (L.InR L.ErrorCodes_InvalidRequest),
    testCase "formatting answers one edit that replaces the whole document" $ do
      r <- inSession $ \absRoot -> do
        doc <- LT.openDoc "b.gm" "golem"
        LT.changeDoc doc [L.TextDocumentContentChangeEvent (L.InR (L.TextDocumentContentChangeWholeDocument "@label second\n# 改めた章\n\n\n\n[ref-title   nosuch]\n"))]
        -- the G0403 of the edited text: the workspace has it (a new heading re-evaluates the project)
        _ <- publishedFor (absRoot </> "b.gm") (elem "G0403")
        M.TResponseMessage _ _ res <- LT.request M.SMethod_TextDocumentFormatting (L.DocumentFormattingParams Nothing doc (L.FormattingOptions 2 True Nothing Nothing Nothing))
        pure (either (const []) (\case L.InL es -> [(rg, t) | L.TextEdit rg t <- es]; L.InR _ -> []) res)
      r @?= [(range 0 0 6 0, "@label second\n# 改めた章\n\n[ref-title nosuch]\n")],
    testCase "closing an edited document publishes the diagnostics of the file on disk" $ do
      r <- inSession $ \absRoot -> do
        doc <- LT.openDoc "b.gm" "golem"
        LT.changeDoc doc [L.TextDocumentContentChangeEvent (L.InR (L.TextDocumentContentChangeWholeDocument "@label second\n# 改めた章\n\n[ref-title nosuch]\n"))]
        _ <- publishedFor (absRoot </> "b.gm") (elem "G0403")
        LT.closeDoc doc
        publishedFor (absRoot </> "b.gm") (const True)
      r @?= []
  ]

editingTests :: TestTree
editingTests =
  testGroup
    "renaming, formatting, closing and imports (ADR 0001)"
    [ testGroup "features" featureTests,
      testGroup "protocol" sessionTests
    ]
