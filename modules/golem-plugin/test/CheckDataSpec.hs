{- | The check of a plugin's data at load (docs/adr/0120): the optional
export golem_check_data, its request [data] and its response
[* data-diagnostic].
-}
module CheckDataSpec (checkDataTests) where

import Codec.CBOR.Term (Term (..), encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Plugin
import Golem.Syntax (Severity (..))
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

cbor :: Term -> ByteString
cbor = toStrictByteString . encodeTerm

{- | check-data.wat (or fixed.wat, without the export) with a description
that declares the command shout and the data table, the response of
golem_invoke, and the response of golem_check_data.
-}
checking :: FilePath -> ByteString -> ByteString -> IO (Either PluginError Plugin)
checking file response check = do
  src <- TIO.readFile ("test/plugins/" <> file)
  let d = cbor (TMap [(TString "commands", TList [TString "shout"]), (TString "data", TList [TString "table"])])
      escape = T.pack . concatMap (printf "\\%02x") . BS.unpack
      filled =
        T.replace "{{ABI}}" "8"
          . T.replace "{{DESCRIBE}}" (escape d)
          . T.replace "{{DESCRIBE_LEN}}" (T.pack (show (BS.length d)))
          . T.replace "{{RESPONSE}}" (escape response)
          . T.replace "{{RESPONSE_LEN}}" (T.pack (show (BS.length response)))
          . T.replace "{{CHECK}}" (escape check)
          . T.replace "{{CHECK_LEN}}" (T.pack (show (BS.length check)))
          $ src
  wasm <- watToWasm filled >>= either (assertFailure . T.unpack) pure
  loadPlugin wasm

-- | A plugin of check-data.wat whose golem_check_data answers with the term.
answering :: Term -> IO Plugin
answering t = checking "check-data.wat" (cbor (TList [TList [], TList []])) (cbor t) >>= either (assertFailure . show) pure

checkDataTests :: TestTree
checkDataTests =
  testGroup
    "golem_check_data (docs/adr/0120)"
    [ testCase "a plugin with golem_check_data checks its data; one without does not" $ do
        p <- answering (TList [])
        pluginChecksData p @?= True
        q <- checking "fixed.wat" (cbor (TList [TList [], TList []])) "" >>= either (assertFailure . show) pure
        pluginChecksData q @?= False
        checkData q >>= (@?= Right []),
      testCase "the request is [data]" $ do
        p <- withPluginData (Map.fromList [("table", "a\tb\n")]) <$> answering (TList [])
        checkDataRequest p @?= cbor (TList [TList [TList [TString "table", TBytes "a\tb\n"]]])
        q <- answering (TList [])
        checkDataRequest q @?= cbor (TList [TList []]),
      testCase "the response is the diagnostics of the data: code, severity, name, line or null, message" $ do
        p <- answering (TList [TList [TString "tsv-columns", TInt 0, TString "table", TInt 7, TString "欄の数が違います"], TList [TString "tsv-empty", TInt 1, TString "table", TNull, TString "空です"]])
        checkData p
          >>= (@?= Right [DataDiagnostic "tsv-columns" Error "table" (Just 7) "欄の数が違います", DataDiagnostic "tsv-empty" Warning "table" Nothing "空です"]),
      testCase "a code of the wrong form is bad output (docs/adr/0108)" $
        mapM_
          ( \c -> do
              p <- answering (TList [TList [TString c, TInt 0, TString "table", TNull, TString "m"]])
              checkData p >>= (@?= Left (BadOutput ("診断のコードの形が不正です: " <> c)))
          )
          -- a code starts with a lowercase letter (docs/adr/0139)
          ["Lookup/x", "", "a_b", "404", "-x"],
      testCase "a wrong severity, line or shape is bad output" $ do
        let bad t m = answering t >>= checkData >>= (@?= Left (BadOutput m))
        bad (TList [TList [TString "x", TInt 2, TString "table", TNull, TString "m"]]) "診断の重大度が不正です"
        bad (TList [TList [TString "x", TInt 0, TString "table", TInt 0, TString "m"]]) "データの診断の行が不正です"
        bad (TList [TList [TString "x", TInt 0, TString "table", TInt (-1), TString "m"]]) "データの診断の行が不正です"
        bad (TList [TList [TString "x", TInt 0, TString "table", TString "m"]]) "データの診断の形が不正です"
        bad (TMap []) "データの検査の応答の形が不正です"
    ]
