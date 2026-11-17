{-# LANGUAGE GADTs #-}

-- | The highlighting of .gm files by semantic tokens (golem-lsp ADR 0006).
module SemanticTokensSpec (semanticTokensTests) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forM_, void)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson qualified as J
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (isRight)
import Data.IntSet qualified as IS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.Features (Encoding (..), commandBytes, semanticTokens)
import Golem.Lsp.Server (rewriteInitializeResponse, runGolemLspWithHandles)
import Golem.TestSupport.Gen (genText)
import Hedgehog (Gen, forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Language.LSP.Protocol.Message qualified as M
import Language.LSP.Protocol.Types qualified as L
import Language.LSP.Test qualified as LT
import System.Directory (canonicalizePath, copyFile, createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (createPipe)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

type Tok = (L.UInt, L.UInt, L.UInt, L.SemanticTokenTypes, [L.SemanticTokenModifiers])

toks :: Encoding -> Text -> [Tok]
toks enc src = [(l, c, n, t, m) | L.SemanticTokenAbsolute l c n t m <- semanticTokens enc src]

fixture :: FilePath
fixture = "test/fixtures/proj"

withFixture :: (FilePath -> IO a) -> IO a
withFixture act = withSystemTempDirectory "golem-lsp-tokens" $ \tmp0 -> do
  tmp <- canonicalizePath tmp0
  forM_ ["manifest.toml", "style.toml", "a.gm", "b.gm", "common/values.gm"] $ \f ->
    createDirectoryIfMissing True (takeDirectory (tmp </> f)) >> copyFile (fixture </> f) (tmp </> f)
  act tmp

session :: FilePath -> LT.Session a -> IO a
session dir s = do
  (serverIn, clientOut) <- createPipe
  (clientIn, serverOut) <- createPipe
  void (forkIO (void (runGolemLspWithHandles serverIn serverOut)))
  r <- LT.runSessionWithHandles clientOut clientIn LT.defaultConfig LT.fullLatestClientCaps dir s
  hClose clientOut
  pure r

fullTokens :: L.TextDocumentIdentifier -> LT.Session [L.UInt]
fullTokens doc = do
  rsp <- LT.request M.SMethod_TextDocumentSemanticTokensFull (L.SemanticTokensParams Nothing Nothing doc)
  case rsp of
    M.TResponseMessage _ _ (Right (L.InL (L.SemanticTokens _ ds))) -> pure ds
    _ -> liftIO (assertFailure ("no tokens: " <> show rsp)) >> pure []

semanticTokensTests :: TestTree
semanticTokensTests =
  testGroup
    "semantic tokens (golem-lsp ADR 0006)"
    [ testCase "commands, arguments, headings, expressions and comments" $
        toks Utf8 "@label intro\n# 見出し\n\n[ruby 漢字: かんじ]と[= f(1, x.y) + 2]。%%=校正%%\n"
          @?= [ (0, 0, 1, L.SemanticTokenTypes_Decorator, []),
                (0, 1, 5, L.SemanticTokenTypes_Decorator, []),
                (0, 6, 1, L.SemanticTokenTypes_Operator, []),
                (0, 7, 5, L.SemanticTokenTypes_String, []),
                (1, 0, 1, L.SemanticTokenTypes_Keyword, []),
                (1, 2, 9, L.SemanticTokenTypes_Namespace, []),
                (3, 0, 1, L.SemanticTokenTypes_Operator, []),
                (3, 1, 4, L.SemanticTokenTypes_Function, []),
                (3, 5, 1, L.SemanticTokenTypes_Operator, []),
                (3, 6, 6, L.SemanticTokenTypes_String, []),
                (3, 12, 1, L.SemanticTokenTypes_Operator, []),
                (3, 13, 1, L.SemanticTokenTypes_Operator, []),
                (3, 23, 1, L.SemanticTokenTypes_Operator, []),
                (3, 27, 2, L.SemanticTokenTypes_Keyword, []),
                (3, 29, 1, L.SemanticTokenTypes_Operator, []),
                (3, 30, 1, L.SemanticTokenTypes_Function, []),
                (3, 31, 1, L.SemanticTokenTypes_Operator, []),
                (3, 32, 1, L.SemanticTokenTypes_Number, []),
                (3, 33, 1, L.SemanticTokenTypes_Operator, []),
                (3, 34, 1, L.SemanticTokenTypes_Operator, []),
                (3, 35, 1, L.SemanticTokenTypes_Variable, []),
                (3, 36, 1, L.SemanticTokenTypes_Operator, []),
                (3, 37, 1, L.SemanticTokenTypes_Variable, []),
                (3, 38, 1, L.SemanticTokenTypes_Operator, []),
                (3, 39, 1, L.SemanticTokenTypes_Operator, []),
                (3, 40, 1, L.SemanticTokenTypes_Operator, []),
                (3, 41, 1, L.SemanticTokenTypes_Operator, []),
                (3, 42, 1, L.SemanticTokenTypes_Number, []),
                (3, 43, 1, L.SemanticTokenTypes_Operator, []),
                (3, 47, 11, L.SemanticTokenTypes_Comment, [L.SemanticTokenModifiers_Modification])
              ],
      testCase "code blocks, lists, definition lists, tables and keyword arguments" $
        toks Utf8 "```haskell\nmain = 1\n```\n\n- 一\n+ 二\n\n= 版面\n  説明。\n\n| a | b |\n|---|---|\n\n@figure x.png alt=\"図\"\n"
          @?= [ (0, 0, 3, L.SemanticTokenTypes_Keyword, []),
                (0, 3, 7, L.SemanticTokenTypes_Type, []),
                (2, 0, 3, L.SemanticTokenTypes_Keyword, []),
                (4, 0, 1, L.SemanticTokenTypes_Keyword, []),
                (5, 0, 1, L.SemanticTokenTypes_Keyword, []),
                (7, 0, 1, L.SemanticTokenTypes_Keyword, []),
                (10, 0, 1, L.SemanticTokenTypes_Operator, []),
                (10, 4, 1, L.SemanticTokenTypes_Operator, []),
                (10, 8, 1, L.SemanticTokenTypes_Operator, []),
                (11, 0, 1, L.SemanticTokenTypes_Operator, []),
                (11, 1, 3, L.SemanticTokenTypes_Operator, []),
                (11, 4, 1, L.SemanticTokenTypes_Operator, []),
                (11, 5, 3, L.SemanticTokenTypes_Operator, []),
                (11, 8, 1, L.SemanticTokenTypes_Operator, []),
                (13, 0, 1, L.SemanticTokenTypes_Decorator, []),
                (13, 1, 6, L.SemanticTokenTypes_Decorator, []),
                (13, 7, 1, L.SemanticTokenTypes_Operator, []),
                (13, 8, 5, L.SemanticTokenTypes_String, []),
                (13, 13, 1, L.SemanticTokenTypes_Operator, []),
                (13, 14, 3, L.SemanticTokenTypes_Parameter, []),
                (13, 17, 1, L.SemanticTokenTypes_Operator, []),
                (13, 18, 5, L.SemanticTokenTypes_String, [])
              ],
      testCase "escapes and number shorthands" $
        toks Utf8 "\\[ ##12##\n"
          @?= [ (0, 0, 2, L.SemanticTokenTypes_Macro, []),
                (0, 3, 2, L.SemanticTokenTypes_Operator, []),
                (0, 5, 2, L.SemanticTokenTypes_Number, []),
                (0, 7, 2, L.SemanticTokenTypes_Operator, [])
              ],
      testCase "columns after Japanese text are counted in the negotiated unit" $ do
        toks Utf8 "あ😀[em: x]\n" @?= [(0, 7, 1, L.SemanticTokenTypes_Operator, []), (0, 8, 2, L.SemanticTokenTypes_Function, []), (0, 10, 1, L.SemanticTokenTypes_Operator, []), (0, 11, 1, L.SemanticTokenTypes_Operator, []), (0, 13, 1, L.SemanticTokenTypes_Operator, [])]
        toks Utf16 "あ😀[em: x]\n" @?= [(0, 3, 1, L.SemanticTokenTypes_Operator, []), (0, 4, 2, L.SemanticTokenTypes_Function, []), (0, 6, 1, L.SemanticTokenTypes_Operator, []), (0, 7, 1, L.SemanticTokenTypes_Operator, []), (0, 9, 1, L.SemanticTokenTypes_Operator, [])],
      testCase "a comment over two lines is two tokens" $ do
        toks Utf8 "%% あ\nb %%\n" @?= [(0, 0, 6, L.SemanticTokenTypes_Comment, []), (1, 0, 4, L.SemanticTokenTypes_Comment, [])]
        toks Utf16 "%% あ\nb %%\n" @?= [(0, 0, 4, L.SemanticTokenTypes_Comment, []), (1, 0, 4, L.SemanticTokenTypes_Comment, [])],
      testCase "no tokens for text, prose slots, code and errors" $ do
        toks Utf8 "本文だけ。\n" @?= []
        toks Utf8 "[strong: 閉じない\n" @?= [(0, 0, 1, L.SemanticTokenTypes_Operator, []), (0, 1, 6, L.SemanticTokenTypes_Function, []), (0, 7, 1, L.SemanticTokenTypes_Operator, []), (0, 8, 1, L.SemanticTokenTypes_Operator, [])]
        toks Utf8 "= 用語\n: 説明\n" @?= [],
      testProperty "tokens are in document order, do not overlap, and encode with the default legend" . property $ do
        src <- forAll genText
        let ts = toks Utf16 src
            ordered = and (zipWith before ts (drop 1 ts))
            before (l1, c1, n1, _, _) (l2, c2, _, _, _) = l1 < l2 || (l1 == l2 && c1 + n1 <= c2)
        (ordered, all (\(_, _, n, _, _) -> n > 0) ts) === (True, True)
        isRight (L.makeSemanticTokens L.defaultSemanticTokensLegend [L.SemanticTokenAbsolute l c n t m | (l, c, n, t, m) <- ts]) === True,
      testCase "the brackets, colons and pipes of commands and the punctuation of expressions (golem-lsp ADR 0007)" $
        toks Utf8 "[ruby: 霧笛|むてき]は[= book.liters(12)]リットル。[book.stamp 赤]消印\n"
          @?= [ (0, 0, 1, L.SemanticTokenTypes_Operator, []),
                (0, 1, 4, L.SemanticTokenTypes_Function, []),
                (0, 5, 1, L.SemanticTokenTypes_Operator, []),
                (0, 6, 1, L.SemanticTokenTypes_Operator, []),
                (0, 13, 1, L.SemanticTokenTypes_Operator, []),
                (0, 23, 1, L.SemanticTokenTypes_Operator, []),
                (0, 27, 2, L.SemanticTokenTypes_Keyword, []),
                (0, 29, 1, L.SemanticTokenTypes_Operator, []),
                (0, 30, 4, L.SemanticTokenTypes_Function, []),
                (0, 34, 1, L.SemanticTokenTypes_Operator, []),
                (0, 35, 6, L.SemanticTokenTypes_Function, []),
                (0, 41, 1, L.SemanticTokenTypes_Operator, []),
                (0, 42, 2, L.SemanticTokenTypes_Number, []),
                (0, 44, 1, L.SemanticTokenTypes_Operator, []),
                (0, 45, 1, L.SemanticTokenTypes_Operator, []),
                (0, 61, 1, L.SemanticTokenTypes_Operator, []),
                (0, 62, 10, L.SemanticTokenTypes_Function, []),
                (0, 72, 1, L.SemanticTokenTypes_Operator, []),
                (0, 73, 3, L.SemanticTokenTypes_String, []),
                (0, 76, 1, L.SemanticTokenTypes_Operator, [])
              ],
      testCase "a prose slot over lines and nested commands give tokens that do not overlap (golem-lsp ADR 0007)" $ do
        let src = "[strong: 一行目の[em: 中]と\n  二行目の[= f(x, [1, {a: 2}])]。]\n"
            ts = toks Utf16 src
            before (l1, c1, n1, _, _) (l2, c2, _, _, _) = l1 < l2 || (l1 == l2 && c1 + n1 <= c2)
        and (zipWith before ts (drop 1 ts)) @?= True
        [(l, c) | (l, c, _, L.SemanticTokenTypes_Operator, _) <- ts]
          @?= [(0, 0), (0, 7), (0, 8), (0, 13), (0, 16), (0, 17), (0, 19), (1, 8), (1, 10), (1, 12), (1, 13), (1, 14), (1, 16), (1, 17), (1, 18), (1, 20), (1, 21), (1, 23), (1, 24), (1, 25), (1, 26), (1, 28)],
      testCase "the spaces and the equals signs of arguments (golem-lsp ADR 0008)" $
        [(c, n) | (0, c, n, L.SemanticTokenTypes_Operator, []) <- toks Utf8 "[figure a.png alt=\"図\" width=10]\n"]
          @?= [(0, 1), (7, 1), (13, 1), (17, 1), (23, 1), (29, 1), (32, 1)],
      testCase "the spaces after the name and the colon, not the prose slot (golem-lsp ADR 0008)" $ do
        let ts = toks Utf8 "[ruby 漢字: かんじ]\n"
        [c | (0, c, 1, L.SemanticTokenTypes_Operator, []) <- ts] @?= [0, 5, 12, 13, 23]
        [c | (_, c, _, _, _) <- ts, c >= 14, c < 23] @?= [],
      testCase "the spaces after the colon and the pipe, not those of the prose slots (golem-lsp ADR 0008)" $ do
        let ts = toks Utf8 "[strong: 強 | 弱 ]\n"
        [c | (0, c, 1, L.SemanticTokenTypes_Operator, []) <- ts] @?= [0, 7, 8, 13, 14, 19]
        [c | (_, c, _, _, _) <- ts, (c >= 9 && c < 13) || (c >= 15 && c < 19)] @?= [],
      testCase "splat arguments and the expressions in them (golem-lsp ADR 0008)" $
        toks Utf8 "[x *[a.b] **[f(1)]]\n"
          @?= [ (0, 0, 1, L.SemanticTokenTypes_Operator, []),
                (0, 1, 1, L.SemanticTokenTypes_Function, []),
                (0, 2, 1, L.SemanticTokenTypes_Operator, []),
                (0, 3, 2, L.SemanticTokenTypes_Operator, []),
                (0, 5, 1, L.SemanticTokenTypes_Variable, []),
                (0, 6, 1, L.SemanticTokenTypes_Operator, []),
                (0, 7, 1, L.SemanticTokenTypes_Variable, []),
                (0, 8, 1, L.SemanticTokenTypes_Operator, []),
                (0, 9, 1, L.SemanticTokenTypes_Operator, []),
                (0, 10, 3, L.SemanticTokenTypes_Operator, []),
                (0, 13, 1, L.SemanticTokenTypes_Function, []),
                (0, 14, 1, L.SemanticTokenTypes_Operator, []),
                (0, 15, 1, L.SemanticTokenTypes_Number, []),
                (0, 16, 1, L.SemanticTokenTypes_Operator, []),
                (0, 17, 1, L.SemanticTokenTypes_Operator, []),
                (0, 18, 1, L.SemanticTokenTypes_Operator, [])
              ],
      testCase "the keys and the spaces of a hash (golem-lsp ADR 0008)" $
        toks Utf8 "[= {a: 1, \"b\": 2}]\n"
          @?= [ (0, 0, 2, L.SemanticTokenTypes_Keyword, []),
                (0, 2, 1, L.SemanticTokenTypes_Operator, []),
                (0, 3, 1, L.SemanticTokenTypes_Operator, []),
                (0, 4, 1, L.SemanticTokenTypes_Property, []),
                (0, 5, 1, L.SemanticTokenTypes_Operator, []),
                (0, 6, 1, L.SemanticTokenTypes_Operator, []),
                (0, 7, 1, L.SemanticTokenTypes_Number, []),
                (0, 8, 1, L.SemanticTokenTypes_Operator, []),
                (0, 9, 1, L.SemanticTokenTypes_Operator, []),
                (0, 10, 3, L.SemanticTokenTypes_String, []),
                (0, 13, 1, L.SemanticTokenTypes_Operator, []),
                (0, 14, 1, L.SemanticTokenTypes_Operator, []),
                (0, 15, 1, L.SemanticTokenTypes_Number, []),
                (0, 16, 1, L.SemanticTokenTypes_Operator, []),
                (0, 17, 1, L.SemanticTokenTypes_Operator, [])
              ],
      testCase "the name, the equals sign and the expression of @set (golem-lsp ADR 0008)" $
        toks Utf8 "@set x = 1 + y.z\n"
          @?= [ (0, 0, 1, L.SemanticTokenTypes_Decorator, []),
                (0, 1, 3, L.SemanticTokenTypes_Decorator, []),
                (0, 4, 1, L.SemanticTokenTypes_Operator, []),
                (0, 5, 1, L.SemanticTokenTypes_Variable, [L.SemanticTokenModifiers_Declaration]),
                (0, 6, 1, L.SemanticTokenTypes_Operator, []),
                (0, 7, 1, L.SemanticTokenTypes_Operator, []),
                (0, 8, 1, L.SemanticTokenTypes_Operator, []),
                (0, 9, 1, L.SemanticTokenTypes_Number, []),
                (0, 10, 1, L.SemanticTokenTypes_Operator, []),
                (0, 11, 1, L.SemanticTokenTypes_Operator, []),
                (0, 12, 1, L.SemanticTokenTypes_Operator, []),
                (0, 13, 1, L.SemanticTokenTypes_Variable, []),
                (0, 14, 1, L.SemanticTokenTypes_Operator, []),
                (0, 15, 1, L.SemanticTokenTypes_Variable, [])
              ],
      testCase "ADR 0336 I1: semantic tokens of set have no @ decorator" $
        toks Utf8 "set x = 1\n"
          @?= [ (0, 0, 3, L.SemanticTokenTypes_Decorator, []),
                (0, 3, 1, L.SemanticTokenTypes_Operator, []),
                (0, 4, 1, L.SemanticTokenTypes_Variable, [L.SemanticTokenModifiers_Declaration]),
                (0, 5, 1, L.SemanticTokenTypes_Operator, []),
                (0, 6, 1, L.SemanticTokenTypes_Operator, []),
                (0, 7, 1, L.SemanticTokenTypes_Operator, []),
                (0, 8, 1, L.SemanticTokenTypes_Number, [])
              ],
      testCase "not the indentation of a block command, but its other spaces (golem-lsp ADR 0008)" $
        [t | t@(l, _, _, _, _) <- toks Utf8 "@box\n  @label x\n  本文\n", l > 0]
          @?= [ (1, 2, 1, L.SemanticTokenTypes_Decorator, []),
                (1, 3, 5, L.SemanticTokenTypes_Decorator, []),
                (1, 8, 1, L.SemanticTokenTypes_Operator, []),
                (1, 9, 1, L.SemanticTokenTypes_String, [])
              ],
      testCase "the spaces at the end of a block command (golem-lsp ADR 0008)" $
        toks Utf8 "@label intro  \n"
          @?= [ (0, 0, 1, L.SemanticTokenTypes_Decorator, []),
                (0, 1, 5, L.SemanticTokenTypes_Decorator, []),
                (0, 6, 1, L.SemanticTokenTypes_Operator, []),
                (0, 7, 5, L.SemanticTokenTypes_String, []),
                (0, 12, 2, L.SemanticTokenTypes_Operator, [])
              ],
      testCase "no tokens for the spaces of text, headings, lists and definition lists (golem-lsp ADR 0008)" $
        [(l, c) | (l, c, _, _, _) <- toks Utf8 "[a] [b]\n\n# 見出し\n\n- a\n\n= 用語\n  定義\n", (l, c) `elem` [(0, 3), (2, 1), (4, 1), (6, 1)]] @?= [],
      testCase "the mark of a new definition (golem-lsp ADR 0008)" $
        toks Utf8 "= 用語\n  定義\n=:\n  別\n" @?= [(0, 0, 1, L.SemanticTokenTypes_Keyword, []), (2, 0, 2, L.SemanticTokenTypes_Keyword, [])],
      testProperty "every byte of commands and expressions is in a token (golem-lsp ADR 0008)" . property $ do
        src <- forAll (Gen.choice [genText, genCommands])
        let covered = tokenBytes src
        [(s, e) | (s, e) <- commandBytes src, not (all (`IS.member` covered) [s .. e - 1])] === [],
      testProperty "tokens of commands are in document order, do not overlap, and encode with the default legend (golem-lsp ADR 0008)" . property $ do
        src <- forAll genCommands
        let ts = toks Utf16 src
            ordered = and (zipWith before ts (drop 1 ts))
            before (l1, c1, n1, _, _) (l2, c2, _, _, _) = l1 < l2 || (l1 == l2 && c1 + n1 <= c2)
        (ordered, all (\(_, _, n, _, _) -> n > 0) ts) === (True, True)
        isRight (L.makeSemanticTokens L.defaultSemanticTokensLegend [L.SemanticTokenAbsolute l c n t m | (l, c, n, t, m) <- ts]) === True,
      testCase "the initialize response keeps semanticTokensProvider" $ do
        let resp = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"positionEncoding\":\"utf-16\",\"semanticTokensProvider\":{\"full\":{\"delta\":false}}}}}"
            expected = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"positionEncoding\":\"utf-8\",\"semanticTokensProvider\":{\"full\":{\"delta\":false}}}}}"
            decode = J.decode :: BL.ByteString -> Maybe J.Value
        (decode =<< rewriteInitializeResponse (M.IdInt 1) Utf8 resp) @?= decode expected,
      testCase "the server advertises full semantic tokens with a legend, without range or delta" $ withFixture $ \dir -> do
        caps <- session dir $ do
          M.TResponseMessage _ _ r <- LT.initializeResponse
          pure (either (const Nothing) (\(L.InitializeResult c _) -> Just (J.toJSON c)) r)
        let provider = do
              J.Object o <- caps
              J.Object p <- KM.lookup "semanticTokensProvider" o
              pure p
        fmap (KM.lookup "legend") provider @?= Just (Just (J.toJSON L.defaultSemanticTokensLegend))
        fmap (KM.lookup "range") provider @?= Just Nothing
        fmap (KM.lookup "full") provider @?= Just (Just (J.object ["delta" J..= False])),
      testCase "tokens follow the editor's text at once, before the evaluation" $ withFixture $ \dir -> do
        ds <- session dir $ do
          doc <- LT.openDoc "b.gm" "golem"
          LT.changeDoc doc [L.TextDocumentContentChangeEvent (L.InR (L.TextDocumentContentChangeWholeDocument "本文。\n\n@label x\n"))]
          fullTokens doc
        ds @?= [2, 0, 1, 0, 0, 0, 1, 5, 0, 0, 0, 5, 1, 0, 0, 0, 1, 1, 0, 0] `withTypes` [L.SemanticTokenTypes_Decorator, L.SemanticTokenTypes_Decorator, L.SemanticTokenTypes_Operator, L.SemanticTokenTypes_String],
      testCase "style.toml has no tokens" $ withFixture $ \dir -> do
        ds <- session dir $ do
          doc <- LT.openDoc "style.toml" "toml"
          fullTokens doc
        ds @?= [],
      testCase "$/cancelRequest is answered by nothing" $ withFixture $ \dir -> do
        logged <- session dir $ do
          doc <- LT.openDoc "b.gm" "golem"
          _ <- fullTokens doc
          LT.sendNotification M.SMethod_CancelRequest (L.CancelParams (L.InL 999))
          liftIO (threadDelay 300000)
          lid <- LT.sendRequest M.SMethod_TextDocumentDocumentSymbol (L.DocumentSymbolParams Nothing Nothing doc)
          let go :: [Text] -> LT.Session [Text]
              go acc = do
                msg <- LT.anyMessage
                case msg of
                  M.FromServerMess M.SMethod_WindowLogMessage (M.TNotificationMessage _ _ (L.LogMessageParams _ t)) -> go (t : acc)
                  M.FromServerMess M.SMethod_WindowShowMessage (M.TNotificationMessage _ _ (L.ShowMessageParams _ t)) -> go (t : acc)
                  M.FromServerRsp M.SMethod_TextDocumentDocumentSymbol (M.TResponseMessage _ (Just i) _) | i == lid -> pure acc
                  _ -> go acc
          go []
        logged @?= []
    ]
  where
    -- the bytes of the text in a semantic token, from its UTF-8 lines and columns
    tokenBytes src =
      let bytes = TE.encodeUtf8 src
          starts = 0 : [i + 1 | i <- BS.elemIndices 10 bytes]
       in IS.fromList [s + k | (l, c, n, _, _) <- toks Utf8 src, let s = starts !! fromIntegral l + fromIntegral c, k <- [0 .. fromIntegral n - 1]]
    -- the index of each type in the default legend, at the fourth of every five
    withTypes xs ts = [if i `mod` 5 == 3 then typeIndex (ts !! (i `div` 5)) else x | (i, x) <- zip [0 :: Int ..] xs]
    typeIndex t =
      let L.SemanticTokensLegend tys _ = L.defaultSemanticTokensLegend
       in maybe 0 fromIntegral (lookup (L.toEnumBaseType t) (zip tys [0 :: Int ..]))

-- | Texts made of pieces of commands and expressions, prose and spaces.
genCommands :: Gen Text
genCommands =
  T.concat
    <$> Gen.list
      (Range.linear 0 40)
      ( Gen.element
          [ "[",
            "]",
            ":",
            "|",
            " ",
            "  ",
            "\n",
            "\n  ",
            "@",
            "@set ",
            "@label ",
            "@box",
            "[=",
            "*[",
            "**[",
            "=",
            "=:",
            "= ",
            "# ",
            "- ",
            "x",
            "a.b",
            "f(",
            ")",
            ",",
            "{",
            "}",
            "1",
            "+",
            "\"s\"",
            "漢字",
            "本文",
            "%% c %%",
            "\\",
            "##1##",
            "a=1",
            "[em: ",
            "[ruby 漢字: "
          ]
      )
