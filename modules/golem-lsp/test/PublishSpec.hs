{-# LANGUAGE GADTs #-}

{- | What the server publishes after an edit, and that every edit is
evaluated (golem-lsp ADR 0005).
-}
module PublishSpec (publishTests) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forM_, void)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson qualified as J
import Data.ByteString.Lazy qualified as BL
import Data.List (nub, sort)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Golem.Lsp.Features (Encoding (..))
import Golem.Lsp.Server (rewriteInitializeResponse, runGolemLspWithHandles)
import Language.LSP.Protocol.Message qualified as M
import Language.LSP.Protocol.Types qualified as L
import Language.LSP.Test qualified as LT
import System.Directory (canonicalizePath, copyFile, createDirectoryIfMissing)
import System.FilePath (makeRelative, takeDirectory, (</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (createPipe)
import Test.Tasty
import Test.Tasty.HUnit

fixture :: FilePath
fixture = "test/fixtures/proj"

-- | A copy of the fixture project.
withFixture :: (FilePath -> IO a) -> IO a
withFixture act = withSystemTempDirectory "golem-lsp-publish" $ \tmp0 -> do
  tmp <- canonicalizePath tmp0
  forM_ ["manifest.toml", "style.toml", "a.gm", "b.gm", "common/values.gm"] $ \f ->
    createDirectoryIfMissing True (takeDirectory (tmp </> f)) >> copyFile (fixture </> f) (tmp </> f)
  act tmp

-- | b.gm of the fixture.
bOriginal :: Text
bOriginal = "@label second\n# 次の章\n\n[ref-title intro]と[ref-page intro]を見る。\n"

session :: FilePath -> LT.Session a -> IO a
session dir s = do
  (serverIn, clientOut) <- createPipe
  (clientIn, serverOut) <- createPipe
  void (forkIO (void (runGolemLspWithHandles serverIn serverOut)))
  r <- LT.runSessionWithHandles clientOut clientIn LT.defaultConfig LT.fullLatestClientCaps dir s
  hClose clientOut
  pure r

{- | Waits until the evaluations of the edits so far have finished, and
returns the diagnostics published meanwhile, as (file, codes), in order.
The pause is longer than the wait before evaluating; the response to a
request sent after it comes after everything published before it.
-}
settle :: FilePath -> L.TextDocumentIdentifier -> LT.Session [(FilePath, [Text])]
settle dir doc = do
  liftIO (threadDelay 1000000)
  lid <- LT.sendRequest M.SMethod_TextDocumentDocumentSymbol (L.DocumentSymbolParams Nothing Nothing doc)
  let go :: [(FilePath, [Text])] -> LT.Session [(FilePath, [Text])]
      go acc = do
        msg <- LT.anyMessage
        case msg of
          M.FromServerMess M.SMethod_TextDocumentPublishDiagnostics (M.TNotificationMessage _ _ (L.PublishDiagnosticsParams u _ ds)) ->
            go ((maybe "?" (makeRelative dir) (L.uriToFilePath u), mapMaybe codeOf ds) : acc)
          M.FromServerRsp M.SMethod_TextDocumentDocumentSymbol (M.TResponseMessage _ (Just i) _) | i == lid -> pure (reverse acc)
          _ -> go acc
  go []
  where
    codeOf (L.Diagnostic _ _ c _ _ _ _ _ _) = case c of
      Just (L.InR t) -> Just t
      _ -> Nothing

change :: L.TextDocumentIdentifier -> Text -> LT.Session ()
change doc t = LT.changeDoc doc [L.TextDocumentContentChangeEvent (L.InR (L.TextDocumentContentChangeWholeDocument t))]

-- | The codes last published for a file.
lastFor :: FilePath -> [(FilePath, [Text])] -> Maybe [Text]
lastFor p xs = case [cs | (q, cs) <- reverse xs, q == p] of
  (cs : _) -> Just cs
  [] -> Nothing

publishTests :: TestTree
publishTests =
  testGroup
    "publishing and evaluation order (golem-lsp ADR 0005)"
    [ testCase "the initialize response does not advertise semantic tokens" $ do
        let resp = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"positionEncoding\":\"utf-16\",\"hoverProvider\":true,\"semanticTokensProvider\":{\"legend\":{\"tokenTypes\":[],\"tokenModifiers\":[]}}}}}"
            expected = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"positionEncoding\":\"utf-16\",\"hoverProvider\":true}}}"
            decode = J.decode :: BL.ByteString -> Maybe J.Value
        (decode =<< rewriteInitializeResponse (M.IdInt 1) Utf16 resp) @?= decode expected,
      testCase "an edit that changes no other file's diagnostics is published for that file alone" $ withFixture $ \dir -> do
        published <- session dir $ do
          a <- LT.openDoc "a.gm" "golem"
          b <- LT.openDoc "b.gm" "golem"
          _ <- settle dir a
          change b (bOriginal <> "\n本文を足す。\n")
          settle dir b
        nub (map fst published) @?= ["b.gm"],
      testCase "an edit of another file within the wait does not drop the first edit" $ withFixture $ \dir -> do
        published <- session dir $ do
          a <- LT.openDoc "a.gm" "golem"
          b <- LT.openDoc "b.gm" "golem"
          _ <- settle dir a
          aText <- LT.documentContents a
          change b (bOriginal <> "\n[ref-page no-such-label]を見る。\n")
          change a (aText <> "\n本文を足す。\n")
          settle dir a
        fmap (elem "G04003") (lastFor "b.gm" published) @?= Just True
        sort (nub (map fst published)) @?= ["a.gm", "b.gm"],
      testCase "a fixed error clears the file's diagnostics" $ withFixture $ \dir -> do
        published <- session dir $ do
          b <- LT.openDoc "b.gm" "golem"
          _ <- settle dir b
          change b (bOriginal <> "\n[ref-page no-such-label]を見る。\n")
          broken <- settle dir b
          change b bOriginal
          fixed <- settle dir b
          pure (broken, fixed)
        fmap (elem "G04003") (lastFor "b.gm" (fst published)) @?= Just True
        lastFor "b.gm" (snd published) @?= Just []
    ]
