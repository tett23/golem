-- | Citations of several keys and of a page (docs/adr/0266).
module CiteSpec (tests) where

import Control.Monad (forM_)
import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

ctx :: EvalContext
ctx = baseCtx {ctxCiteKeys = Set.fromList ["a", "b", "c", "d"]}

-- | The citations of a source and the codes and messages of its diagnostics.
citesOf :: Text -> ([[CiteItem ()]], [(Text, Text)])
citesOf src =
  let (ds, r) = evalSource ctx src
   in ([is | Paragraph _ xs <- resultBodies r, Cite _ is <- xs], [(diagCodeText d, diagMessage d) | d <- ds])

-- | The codes of the diagnostics of a source.
codes :: Text -> [Text]
codes = map fst . snd . citesOf

page :: LocatorValue -> Maybe Locator
page = Just . Locator LocatorPage

tests :: TestTree
tests =
  testGroup
    "citations (docs/adr/0266)"
    [ testCase "I6: no cause: a citation of as many items as keys, in the order written" $ do
        citesOf "[cite a]\n" @?= ([[citeItem "a"]], [])
        citesOf "[cite c a]\n" @?= ([[citeItem "c", citeItem "a"]], [])
        citesOf "[cite a b c d]\n" @?= ([map citeItem ["a", "b", "c", "d"]], [])
        citesOf "[cite \"b\" a]\n" @?= ([[citeItem "b", citeItem "a"]], []),
      testCase "I6: the keys spread from an array, and a string of [= ...]" $ do
        citesOf "[cite *[[\"b\", \"a\"]]]\n" @?= ([[citeItem "b", citeItem "a"]], [])
        citesOf "[cite [= \"c\"]]\n" @?= ([[citeItem "c"]], []),
      testCase "I6: page is a number, a range, or text" $ do
        citesOf "[cite a page=0]\n" @?= ([[CiteItem "a" (page (LocNumber 0)) [] []]], [])
        citesOf "[cite a page=5]\n" @?= ([[CiteItem "a" (page (LocNumber 5)) [] []]], [])
        citesOf "[cite a page=5...5]\n" @?= ([[CiteItem "a" (page (LocRange 5 5)) [] []]], [])
        citesOf "[cite a page=5...7]\n" @?= ([[CiteItem "a" (page (LocRange 5 7)) [] []]], [])
        citesOf "[cite a page=xii]\n" @?= ([[CiteItem "a" (page (LocText "xii")) [] []]], [])
        citesOf "[cite a page=\"5f.\"]\n" @?= ([[CiteItem "a" (page (LocText "5f.")) [] []]], []),
      testCase "I6: G02021 for a key the bibliography does not have, once each in the order written" $ do
        citesOf "[cite x]\n" @?= ([], [("G02021", "書誌データにないキーです: x")])
        citesOf "[cite a y x]\n" @?= ([], [("G02021", "書誌データにないキーです: y"), ("G02021", "書誌データにないキーです: x")]),
      testCase "I6: G02147 for a key written twice in one citation" $ do
        citesOf "[cite a a]\n" @?= ([], [("G02147", "一つの引用に同じキーを二度書いています: a")])
        citesOf "[cite a b a a]\n" @?= ([], [("G02147", "一つの引用に同じキーを二度書いています: a"), ("G02147", "一つの引用に同じキーを二度書いています: a")]),
      testCase "I6: G02148 for a page that is no page" $
        forM_ ["\"\"", "-1", "[= 1/2]", "[= true]", "[= nil]", "[= [1, 2]]", "[= -1...3]"] $ \v ->
          assertEqual (show v) ["G02148"] (codes ("[cite a page=" <> v <> "]\n")),
      testCase "I6: G02149 for a page of two keys or more" $ do
        citesOf "[cite a b page=5]\n" @?= ([], [("G02149", "page は文献を一つだけ引く cite に書きます")])
        codes "[cite a b c page=5]\n" @?= ["G02149"],
      testCase "I6: G02150 for an argument that is no key" $ do
        citesOf "[cite [= 1]]\n" @?= ([], [("G02150", "cite のキーは名前か文字列で書きます")])
        codes "[cite a [= true]]\n" @?= ["G02150"],
      testCase "I6: G02151 for no key" $ do
        citesOf "[cite]\n" @?= ([], [("G02151", "cite には書誌データのキーを書きます")])
        codes "[cite page=5]\n" @?= ["G02151"],
      testCase "I6, I8: several causes each in the order written, and no citation" $ do
        codes "[cite x a a]\n" @?= ["G02021", "G02147"]
        codes "[cite a x page=\"\"]\n" @?= ["G02021", "G02148", "G02149"]
        codes "[cite [= 1] y y]\n" @?= ["G02150", "G02021", "G02147"]
        codes "[cite page=-1]\n" @?= ["G02148", "G02151"]
        -- the same source, the same diagnostics in the same order
        citesOf "[cite x a a page=-1]\n" @?= citesOf "[cite x a a page=-1]\n",
      testCase "cite takes no prose slot, as before (G02038)" $
        codes "[cite a: x]\n" @?= ["G02038"]
    ]
