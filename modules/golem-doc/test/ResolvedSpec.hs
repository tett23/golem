-- | [ref-number] and [ref-title] after the assembly in the IR (docs/adr/0215).
module ResolvedSpec (tests) where

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

tests :: TestTree
tests =
  testGroup
    "resolved references (docs/adr/0215)"
    [ testCase "a resolved reference survives the CBOR round trip as [22, span, ref-kind, label, inlines]" $ do
        let r = Resolved sp RefTitle "design" [Text sp "設計", Ruby sp () [RubySegment [Text sp "組版"] (Just "くみはん")]]
        decodeInlines (encodeInlines [r]) @?= Right [r]
        let n = Resolved sp RefNumber "h" [Number sp 2 Nothing]
            bytes = toStrictByteString (encodeTerm (TList [TList [TInt 22, spT, TInt 0, TString "h", TList [TList [TInt 9, spT, TInt 2, TNull]]]]))
        encodeInlines [n] @?= bytes
        decodeInlines bytes @?= Right [n]
        -- the kind of a reference is 0..2
        decodeInlines (toStrictByteString (encodeTerm (TList [TList [TInt 22, spT, TInt 3, TString "h", TList []]]))) @?= Left "スキーマに合いません: 列挙の範囲",
      testCase "a plugin does not put out a resolved reference, which only the assembly makes" $ do
        validateInlines size [] [Resolved sp RefNumber "h" [Text sp "1"]] @?= ["解決した参照は文書の組み立てだけが作ります"]
        validateInlines size [] [CharStyle sp "strong" [Resolved sp RefTitle "h" [Text sp "題"]]] @?= ["解決した参照は文書の組み立てだけが作ります"],
      testCase "the IR functions go inside a resolved reference as inside a link" $ do
        let mark = IndexMark sp (IndexEntry ["組"] ["くみ"])
        withoutAnchors [Resolved sp RefTitle "h" [Text sp "題", mark] :: Inline] @?= [Resolved sp RefTitle "h" [Text sp "題"]]
        noRuby (Resolved sp RefTitle "h" [Text sp "題"]) @?= Just (Resolved sp RefTitle "h" [Text sp "題"])
        noRuby (Resolved sp RefTitle "h" [Ruby sp () [RubySegment [Text sp "組"] (Just "く")]]) @?= Nothing
    ]
