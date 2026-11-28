-- | Citations of several keys and of a page (docs/adr/0266).
module CiteSpec (tests) where

import Control.Monad (forM_)
import Data.List (permutations)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.Builtin (BuiltinInline (..))
import Golem.Eval.File
import Golem.Eval.Value (PluginArg (..), Value (..))
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
    [ testCase "root ADR 0475 I6: citation affixes are literal text, including markup and empty strings" $
        forM_ ["", "<a>&[cite x]", "参照: {year}"] $ \literal ->
          let source = "[cite a prefix=" <> ("\"" <> literal <> "\"") <> " suffix=" <> ("\"" <> literal <> "\"") <> "]\n"
              (items, ds) = citesOf source
           in (ds, [[([t | Text _ t <- citPrefix item], [t | Text _ t <- citSuffix item]) | item <- xs] | xs <- items])
                @?= ([], [[([literal], [literal])]]),
      testCase "root ADR 0475 I1, I6: every non-string affix reports G02299 and removes the citation" $
        forM_ ["prefix", "suffix"] $ \name ->
          forM_ ["7", "[= true]", "[= nil]", "[= [1]]", "[= 1/2]", "2...4"] $ \value ->
            let (items, ds) = citesOf ("[cite a " <> name <> "=" <> value <> "]\n")
             in (items, map fst ds) @?= ([], ["G02299"]),
      testCase "root ADR 0475 I6: each cites slot preserves its own affixes" $
        let (items, ds) = citesOf "[cites: [cite a prefix=\"A\" suffix=\"!\"]|[cite b prefix=\"B\" suffix=\"?\"]]\n"
         in (ds, [[(citKey item, [t | Text _ t <- citPrefix item], [t | Text _ t <- citSuffix item]) | item <- xs] | xs <- items])
              @?= ([], [[("a", ["A"], ["!"]), ("b", ["B"], ["?"])]]),
      testCase "root ADR 0475 I1, I6: affix errors point at numeric and expression values" $
        forM_ [("[cite a prefix=7]\n", (15, 16)), ("[cite a suffix=[= true]]\n", (15, 23))] $ \(source, expected) ->
          let (ds, _) = evalSource ctx source
           in [(diagCodeText d, (spanStart (diagSpan d), spanEnd (diagSpan d))) | d <- ds] @?= [("G02299", expected)],
      testCase "root ADR 0385 I1: cites aggregation preserves the locator and affix IR" $
        let command = PluginCommand $ \args _ at -> case args of
              [PluginPositional (VString key)] -> Right ([Cite at [CiteItem key (Just (Locator LocatorChapter (LocNumber 2))) [Text at "cf. "] [Text at "!"]]], [])
              _ -> Left []
            custom = ctx {ctxPlugins = noPlugins {phOverrides = Map.singleton BCite command}}
            (ds, result) = evalSource custom "[cites: [cite \"a\"]|[cite \"b\"]]\n"
            itemParts item = (citKey item, citLocator item, [t | Text _ t <- citPrefix item], [t | Text _ t <- citSuffix item])
         in (map diagCodeText ds, [[itemParts item | item <- items] | Paragraph _ xs <- resultBodies result, Cite _ items <- xs])
              @?= ([], [[(key, Just (Locator LocatorChapter (LocNumber 2)), ["cf. "], ["!"]) | key <- ["a", "b"]]]),
      testCase "root ADR 0385 I1: cites keeps each page across every four-key permutation" $
        forM_ (permutations [("a", 2), ("b", 5), ("c", 7), ("d", 11)]) $ \entries ->
          let source = "[cites: " <> T.intercalate "|" ["[cite " <> key <> " page=" <> T.pack (show (number :: Integer)) <> "]" | (key, number) <- entries] <> "]\n"
           in citesOf source @?= ([[CiteItem key (page (LocNumber number)) [] [] | (key, number) <- entries]], []),
      testCase "root ADR 0385 I1: cites accepts line wrapping around slot citations" $
        citesOf "[cites:\n [cite a] |\n [cite b]\n]\n" @?= ([[citeItem "a", citeItem "b"]], []),
      testCase "root ADR 0385 I1: a duplicate points at its repeated key" $
        let (ds, _) = evalSource ctx "[cites: [cite a]|[cite b]|[cite a]]\n"
         in [(spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- ds] @?= [(32, 33)],
      testCase "root ADR 0385 I1: duplicate and child errors are all reported in source order" $
        codes "[cites: [cite a]|[cite a]|[cite x]]\n" @?= ["G02147", "G02021"],
      testCase "root ADR 0385 I1: cites combines single-key citations in written order" $
        citesOf "[cites: [cite c]|[cite a]]\n" @?= ([[citeItem "c", citeItem "a"]], []),
      testCase "root ADR 0385 I1: each cites item retains its own page" $
        citesOf "[cites: [cite a page=5]|[cite b page=7...9]]\n"
          @?= ([[CiteItem "a" (page (LocNumber 5)) [] [], CiteItem "b" (page (LocRange 7 9)) [] []]], []),
      testCase "root ADR 0385 I1: cites permits surrounding slot whitespace" $
        citesOf "[cites: [cite a] | [cite b] ]\n" @?= ([[citeItem "a", citeItem "b"]], []),
      testCase "root ADR 0385 I1: duplicate cites keys are G02147" $
        codes "[cites: [cite a]|[cite b]|[cite a]]\n" @?= ["G02147"],
      testCase "root ADR 0385 I1: cites slots require one single-key citation" $
        forM_ ["[cites]", "[cites:]", "[cites: text]", "[cites: [cite a b]]", "[cites: [cite a][cite b]]", "[cites: [cite a]|]", "[cites a: [cite a]]"] $ \source ->
          assertEqual (show source) ["G02038"] (codes (source <> "\n")),
      testCase "root ADR 0385 I1: child citation errors are retained once" $
        codes "[cites: [cite x]|[cite a]]\n" @?= ["G02021"],
      testCase "I6: no cause: a citation of as many items as keys, in the order written" $ do
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
