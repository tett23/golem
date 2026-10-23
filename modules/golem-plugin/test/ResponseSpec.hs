{- | The response of a plugin as the host reads it (golem-plugin ADR 0001):
the diagnostics a plugin returns with its output, and the malformed
responses and descriptions that the host rejects as bad output. The
plugin is fixed.wat, which answers every call with the bytes the test
puts into it.
-}
module ResponseSpec (responseTests) where

import Codec.CBOR.Term (Term (..), encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Control.Monad (void)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Doc.Assemble (ChannelDecl (..), ChannelOrder (..))
import Golem.Doc.Cbor (documentTerm, inlinesTerm)
import Golem.Doc.IR
import Golem.Eval.Value (Value (..))
import Golem.Plugin
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

cbor :: Term -> ByteString
cbor = toStrictByteString . encodeTerm

{- | The usual description: one command, shout, one filter, upper, and two
channels, glossary in reading order and people in document order with
locators (golem-doc ADR 0007).
-}
shoutAndUpper :: ByteString
shoutAndUpper = cbor (TList [TList [TString "shout"], TList [TString "upper"], TList [decl "glossary" 1 False, decl "people" 0 True]])
  where
    decl n o l = TList [TString n, TInt o, TBool l]

{- | fixed.wat filled with a description and a response; the ABI version
is the host's.
-}
fixedPlugin :: ByteString -> ByteString -> IO ByteString
fixedPlugin describe response = do
  src <- TIO.readFile "test/plugins/fixed.wat"
  let escape = T.pack . concatMap (printf "\\%02x") . BS.unpack
      filled =
        T.replace "{{ABI}}" (T.pack (show Golem.Plugin.abiVersion))
          . T.replace "{{DESCRIBE}}" (escape describe)
          . T.replace "{{DESCRIBE_LEN}}" (T.pack (show (BS.length describe)))
          . T.replace "{{RESPONSE}}" (escape response)
          . T.replace "{{RESPONSE_LEN}}" (T.pack (show (BS.length response)))
          $ src
  watToWasm filled >>= either (assertFailure . T.unpack) pure

-- | A plugin that answers every call with the response.
answering :: ByteString -> IO Plugin
answering response = do
  wasm <- fixedPlugin shoutAndUpper response
  loadPlugin wasm >>= either (assertFailure . show) pure

callSpan :: SrcSpan
callSpan = mkSpan (FileId 1) 10 20

-- | The command shout, called at callSpan with one slot.
shout :: Plugin -> Either PluginError ([Inline], [Diagnostic])
shout p = callCommand p "shout" [VString "x"] [[Text callSpan "slot"]] callSpan

-- | A response of the inlines [Text callSpan "SLOT"] with the diagnostics.
withDiagnostics :: [Term] -> ByteString
withDiagnostics ds = cbor (TList [inlinesTerm [Text callSpan "SLOT"], TList ds])

-- | A plugin-diagnostic of the CDDL: [code, severity, span, message].
pluginDiagnostic :: Text -> Int -> Text -> Term
pluginDiagnostic code severity msg = TList [TString code, TInt severity, TList [TInt 1, TInt 10, TInt 20], TString msg]

responseTests :: TestTree
responseTests =
  testGroup
    "the response of a plugin (golem-plugin ADR 0001)"
    [ diagnosticTests,
      channelTests,
      malformedResponseTests,
      malformedDescriptionTests,
      testCase "a hash as an argument is bad output before the plugin runs" $ do
        p <- answering (withDiagnostics [])
        callCommand p "shout" [VHash mempty] [] callSpan @?= Left (BadOutput "ハッシュはプラグインに渡せません"),
      describeErrorTests
    ]

diagnosticTests :: TestTree
diagnosticTests =
  testGroup
    "diagnostics returned by a plugin"
    [ testCase "a warning of a command comes back with its code, span and message" $ do
        p <- answering (withDiagnostics [pluginDiagnostic "X0001" 1 "読みが推測です"])
        shout p @?= Right ([Text callSpan "SLOT"], [diagnostic "X0001" Warning callSpan "読みが推測です"]),
      testCase "severity 0 is an error" $ do
        p <- answering (withDiagnostics [pluginDiagnostic "X0002" 0 "読めません"])
        fmap snd (shout p) @?= Right [diagnostic "X0002" Error callSpan "読めません"],
      testCase "several diagnostics keep the order of the response" $ do
        p <- answering (withDiagnostics [pluginDiagnostic "X0003" 1 "二つ目より前", pluginDiagnostic "X0001" 0 "後"])
        fmap (map diagCode . snd) (shout p) @?= Right [DiagnosticCode "X0003", DiagnosticCode "X0001"],
      testCase "a filter returns its diagnostics with the document" $ do
        let doc = Document (FileId 1) [Block callSpan Nothing (Paragraph Nothing [Text callSpan "a"])]
        p <- answering (cbor (TList [documentTerm doc, TList [pluginDiagnostic "X0004" 1 "総ルビにしました"]]))
        applyFilter p "upper" doc @?= Right (doc, [diagnostic "X0004" Warning callSpan "総ルビにしました"])
    ]

malformedResponseTests :: TestTree
malformedResponseTests =
  testGroup
    "malformed responses are bad output"
    [ testCase "severity 2" $ do
        p <- answering (withDiagnostics [pluginDiagnostic "X0001" 2 "m"])
        shout p @?= Left (BadOutput "診断の重大度が不正です"),
      testCase "a diagnostic without its message" $ do
        p <- answering (withDiagnostics [TList [TString "X0001", TInt 1, TList [TInt 1, TInt 10, TInt 20]]])
        shout p @?= Left (BadOutput "診断の形が不正です"),
      testCase "a diagnostic whose code is a number" $ do
        p <- answering (withDiagnostics [TList [TInt 1, TInt 1, TList [TInt 1, TInt 10, TInt 20], TString "m"]])
        shout p @?= Left (BadOutput "診断の形が不正です"),
      testCase "a diagnostic whose span ends before it starts" $ do
        p <- answering (withDiagnostics [TList [TString "X0001", TInt 1, TList [TInt 1, TInt 20, TInt 10], TString "m"]])
        shout p @?= Left (BadOutput "スキーマに合いません: 位置の範囲"),
      testCase "a response of three elements" $ do
        p <- answering (cbor (TList [inlinesTerm [Text callSpan "SLOT"], TList [], TList []]))
        shout p @?= Left (BadOutput "応答の形が不正です"),
      testCase "a response whose diagnostics are not a list" $ do
        p <- answering (cbor (TList [inlinesTerm [Text callSpan "SLOT"], TInt 0]))
        shout p @?= Left (BadOutput "応答の形が不正です"),
      testCase "bytes after the CBOR of the response" $ do
        p <- answering (withDiagnostics [] <> BS.pack [0x00])
        shout p @?= Left (BadOutput "CBOR の後ろに余分なバイトがあります"),
      testCase "a Number out of int64 is out of range, G06009 (golem-doc ADR 0006)" $ do
        let numberOf n = TList [TList [TInt 9, TList [TInt 1, TInt 10, TInt 20], TInteger n, TNull]]
        mapM_
          ( \n -> do
              p <- answering (cbor (TList [numberOf n, TList []]))
              shout p @?= Left (BadOutput "スキーマに合いません: 整数が範囲の外です")
          )
          [2 ^ (63 :: Int), 2 ^ (70 :: Int), negate (2 ^ (63 :: Int)) - 1]
        p <- answering (cbor (TList [numberOf (2 ^ (63 :: Int) - 1), TList []]))
        fmap fst (shout p) @?= Right [Number callSpan (2 ^ (63 :: Int) - 1) Nothing],
      testCase "a filter that answers with inlines instead of a document" $ do
        let doc = Document (FileId 1) [Block callSpan Nothing (Paragraph Nothing [Text callSpan "a"])]
        p <- answering (withDiagnostics [])
        case applyFilter p "upper" doc of
          Left (BadOutput _) -> pure ()
          other -> assertFailure (show other)
    ]

-- | The channels of a plugin (golem-doc ADR 0007).
channelTests :: TestTree
channelTests =
  testGroup
    "the channels of a plugin (golem-doc ADR 0007)"
    [ testCase "the description of three fields gives the channels" $ do
        p <- answering (withDiagnostics [])
        pluginChannels p @?= [ChannelDecl "glossary" OrderReading False, ChannelDecl "people" OrderDocument True],
      testCase "a description of two fields is bad output" $ do
        wasm <- fixedPlugin (cbor (TList [TList [TString "shout"], TList [TString "upper"]])) (withDiagnostics [])
        loadPlugin wasm >>= (@?= Left (BadOutput "golem_describe の形が不正です")) . void,
      testCase "an item of a channel the plugin declares comes back" $ do
        let it = item "glossary" (Just "かな") [Text callSpan "語"]
        p <- answering (itemsResponse [it])
        fmap fst (shout p) @?= Right [it],
      testCase "an item of a channel the plugin does not declare is bad output" $ do
        p <- answering (itemsResponse [item "other" Nothing [Text callSpan "語"]])
        shout p @?= Left (BadOutput "宣言していないチャネルです: other"),
      testCase "an item of a channel in reading order without a reading is bad output" $ do
        p <- answering (itemsResponse [item "glossary" Nothing [Text callSpan "語"]])
        shout p @?= Left (BadOutput "読みの順のチャネルの項目には読みが要ります: glossary")
        p' <- answering (itemsResponse [item "glossary" (Just "") [Text callSpan "語"]])
        shout p' @?= Left (BadOutput "読みの順のチャネルの項目には読みが要ります: glossary"),
      testCase "an item whose body holds a note is bad output" $ do
        p <- answering (itemsResponse [item "people" Nothing [Note callSpan 1 [Text callSpan "注"]]])
        shout p @?= Left (BadOutput "チャネルの項目の本文に置けない要素があります")
    ]
  where
    item c r body = ChannelItem callSpan (ChannelItemData c (Just "k") r body)
    itemsResponse is = cbor (TList [inlinesTerm is, TList []])

malformedDescriptionTests :: TestTree
malformedDescriptionTests =
  testGroup
    "a malformed golem_describe is rejected when loading"
    [ testCase "a description of one list" $ do
        wasm <- fixedPlugin (cbor (TList [TList [TString "shout"]])) (withDiagnostics [])
        loadPlugin wasm >>= (@?= Left (BadOutput "golem_describe の形が不正です")) . void,
      testCase "a command name that is not a string" $ do
        wasm <- fixedPlugin (cbor (TList [TList [TInt 1], TList [], TList []])) (withDiagnostics [])
        loadPlugin wasm >>= (@?= Left (BadOutput "名前が文字列ではありません")) . void,
      testCase "a filter name that is not a string" $ do
        wasm <- fixedPlugin (cbor (TList [TList [], TList [TBool True], TList []])) (withDiagnostics [])
        loadPlugin wasm >>= (@?= Left (BadOutput "名前が文字列ではありません")) . void
    ]

-- | The reasons of G06005 and G06009 as golem-plugin ADR 0003 writes them.
describeErrorTests :: TestTree
describeErrorTests =
  testGroup
    "describePluginError (golem-plugin ADR 0003)"
    [ testCase "CompileFailed" $ describePluginError (CompileFailed "d") @?= "プラグインを読み込めません: d",
      testCase "HasImports" $ describePluginError (HasImports ["env.now", "env.rand"]) @?= "プラグインが import を要求しています: env.now, env.rand",
      testCase "AbiMismatch" $ describePluginError (AbiMismatch 5) @?= "プラグインの ABI のバージョンが異なります: 5",
      testCase "MissingExport" $ describePluginError (MissingExport "golem_invoke") @?= "プラグインが関数を公開していません: golem_invoke",
      testCase "OutOfFuel" $ describePluginError (OutOfFuel "detail") @?= "プラグインの実行が命令数の上限を超えました",
      testCase "Trapped" $ describePluginError (Trapped "d") @?= "プラグインの実行が失敗しました（メモリの上限を超えた場合を含む）: d",
      testCase "InstantiateFailed" $ describePluginError (InstantiateFailed "d") @?= "プラグインを起動できません: d",
      testCase "BadOutput" $ describePluginError (BadOutput "d") @?= "プラグインの出力が不正です: d"
    ]
