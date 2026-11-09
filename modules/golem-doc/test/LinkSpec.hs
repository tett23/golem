-- | Links to external URLs in the IR (docs/adr ADR 0182).
module LinkSpec (tests) where

import Codec.CBOR.Term (Term (..), encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Golem.Doc.Cbor
import Golem.Doc.IR
import Golem.Doc.Url
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
    "links (docs/adr ADR 0182)"
    [ testCase "a link survives the CBOR round trip as [20, span, uri, inlines]" $ do
        let l = Link sp "https://example.com/" [Text sp "例"]
        decodeInlines (encodeInlines [l]) @?= Right [l]
        let bytes = toStrictByteString (encodeTerm (TList [TList [TInt 20, spT, TString "https://example.com/", TList [TList [TInt 0, spT, TString "例"]]]]))
        encodeInlines [l] @?= bytes
        decodeInlines bytes @?= Right [l],
      testCase "a link in the base of a ruby survives the CBOR round trip" $ do
        let r = Ruby sp () [RubySegment [Link sp "https://example.com/" [Text sp "a"]] (Just "え")]
        decodeInlines (encodeInlines [r]) @?= Right [r],
      testCase "the form of a URL (G02125)" $ do
        mapM_
          (\u -> (u, checkUrl u) @?= (u, Just UrlMalformed))
          [ "https://example.com/a b",
            "https://example.com/%zz",
            "https://example.com/%4",
            "https:///a",
            "https://",
            "https:example.com",
            "https://example.com/\t",
            "https://example.com/\x7f",
            "https://exa mple.com/",
            "https://example.com/<a>",
            ""
          ],
      testCase "the scheme of a URL (G02126)" $ do
        mapM_
          (\u -> (u, checkUrl u) @?= (u, Just UrlScheme))
          ["javascript:alert(1)", "mailto:a@example.com", "example.com", "ftp://example.com/", "tel:+81-3-0000-0000"],
      testCase "the host of a URL (G02127)" $ do
        checkUrl "https://例え.jp/" @?= Just UrlHost
        checkUrl "https://xn--r8jz45g.jp/" @?= Nothing,
      testCase "URLs that pass" $
        mapM_
          (\u -> (u, checkUrl u) @?= (u, Nothing))
          [ "https://example.com/",
            "http://example.com",
            "HTTPS://EXAMPLE.COM/",
            "https://ja.wikipedia.org/wiki/組版",
            "https://example.com/a%E7%B5%84?q=組&r=1#節",
            "https://user@example.com:8080/a;b=c/(d)!$'*+,~",
            "https://[::1]/a",
            "https://www.w3.org/TR/jlreq/"
          ],
      testCase "the validation rejects a link with a URL that fails the checks" $ do
        validateInlines size [] [Link sp "https://example.com/" [Text sp "a"]] @?= []
        validateInlines size [] [Link sp "javascript:alert(1)" [Text sp "a"]] @?= ["リンクにできる URL は http と https だけです: javascript:alert(1)"]
        validateInlines size [] [Link sp "https:///a" []] @?= ["URL の形が誤っています: https:///a"]
        validateInlines size [] [Link sp "https://例え.jp/" []] @?= ["URL のホストは ASCII で書きます: https://例え.jp/"],
      testCase "the validation rejects the elements that become links inside a link" $ do
        let link = Link sp "https://example.com/"
            msg e = "リンクの中にリンクになる要素は置けません: " <> e
        validateInlines size [] [link [link []]] @?= [msg "link"]
        validateInlines size [] [link [CharStyle sp "strong" [Ref sp RefNumber "a"]]] @?= [msg "ref-number"]
        validateInlines size [] [link [Note sp 1 (noteBody sp [])]] @?= [msg "note"]
        validateInlines size [] [link [Sidenote sp 1 (noteBody sp [])]] @?= [msg "sidenote"]
        validateInlines size [] [link [Cite sp "k"]] @?= [msg "cite"]
        validateInlines size [] [link [Ruby sp () [RubySegment [Text sp "a"] (Just "b")], IndexMark sp (IndexEntry ["a"] ["a"]), CharStyle sp "url" [Text sp "a"]]] @?= [],
      testCase "a link in a note, and a line break inside a link" $ do
        let link = Link sp "https://example.com/"
        validateInlines size [] [Note sp 1 (noteBody sp [link [Text sp "a"]])] @?= []
        validateInlines size [] [link [Text sp "a", LineBreak sp, Text sp "b"]] @?= ["改行は段落の最上位のインラインの間にだけ置けます"],
      testCase "a copy of a title keeps the text of a link without the link" $
        withoutAnchors [Text sp "a", Link sp "https://example.com/" [Text sp "b", IndexMark sp (IndexEntry ["b"] ["b"])]] @?= ([Text sp "a", Text sp "b"] :: [Inline])
    ]
