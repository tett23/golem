{- | The context of the book a plugin asks for (docs/adr/0121): the field
context of golem_describe, and the context in a request, before the data.
-}
module ContextSpec (contextTests) where

import Codec.CBOR.Read (deserialiseFromBytes)
import Codec.CBOR.Term (Term (..), decodeTerm)
import Control.Monad (void)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Doc.Cbor (documentTerm)
import Golem.Doc.IR hiding (abiVersion)
import Golem.Plugin
import Golem.Syntax
import Support (callSpan, cbor)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

-- | fixed.wat with a description; it answers every call with an empty response.
describing :: Term -> IO (Either PluginError Plugin)
describing describe = do
  src <- TIO.readFile "test/plugins/fixed.wat"
  let d = cbor describe
      r = cbor (TList [TList [], TList []])
      escape = T.pack . concatMap (printf "\\%02x") . BS.unpack
      filled =
        T.replace "{{ABI}}" (T.pack (show abiVersion))
          . T.replace "{{DESCRIBE}}" (escape d)
          . T.replace "{{DESCRIBE_LEN}}" (T.pack (show (BS.length d)))
          . T.replace "{{RESPONSE}}" (escape r)
          . T.replace "{{RESPONSE_LEN}}" (T.pack (show (BS.length r)))
          $ src
  wasm <- watToWasm filled >>= either (assertFailure . T.unpack) pure
  loadPlugin wasm

-- | A description of the command c with the context of the names.
asking :: [Term] -> Term
asking ns = TMap [(TString "commands", TList [TString "c"]), (TString "context", TList ns)]

loaded :: Term -> IO Plugin
loaded t = describing t >>= either (assertFailure . show) pure

decoded :: ByteString -> IO [Term]
decoded b = case deserialiseFromBytes decodeTerm (BL.fromStrict b) of
  Right (rest, TList xs) | BL.null rest -> pure xs
  other -> assertFailure (show other)

vertical, horizontal :: HostContext
vertical = HostContext "vertical" "tcy"
horizontal = HostContext "horizontal" "kanji"

contextTests :: TestTree
contextTests =
  testGroup
    "the context of the book (docs/adr/0121)"
    [ testCase "the field context of the description is the names the plugin asks for" $ do
        p <- loaded (asking [TString "writing-mode", TString "vertical-numbers"])
        pluginContextNames p @?= ["writing-mode", "vertical-numbers"]
        q <- loaded (TMap [(TString "commands", TList [TString "c"])])
        pluginContextNames q @?= [],
      testCase "names the host does not have are UnknownContext, all of them" $ do
        describing (asking [TString "language", TString "writing-mode", TString "medium"]) >>= (@?= Left (UnknownContext ["language", "medium"])) . void
        describePluginError (UnknownContext ["language", "medium"])
          @?= "Golem が渡せない文脈を求めています: language、medium（渡せる文脈: vertical-numbers、writing-mode）",
      testCase "a name twice and a name that is not a string are bad output" $ do
        describing (asking [TString "writing-mode", TString "writing-mode"]) >>= (@?= Left (BadOutput "文脈の名前が重複しています: writing-mode")) . void
        describing (asking [TInt 1]) >>= (@?= Left (BadOutput "名前が文字列ではありません")) . void,
      testCase "a command request has the context before the data, only the names asked for, in their order" $ do
        p <- withPluginData (Map.fromList [("d", "1")]) . withPluginContext vertical <$> loaded (asking [TString "writing-mode", TString "vertical-numbers"])
        req <- either (assertFailure . show) pure (commandRequest p "c" [] [] callSpan) >>= decoded
        drop 5 req
          @?= [ TList [TList [TString "vertical-numbers", TString "tcy"], TList [TString "writing-mode", TString "vertical"]],
                TList [TList [TString "d", TBytes "1"]]
              ]
        q <- withPluginContext vertical <$> loaded (asking [TString "writing-mode"])
        reqQ <- either (assertFailure . show) pure (commandRequest q "c" [] [] callSpan) >>= decoded
        drop 5 reqQ @?= [TList [TList [TString "writing-mode", TString "vertical"]], TList []],
      testCase "the requests of a plugin that asks for nothing are the same in every book" $ do
        p <- loaded (TMap [(TString "commands", TList [TString "c"])])
        let req c = commandRequest (withPluginContext c p) "c" [] [] callSpan
        req vertical @?= req horizontal
        (either (assertFailure . show) pure (req vertical) >>= decoded) >>= (@?= [TList [], TList []]) . drop 5,
      testCase "a filter request is [1, name, document, context, data]" $ do
        p <- withPluginContext horizontal <$> loaded (TMap [(TString "filters", TList [TString "f"]), (TString "context", TList [TString "writing-mode"])])
        let doc = Document (FileId 1) [Block callSpan Nothing (Paragraph Nothing [Text callSpan "a"])]
        filterRequest p "f" doc @?= cbor (TList [TInt 1, TString "f", documentTerm doc, TList [TList [TString "writing-mode", TString "horizontal"]], TList []])
    ]
