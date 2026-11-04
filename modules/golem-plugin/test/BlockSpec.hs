{- | Block commands of plugins (docs/adr/0122): the field blocks of the
description, the request of a block command, and the blocks a block
command may put out.
-}
module BlockSpec (blockTests) where

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
import Golem.Doc.Cbor (blocksTerm, inlinesTerm, spanT)
import Golem.Doc.IR hiding (abiVersion)
import Golem.Eval.Value (PluginArg (..), Value (..))
import Golem.Plugin
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

cbor :: Term -> ByteString
cbor = toStrictByteString . encodeTerm

callSpan :: SrcSpan
callSpan = mkSpan (FileId 1) 10 20

-- | fixed.wat with a description and a response.
fixed :: Term -> Term -> IO (Either PluginError Plugin)
fixed describe response = do
  src <- TIO.readFile "test/plugins/fixed.wat"
  let d = cbor describe
      r = cbor response
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

described :: [Text] -> Term
described blocks = TMap [(TString "commands", TList [TString "shout"]), (TString "blocks", TList (map TString blocks))]

-- | A plugin with the block command grid that answers with these blocks.
answering :: [Block] -> IO Plugin
answering bs = fixed (described ["grid"]) (TList [blocksTerm bs, TList []]) >>= either (assertFailure . show) pure

echo :: IO Plugin
echo = do
  src <- TIO.readFile "test/plugins/echo.wat"
  wasm <- watToWasm src >>= either (assertFailure . T.unpack) pure
  loadPlugin wasm >>= either (assertFailure . show) pure

decoded :: ByteString -> IO Term
decoded b = case deserialiseFromBytes decodeTerm (BL.fromStrict b) of
  Right (rest, t) | BL.null rest -> pure t
  other -> assertFailure (show other)

text :: Text -> Inline
text = Text callSpan

table :: Block
table = Block callSpan Nothing (Table [AlignDefault, AlignRight] [[text "a"], [text "b"]] [[[text "1"], [text "2"]]])

bodySpan :: SrcSpan
bodySpan = mkSpan (FileId 1) 21 30

badOutput :: Text -> Either PluginError a -> Assertion
badOutput m = \case
  Left (BadOutput m') -> m' @?= m
  Left e -> assertFailure (show e)
  Right _ -> assertFailure "accepted"

blockTests :: TestTree
blockTests =
  testGroup
    "block commands of plugins (docs/adr/0122)"
    [ testCase "the field blocks of the description is the block commands" $ do
        p <- fixed (described ["grid", "tsv-table"]) (TList [TList [], TList []]) >>= either (assertFailure . show) pure
        pluginBlocks p @?= ["grid", "tsv-table"]
        pluginCommands p @?= ["shout"],
      testCase "a description without blocks provides no block command" $ do
        p <- fixed (TMap [(TString "commands", TList [TString "shout"])]) (TList [TList [], TList []]) >>= either (assertFailure . show) pure
        pluginBlocks p @?= [],
      testCase "a block command is a lowercase letter, then lowercase letters, digits and -" $
        mapM_
          (\n -> fixed (described [n]) (TList [TList [], TList []]) >>= badOutput ("ブロックコマンドの名前が不正です: " <> n) . void)
          ["Grid", "", "1a", "a_b", "a b"],
      testCase "a block command named twice is bad output" $
        fixed (described ["grid", "grid"]) (TList [TList [], TList []]) >>= badOutput "ブロックコマンドの名前が重複しています: grid" . void,
      testCase "a block command with the name of a built-in block command, attribute or setting is bad output" $
        mapM_
          (\n -> fixed (described [n]) (TList [TList [], TList []]) >>= badOutput ("組み込みのブロックコマンドの名前です: " <> n) . void)
          ["table", "figure", "label", "manifest", "style-def", "set", "import"],
      testCase "the request of a block command is [2, name, args, body, span, context, data]" $ do
        p <- echo
        let body = [Block bodySpan Nothing (Paragraph Nothing [Text bodySpan "x"])]
        req <- either (assertFailure . show) pure (blockCommandRequest p "grid" [PluginPositional (VString "sales"), PluginKeyword "align" (VString "left")] body callSpan)
        req
          @?= cbor
            ( TList
                [ TInt 2,
                  TString "grid",
                  TList [TList [TInt 0, TString "sales"], TList [TInt 1, TString "align", TString "left"]],
                  blocksTerm body,
                  spanT callSpan,
                  TList [],
                  TList []
                ]
            ),
      testCase "a table at the call is the output" $ do
        p <- answering [table]
        callBlockCommand p "grid" [] [] callSpan @?= Right ([table], []),
      testCase "a paragraph and a list are output" $ do
        let para = Block callSpan Nothing (Paragraph Nothing [text "p"])
            list = Block callSpan Nothing (BulletList [ListItem Nothing [para]])
        p <- answering [para, list]
        callBlockCommand p "grid" [] [] callSpan @?= Right ([para, list], []),
      testCase "a heading is no output of a block command" $ do
        p <- answering [Block callSpan Nothing (Heading 1 noHeadingAttrs [text "h"])]
        badOutput "ブロックコマンドが返せないブロックです: 見出し" (callBlockCommand p "grid" [] [] callSpan),
      testCase "blank lines in a list item are no output of a block command" $ do
        let item = Block callSpan Nothing (BlankLines 1)
        p <- answering [Block callSpan Nothing (BulletList [ListItem Nothing [item]])]
        badOutput "ブロックコマンドが返せないブロックです: 行アキ" (callBlockCommand p "grid" [] [] callSpan),
      testCase "a label is no output of a block command" $ do
        p <- answering [table {blockLabel = Just "t"}]
        badOutput "ブロックコマンドの出力はラベルを持てません" (callBlockCommand p "grid" [] [] callSpan),
      testCase "a span not in the request is bad output" $ do
        p <- answering [table {blockSpan = mkSpan (FileId 2) 0 1}]
        badOutput "要求にないソース位置を含んでいます" (callBlockCommand p "grid" [] [] callSpan),
      testCase "a table whose rows do not match the header is bad output" $ do
        p <- answering [Block callSpan Nothing (Table [AlignDefault] [[text "a"]] [[[text "1"], [text "2"]]])]
        badOutput "表のセルの数が一致しません" (callBlockCommand p "grid" [] [] callSpan),
      testCase "the data reach the plugin at the end of the request" $ do
        p <- withPluginData (Map.fromList [("sales", "a\tb\n")]) <$> echo
        req <- either (assertFailure . show) pure (blockCommandRequest p "grid" [] [] callSpan)
        t <- decoded req
        case t of
          TList xs -> last xs @?= TList [TList [TString "sales", TBytes "a\tb\n"]]
          other -> assertFailure (show other),
      testCase "a block of the body passes as it came, even a heading" $ do
        let h = Block bodySpan (Just "h") (Heading 2 noHeadingAttrs [Text bodySpan "h"])
        p <- answering [h, table]
        callBlockCommand p "grid" [] [h] callSpan @?= Right ([h, table], []),
      testCase "inlines are no output of a block command" $ do
        p <- fixed (described ["grid"]) (TList [inlinesTerm [text "x"], TList []]) >>= either (assertFailure . show) pure
        case callBlockCommand p "grid" [] [] callSpan of
          Left (BadOutput _) -> pure ()
          other -> assertFailure (show other)
    ]
