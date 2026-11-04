{- | The data a project passes to a plugin (docs/adr/0105): the names a
plugin takes, from the fourth list of its description, and the data at
the end of every request.
-}
module DataSpec (dataTests, describeTests) where

import Codec.CBOR.Read (deserialiseFromBytes)
import Codec.CBOR.Term (Term (..), decodeTerm, encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Control.Monad (void)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Doc.Assemble (ChannelDecl (..))
import Golem.Doc.Cbor (documentTerm)
import Golem.Doc.IR hiding (abiVersion)
import Golem.Plugin
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

cbor :: Term -> ByteString
cbor = toStrictByteString . encodeTerm

callSpan :: SrcSpan
callSpan = mkSpan (FileId 1) 10 20

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

withDataNames :: [Text] -> Term
withDataNames ns = TMap [(TString "commands", TList [TString "shout"]), (TString "data", TList (map TString ns))]

echo :: IO Plugin
echo = do
  src <- TIO.readFile "test/plugins/echo.wat"
  wasm <- watToWasm src >>= either (assertFailure . T.unpack) pure
  loadPlugin wasm >>= either (assertFailure . show) pure

decoded :: ByteString -> IO Term
decoded b = case deserialiseFromBytes decodeTerm (BL.fromStrict b) of
  Right (rest, t) | BL.null rest -> pure t
  other -> assertFailure (show other)

-- | The last element of a request as echo.wat sends it back.
lastOf :: Plugin -> ByteString -> IO Term
lastOf p req = do
  out <- either (assertFailure . show) pure (invokeRaw p req)
  t <- decoded out
  case t of
    TList xs@(_ : _) -> pure (last xs)
    other -> assertFailure (show other)

dataTests :: TestTree
dataTests =
  testGroup
    "the data of a plugin (docs/adr/0105)"
    [ testCase "the fourth list of the description is the names of the data the plugin takes" $ do
        p <- describing (withDataNames ["table", "dict"]) >>= either (assertFailure . show) pure
        pluginDataNames p @?= ["table", "dict"],
      testCase "a description without data takes no data" $ do
        p <- describing (TMap [(TString "commands", TList [TString "shout"])]) >>= either (assertFailure . show) pure
        pluginDataNames p @?= [],
      testCase "a name of data that is not a lowercase name is bad output" $
        mapM_
          (\n -> describing (withDataNames [n]) >>= (@?= Left (BadOutput ("データの名前が不正です: " <> n))) . void)
          ["Dict", "", "1a", "a_b"],
      testCase "a name of data twice is bad output" $
        describing (withDataNames ["dict", "dict"]) >>= (@?= Left (BadOutput "データの名前が重複しています: dict")) . void,
      -- docs/adr/0119
      testCase "a plugin that declares * takes data of any well-formed name" $ do
        p <- describing (withDataNames ["*"]) >>= either (assertFailure . show) pure
        map (takesData p) ["sales", "costs", "a-1", "Sales", "1a", "", "*"] @?= [True, True, True, False, False, False, False],
      testCase "a plugin that declares names takes those names only" $ do
        p <- describing (withDataNames ["table"]) >>= either (assertFailure . show) pure
        map (takesData p) ["table", "sales"] @?= [True, False]
        q <- describing (TMap [(TString "commands", TList [TString "shout"])]) >>= either (assertFailure . show) pure
        takesData q "table" @?= False,
      testCase "* with another name is a bad name of data" $
        mapM_
          (\ns -> describing (withDataNames ns) >>= (@?= Left (BadOutput "データの名前が不正です: *")) . void)
          [["*", "table"], ["table", "*"], ["*", "*"]],
      testCase "data of any name is at the end of a command request" $ do
        p <- withPluginData (Map.fromList [("sales", "1"), ("costs", "2")]) <$> echo
        req <- either (assertFailure . show) pure (commandRequest p "echo" [] [] callSpan)
        lastOf p req >>= (@?= TList [TList [TString "costs", TBytes "2"], TList [TString "sales", TBytes "1"]]),
      testCase "a command request ends with the data, in the order of the names" $ do
        p <- withPluginData (Map.fromList [("b", "2"), ("a", "\0\1")]) <$> echo
        req <- either (assertFailure . show) pure (commandRequest p "echo" [] [] callSpan)
        end <- lastOf p req
        end @?= TList [TList [TString "a", TBytes "\0\1"], TList [TString "b", TBytes "2"]],
      testCase "without data, a command request ends with an empty list" $ do
        p <- echo
        req <- either (assertFailure . show) pure (commandRequest p "echo" [] [] callSpan)
        lastOf p req >>= (@?= TList [])
        t <- decoded req
        case t of
          TList xs -> length xs @?= 7
          other -> assertFailure (show other),
      testCase "a filter request is the name, the document, the context and the data" $ do
        p <- withPluginData (Map.fromList [("dict", "x")]) <$> echo
        let doc = Document (FileId 1) [Block callSpan Nothing (Paragraph Nothing [Text callSpan "a"])]
        filterRequest p "f" doc @?= cbor (TList [TInt 1, TString "f", documentTerm doc, TList [], TList [TList [TString "dict", TBytes "x"]]])
    ]

-- | What a plugin declares, as a host reads it.
declared :: Plugin -> ([Text], [Text], [Text], [Text])
declared p = (pluginCommands p, pluginFilters p, map channelName (pluginChannels p), pluginDataNames p)

-- | The fields of golem_describe have names (docs/adr/0107).
describeTests :: TestTree
describeTests =
  testGroup
    "the named fields of golem_describe (docs/adr/0107)"
    [ testCase "an empty map declares nothing" $ do
        p <- describing (TMap []) >>= either (assertFailure . show) pure
        declared p @?= ([], [], [], []),
      testCase "the order of the fields does not matter" $ do
        let fields =
              [ (TString "commands", TList [TString "c"]),
                (TString "filters", TList [TString "f"]),
                (TString "channels", TList [TList [TString "glossary", TInt 1, TBool False]]),
                (TString "data", TList [TString "table"])
              ]
        a <- describing (TMap fields) >>= either (assertFailure . show) pure
        b <- describing (TMap (reverse fields)) >>= either (assertFailure . show) pure
        declared a @?= (["c"], ["f"], ["glossary"], ["table"])
        declared b @?= declared a,
      testCase "an unknown field is bad output" $
        describing (TMap [(TString "commands", TList []), (TString "macros", TList [])]) >>= (@?= Left (BadOutput "golem_describe に未知の欄があります: macros")) . void,
      testCase "a field twice is bad output" $
        describing (TMap [(TString "commands", TList [TString "a"]), (TString "commands", TList [TString "b"])]) >>= (@?= Left (BadOutput "golem_describe の欄が重複しています: commands")) . void,
      testCase "a key that is not a text string is bad output" $
        describing (TMap [(TInt 0, TList [])]) >>= (@?= Left (BadOutput "golem_describe の形が不正です")) . void,
      testCase "a field that is not an array is bad output" $
        describing (TMap [(TString "commands", TString "a")]) >>= (@?= Left (BadOutput "golem_describe の欄の形が不正です: commands")) . void,
      testCase "a map of indefinite length is bad output" $
        describing (TMapI [(TString "commands", TList [])]) >>= (@?= Left (BadOutput "golem_describe の形が不正です")) . void,
      testCase "the old arrays of lists are bad output" $
        mapM_
          (\t -> describing t >>= (@?= Left (BadOutput "golem_describe の形が不正です")) . void)
          [ TList [TList [TString "shout"], TList []],
            TList [TList [TString "shout"], TList [], TList [], TList []],
            TList [TList [TString "shout"], TList [], TList [], TList [], TList []]
          ]
    ]
