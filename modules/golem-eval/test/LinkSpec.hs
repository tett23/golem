-- | [link] (docs/adr ADR 0182).
module LinkSpec (tests) where

import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

ctx :: EvalContext
ctx = baseCtx {ctxCharStyles = Set.fromList ["term", "url"], ctxCiteKeys = Set.fromList ["knuth1981"]}

-- | The inlines of the paragraphs, without their spans.
inlinesOf :: Text -> [[Inline]]
inlinesOf src = [map unspan is | Paragraph _ is <- resultBodies (evalResult ctx src)]

unspan :: Inline -> Inline
unspan = \case
  Text _ t -> Text z t
  CharStyle _ c xs -> CharStyle z c (map unspan xs)
  Link _ u xs -> Link z u (map unspan xs)
  x -> x

z :: SrcSpan
z = mkSpan (FileId 0) 0 0

-- | The code and the message of each diagnostic.
msgs :: Text -> [(Text, Text)]
msgs src = [(c, m) | (c, m, _, _) <- map diagSite (fst (evalSource ctx src))]

wrongArgs :: (Text, Text)
wrongArgs = ("G02124", "link の引数が誤っています")

tests :: TestTree
tests =
  testGroup
    "[link] (docs/adr ADR 0182)"
    [ testCase "a URL and the text of the link" $ do
        inlinesOf "[link \"https://example.com/\": 例]\n" @?= [[Link z "https://example.com/" [Text z "例"]]]
        msgs "[link \"https://example.com/\": 例]\n" @?= [],
      testCase "without a prose slot, the URL in the character style url" $
        inlinesOf "[link \"https://example.com/\"]\n" @?= [[Link z "https://example.com/" [CharStyle z "url" [Text z "https://example.com/"]]]],
      testCase "a string of an expression" $ do
        inlinesOf "[link [= \"https://example.com/\"]: 例]\n" @?= [[Link z "https://example.com/" [Text z "例"]]]
        inlinesOf "@set site = \"https://example.com/\"\n\n[link [= site]: 例]\n" @?= [[Link z "https://example.com/" [Text z "例"]]],
      testCase "G02124: a URL written without quotes tells to quote it" $ do
        msgs "[link https://example.com/: 例]\n" @?= [("G02124", "link の引数が誤っています。URL は \"https://...\" のように引用符で囲みます")]
        inlinesOf "[link https://example.com/: 例]\n" @?= [[]],
      testCase "G02124: no URL, two, a keyword argument, a URL that is not a string" $ do
        msgs "[link]\n" @?= [wrongArgs]
        msgs "[link: 例]\n" @?= [wrongArgs]
        msgs "[link \"https://a.example/\" \"https://b.example/\": 例]\n" @?= [wrongArgs]
        msgs "[link \"https://example.com/\" title=x: 例]\n" @?= [wrongArgs]
        msgs "[link 3: 例]\n" @?= [wrongArgs]
        msgs "[link [= 3]: 例]\n" @?= [wrongArgs]
        msgs "[link example: 例]\n" @?= [wrongArgs],
      testCase "G02038: two prose slots" $
        msgs "[link \"https://example.com/\": a | b]\n" @?= [("G02038", "link の散文スロットは一つまでです")],
      testCase "G02125: the form of a URL" $ do
        msgs "[link \"https://example.com/a b\": 例]\n" @?= [("G02125", "URL の形が誤っています: https://example.com/a b")]
        msgs "[link \"https://example.com/%zz\": 例]\n" @?= [("G02125", "URL の形が誤っています: https://example.com/%zz")]
        msgs "[link \"https:///a\": 例]\n" @?= [("G02125", "URL の形が誤っています: https:///a")]
        inlinesOf "[link \"https:///a\": 例]\n" @?= [[]],
      testCase "G02126: http and https only" $ do
        msgs "[link \"javascript:alert(1)\": 例]\n" @?= [("G02126", "リンクにできる URL は http と https だけです: javascript:alert(1)")]
        msgs "[link \"mailto:a@example.com\": 例]\n" @?= [("G02126", "リンクにできる URL は http と https だけです: mailto:a@example.com")]
        msgs "[link \"example.com\": 例]\n" @?= [("G02126", "リンクにできる URL は http と https だけです: example.com")]
        msgs "[link \"HTTPS://EXAMPLE.COM/\": 例]\n" @?= [],
      testCase "G02127: the host in ASCII" $ do
        msgs "[link \"https://例え.jp/\": 例]\n" @?= [("G02127", "URL のホストは ASCII で書きます: https://例え.jp/")]
        msgs "[link \"https://ja.wikipedia.org/wiki/組版\": 例]\n" @?= [],
      testCase "G02128: the elements that become links are not inside a link" $ do
        let nested e = [("G02128", "リンクの中にリンクになる要素は置けません: " <> e)]
        msgs "[link \"https://a.example/\": [link \"https://b.example/\": 例]]\n" @?= nested "link"
        msgs "[link \"https://a.example/\": [ref-number intro]]\n" @?= nested "ref-number"
        msgs "[link \"https://a.example/\": [note: 例]]\n" @?= nested "note"
        msgs "[link \"https://a.example/\": [sidenote: 例]]\n" @?= nested "sidenote"
        msgs "[link \"https://a.example/\": [style term: [cite knuth1981]]]\n" @?= nested "cite"
        inlinesOf "[link \"https://a.example/\": [note: 例]]\n" @?= [[]],
      testCase "ruby, a character style and an index mark inside a link" $ do
        msgs "[link \"https://a.example/\": [ruby: 漢 | かん][style term: 語][index reading=ご: 語]]\n" @?= []
        msgs "[ruby: [link \"https://a.example/\": 漢] | かん]\n" @?= [],
      testCase "a link in a note and in a heading" $ do
        msgs "本文[note: [link \"https://a.example/\": 例]]\n" @?= []
        msgs "# [link \"https://a.example/\": 例]\n" @?= []
    ]
