-- | Language spans and the language of blocks in the IR (docs/adr ADR 0187).
module LangSpec (tests) where

import Codec.CBOR.Term (Term (..), encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
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

size :: FileId -> Maybe Int
size (FileId 0) = Just 10
size _ = Nothing

para :: [Inline] -> BlockBody
para = Paragraph Nothing

tests :: TestTree
tests =
  testGroup
    "language spans and the language of blocks (docs/adr ADR 0187)"
    [ testCase "a language span survives the CBOR round trip as [21, span, lang, inlines]" $ do
        let l = Lang sp "en-US" [Text sp "a"]
        decodeInlines (encodeInlines [l]) @?= Right [l]
        let bytes = toStrictByteString (encodeTerm (TList [TList [TInt 21, spT, TString "en-US", TList [TList [TInt 0, spT, TString "a"]]]]))
        encodeInlines [l] @?= bytes
        decodeInlines bytes @?= Right [l],
      testCase "nested spans and a span in the base of a ruby survive the CBOR round trip" $ do
        let n = Lang sp "en" [Text sp "a", Lang sp "fr" [Text sp "b"], Text sp "c"]
            r = Ruby sp () [RubySegment [Lang sp "ja" [Text sp "東"]] (Just "ひがし")]
        decodeInlines (encodeInlines [n, r]) @?= Right [n, r],
      testCase "the language of a block survives the CBOR round trip as [span, label, lang, body]" $ do
        let d = Document (FileId 0) [Block sp Nothing (Just "en") (para [Text sp "a"]), Block sp (Just "l") Nothing (para [])]
        decodeDocument (encodeDocument d) @?= Right d
        let bytes = toStrictByteString (encodeTerm (TList [TInt abiVersion, TInt 0, TList [TList [spT, TNull, TString "de-CH-1996", TList [TInt 10, TNull, TList []]]]]))
        decodeDocument bytes @?= Right (Document (FileId 0) [Block sp Nothing (Just "de-CH-1996") (Paragraph Nothing [])])
        encodeDocument (Document (FileId 0) [Block sp Nothing (Just "de-CH-1996") (Paragraph Nothing [])]) @?= bytes,
      testCase "a block of three fields is not of the schema" $
        decodeDocument (toStrictByteString (encodeTerm (TList [TInt abiVersion, TInt 0, TList [TList [spT, TNull, TList [TInt 10, TNull, TList []]]]])))
          @?= Left "スキーマに合いません: ブロック",
      testCase "the validation rejects a language span whose tag is not of the form of BCP 47" $ do
        validateInlines size [] [Lang sp "zh-Hant-TW" [Text sp "a"]] @?= []
        validateInlines size [] [Lang sp "e_n" [Text sp "a"]] @?= ["言語のタグの形が誤っています: e_n"]
        validateInlines size [] [CharStyle sp "s" [Lang sp "en-" []]] @?= ["言語のタグの形が誤っています: en-"]
        langErrors [Note sp 1 (noteBody sp [Lang sp "123" []])] @?= ["言語のタグの形が誤っています: 123"],
      testCase "the validation rejects the language of a block that is not of the form of BCP 47" $ do
        let doc = Document (FileId 0)
            b l = Block sp Nothing l (Paragraph Nothing [Text sp "a"])
        validateDocument size [] (doc [b (Just "en"), b Nothing]) @?= []
        validateDocument size [] (doc [b (Just "")]) @?= ["言語のタグの形が誤っています: "]
        validateBlocks size [] [Block sp Nothing Nothing (BulletList [ListItem Nothing [b (Just "e_n")]])] @?= ["言語のタグの形が誤っています: e_n"],
      testCase "a line break inside a language span is not at the top of a paragraph" $
        validateInlines size [] [Lang sp "en" [Text sp "a", LineBreak sp, Text sp "b"]] @?= ["改行は段落の最上位のインラインの間にだけ置けます"],
      testCase "a copy of a title keeps the language span, without the anchors inside it" $
        withoutAnchors [Lang sp "en" [Text sp "a", IndexMark sp (IndexEntry ["a"] ["a"]), Link sp "https://example.com/" [Text sp "b"]]]
          @?= ([Lang sp "en" [Text sp "a", Text sp "b"]] :: [Inline])
    ]
