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
import Golem.Syntax.Sha256 (sha256)
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
answering bs = drawing bs []

-- | A plugin with the block command grid that answers with these blocks and images (docs/adr/0123).
drawing :: [Block] -> [(Text, Text, ByteString)] -> IO Plugin
drawing bs imgs =
  fixed (described ["grid"]) (TList [TList [blocksTerm bs, TList [TList [TString n, TString f, TBytes b] | (n, f, b) <- imgs]], TList []])
    >>= either (assertFailure . show) pure

-- | A figure of the call whose image is src.
figureOf :: Text -> Block
figureOf src = Block callSpan Nothing (FigureBlock (Figure src Nothing "棒グラフ" Nothing Nothing [] Nothing False))

svgBytes :: ByteString
svgBytes = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"5\" height=\"5\"/></svg>"

-- | The SHA-256 of svgBytes in hexadecimal, as the host names the image.
svgName :: Text
svgName = "golem-plugin-image://" <> T.pack (concatMap (printf "%02x") (BS.unpack (sha256 svgBytes))) <> ".svg"

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
        callBlockCommand p "grid" [] [] callSpan @?= Right ([table], Map.empty, []),
      -- docs/adr/0123
      testCase "a figure of an image of the response is named by the SHA-256 of the image" $ do
        p <- drawing [figureOf "plugin:chart"] [("chart", "svg", svgBytes)]
        callBlockCommand p "grid" [] [] callSpan @?= Right ([figureOf svgName], Map.fromList [(svgName, svgBytes)], []),
      testCase "the same bytes under two names are one image" $ do
        p <- drawing [figureOf "plugin:a", figureOf "plugin:b"] [("a", "svg", svgBytes), ("b", "svg", svgBytes)]
        callBlockCommand p "grid" [] [] callSpan @?= Right ([figureOf svgName, figureOf svgName], Map.fromList [(svgName, svgBytes)], []),
      testCase "png and jpeg images are named with .png and .jpg" $ do
        p <- drawing [figureOf "plugin:a", figureOf "plugin:b"] [("a", "png", "P"), ("b", "jpeg", "J")]
        let named ext b = "golem-plugin-image://" <> T.pack (concatMap (printf "%02x") (BS.unpack (sha256 b))) <> ext
        fmap (\(_, imgs, _) -> Map.keys imgs) (callBlockCommand p "grid" [] [] callSpan) @?= Right (Map.keys (Map.fromList [(named ".png" "P", ()), (named ".jpg" "J", ())])),
      testCase "the images of a figure that are bad output" $ do
        let bad bs imgs m = drawing bs imgs >>= \p -> badOutput m (callBlockCommand p "grid" [] [] callSpan)
        bad [figureOf "plugin:nope"] [] "応答にない画像です: plugin:nope"
        bad [figureOf "images/a.png"] [] "プラグインの図版は plugin:<名前> で画像を指します: images/a.png"
        bad [] [("chart", "svg", svgBytes)] "どの図版も使っていない画像があります: chart"
        bad [figureOf "plugin:chart"] [("chart", "pdf", svgBytes)] "画像の形式は svg、png、jpeg のどれかです: pdf"
        bad [figureOf "plugin:Chart"] [("Chart", "svg", svgBytes)] "画像の名前が不正です: Chart"
        bad [figureOf "plugin:chart"] [("chart", "svg", svgBytes), ("chart", "svg", svgBytes)] "画像の名前が重複しています: chart"
        let withWeb = Block callSpan Nothing (FigureBlock (Figure "plugin:chart" (Just "plugin:chart") "x" Nothing Nothing [] Nothing False))
        bad [withWeb] [("chart", "svg", svgBytes)] "プラグインの図版は web を持てません"
        bad [Block callSpan Nothing (BulletList [ListItem Nothing [figureOf "plugin:chart"]])] [("chart", "svg", svgBytes)] "図版は出力の最上位にだけ置けます",
      testCase "images over 64 MiB together are bad output" $ do
        src <- TIO.readFile "test/plugins/big-image.wat"
        wasm <- watToWasm src >>= either (assertFailure . T.unpack) pure
        p <- loadPlugin wasm >>= either (assertFailure . show) pure
        badOutput "画像の大きさの合計が上限（67108864 バイト）を超えています" (callBlockCommand p "grid" [] [] callSpan),
      testCase "the blocks without the list of images are bad output" $ do
        p <- fixed (described ["grid"]) (TList [blocksTerm [table], TList []]) >>= either (assertFailure . show) pure
        case callBlockCommand p "grid" [] [] callSpan of
          Left (BadOutput _) -> pure ()
          other -> assertFailure (show other),
      testCase "a paragraph and a list are output" $ do
        let para = Block callSpan Nothing (Paragraph Nothing [text "p"])
            list = Block callSpan Nothing (BulletList [ListItem Nothing [para]])
        p <- answering [para, list]
        callBlockCommand p "grid" [] [] callSpan @?= Right ([para, list], Map.empty, []),
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
        callBlockCommand p "grid" [] [h] callSpan @?= Right ([h, table], Map.empty, []),
      testCase "inlines are no output of a block command" $ do
        p <- fixed (described ["grid"]) (TList [TList [inlinesTerm [text "x"], TList []], TList []]) >>= either (assertFailure . show) pure
        case callBlockCommand p "grid" [] [] callSpan of
          Left (BadOutput _) -> pure ()
          other -> assertFailure (show other)
    ]
