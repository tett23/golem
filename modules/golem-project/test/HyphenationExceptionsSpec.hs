-- | [composition.hyphenation-exceptions] of style.toml (docs/adr ADR 0272).
module HyphenationExceptionsSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

-- | The code and the start of each diagnostic of a style.toml.
diags :: Text -> [(Text, Int)]
diags src = either (map (\d -> let DiagnosticCode c = diagCode d in (c, spanStart (diagSpan d)))) (const []) (parseStyle (FileId 0) src)

-- | A style.toml of one list.
listed :: Text -> Text
listed v = "[composition.hyphenation-exceptions]\n" <> v <> "\n"

-- | Where a text starts in a source.
at :: Text -> Text -> Int
at src t = T.length (fst (T.breakOn t src))

tests :: TestTree
tests =
  testGroup
    "[composition.hyphenation-exceptions] (docs/adr ADR 0272)"
    [ testCase "the lists are read by tag as written" $ do
        let s = parseStyle (FileId 0) (listed "en = [\"ta-ble\", \"pro-ject\", \"Golem\"]\nfr = [\"ma-nu-scrit\"]")
        fmap (compHyphenationExceptions . stComposition) s @?= Right (Map.fromList [("en", ["ta-ble", "pro-ject", "Golem"]), ("fr", ["ma-nu-scrit"])])
        fmap (compHyphenationExceptions . stComposition) (parseStyle (FileId 0) "") @?= Right Map.empty,
      testCase "I11: no code for lists without errors, a word of one hyphen, two, one letter before it, a capital" $
        diags (listed "en = [\"chair\", \"ta-ble\", \"hy-phen-ation\", \"a-ble\", \"Go-lem\"]\nen-US = [\"x\"]\nfr = [\"y\"]") @?= [],
      testCase "I11: G03127 for an empty word, a digit, a space; G03128 for -, a-, -a, a--b, each at its word" $ do
        let src = listed "en = [\"\", \"ab1\", \"a b\", \"-\", \"a-\", \"-a\", \"a--b\"]"
            words' = ["\"\"", "\"ab1\"", "\"a b\"", "\"-\"", "\"a-\"", "\"-a\"", "\"a--b\""]
        diags src @?= zip ["G03127", "G03127", "G03127", "G03128", "G03128", "G03128", "G03128"] (map (at src) words'),
      testCase "I11: G03129 for the same word again, whatever its hyphens or case" $ do
        let src = listed "en = [\"ta-ble\", \"tab-le\", \"TABLE\", \"pro-ject\"]"
        diags src @?= [("G03129", at src "\"tab-le\""), ("G03129", at src "\"TABLE\"")],
      testCase "I11: one code for a word of two errors: G03127 before G03128 before G03129" $ do
        diags (listed "en = [\"-1\"]") @?= [("G03127", T.length "[composition.hyphenation-exceptions]\nen = [")]
        let src = listed "en = [\"ab\", \"-ab\"]"
        diags src @?= [("G03128", at src "\"-ab\"")],
      testCase "I11: G03126 for a key not of the form of a tag, G03130 for two keys that differ only in case" $ do
        map fst (diags (listed "\"e n\" = [\"ta-ble\"]")) @?= ["G03126"]
        map fst (diags (listed "en = [\"ta-ble\"]\nEN = [\"pro-ject\"]")) @?= ["G03130"],
      testCase "a value that is not an array of strings is G03006" $ do
        map fst (diags (listed "en = \"ta-ble\"")) @?= ["G03006"]
        map fst (diags (listed "en = [1]")) @?= ["G03006"]
    ]
