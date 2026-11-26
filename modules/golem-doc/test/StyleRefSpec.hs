-- | The paragraph style of a paragraph with the keys of @style (root ADR 0467).
module StyleRefSpec (tests) where

import Codec.CBOR.Term (Term (..), encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Data.ByteString (ByteString)
import Data.Map.Strict qualified as Map
import Golem.Doc.Cbor
import Golem.Doc.IR
import Golem.Doc.Validate
import Golem.Syntax.Span
import Test.Tasty
import Test.Tasty.HUnit

sp :: SrcSpan
sp = SrcSpan (FileId 0) 0 1

spT :: Term
spT = TList [TInt 0, TInt 0, TInt 1]

-- | A document of one paragraph in a style.
docOf :: Maybe StyleRef -> Document
docOf st = Document (FileId 0) [Block sp Nothing Nothing (Paragraph st [Text sp "x"])]

-- | The bytes of a document of one paragraph with the style written as a term.
bytesOf :: Term -> ByteString
bytesOf st = toStrictByteString (encodeTerm (TList [TInt abiVersion, TInt 0, TList [TList [spT, TNull, TNull, TList [TInt 10, st, TList [TList [TInt 0, spT, TString "x"]]]]]]))

keyed :: StyleRef
keyed = StyleRef "quote" (Map.fromList [("line-pitch", StyleString "16pt"), ("indent", StyleWord "2zw")])

tests :: TestTree
tests =
  testGroup
    "the keys of a paragraph style (root ADR 0467)"
    [ testCase "root ADR 0467 I1: a style without keys is written as its name, as before" $
        decodeDocument (bytesOf (TString "quote")) @?= Right (docOf (Just "quote")),
      testCase "root ADR 0467 I2: a style with keys survives the CBOR round trip, a paragraph and the cells of a table" $ do
        decodeDocument (encodeDocument (docOf (Just keyed))) @?= Right (docOf (Just keyed))
        let t = (plainTable [AlignDefault] [[Text sp "a"]] []) {tableStyle = Just keyed}
            doc = Document (FileId 0) [Block sp Nothing Nothing (TableBlock t)]
        decodeDocument (encodeDocument doc) @?= Right doc,
      testCase "root ADR 0467 I2: the keys are written in the order of their names, a word as 0 and a string as 1" $
        decodeDocument (bytesOf (TList [TString "quote", TList [TList [TString "indent", TList [TInt 0, TString "2zw"]], TList [TString "line-pitch", TList [TInt 1, TString "16pt"]]]])) @?= Right (docOf (Just keyed)),
      testCase "root ADR 0467: keys out of order, written twice or none are rejected" $ do
        let key k = TList [TString k, TList [TInt 1, TString "v"]]
        decodeDocument (bytesOf (TList [TString "quote", TList [key "line-pitch", key "indent"]])) @?= Left "スキーマに合いません: 段落スタイルのキーの順"
        decodeDocument (bytesOf (TList [TString "quote", TList [key "indent", key "indent"]])) @?= Left "スキーマに合いません: 段落スタイルのキーの順"
        decodeDocument (bytesOf (TList [TString "quote", TList []])) @?= Left "スキーマに合いません: 段落スタイル",
      testCase "root ADR 0467: based-on is no key of a paragraph style" $
        validateDocument (const (Just 10)) [] (docOf (Just (StyleRef "quote" (Map.singleton "based-on" (StyleWord "body"))))) @?= ["段落スタイルのキーに based-on は書けません"],
      testCase "root ADR 0467 I5: two styles are equal when the names and the tables are" $ do
        StyleRef "quote" (Map.fromList [("a", StyleWord "1"), ("b", StyleWord "2")]) @?= StyleRef "quote" (Map.fromList [("b", StyleWord "2"), ("a", StyleWord "1")])
        assertBool "a word and a string differ" (StyleRef "q" (Map.singleton "a" (StyleWord "1")) /= StyleRef "q" (Map.singleton "a" (StyleString "1")))
        assertBool "with keys and without differ" (keyed /= "quote")
    ]
