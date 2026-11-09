-- | @hyphenation-exceptions, the hyphenation exceptions of a file (docs/adr ADR 0272).
module ExceptionsSpec (tests) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.Builtin (builtinBlockCommands)
import Golem.Eval.File
import Golem.Project.Style (LocalStyles (..))
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | The lists of a source.
listsOf :: Text -> Map Text [Text]
listsOf = lsHyphenationExceptions . erStyles . evalResult baseCtx

-- | The code and the start of each diagnostic of a source.
sites :: Text -> [(Text, Int)]
sites src = [(c, s) | (c, _, s, _) <- map diagSite (fst (evalSource baseCtx src))]

-- | Where a text starts in a source, in bytes of its ASCII.
at :: Text -> Text -> Int
at src t = T.length (fst (T.breakOn t src))

tests :: TestTree
tests =
  testGroup
    "@hyphenation-exceptions (docs/adr ADR 0272)"
    [ testCase "a line for each language, a word or a string for each word" $ do
        let src = "@hyphenation-exceptions en ta-ble pro-ject Golem\n@hyphenation-exceptions fr \"ma-nu-scrit\"\n\nbody\n"
        listsOf src @?= Map.fromList [("en", ["ta-ble", "pro-ject", "Golem"]), ("fr", ["ma-nu-scrit"])]
        sites src @?= [],
      testCase "a language and one word is no error" $ do
        listsOf "@hyphenation-exceptions en ta-ble\n\nx\n" @?= Map.fromList [("en", ["ta-ble"])]
        sites "@hyphenation-exceptions en ta-ble\n\nx\n" @?= [],
      testCase "the arguments: the language alone G02052, a keyword G02153, a body G02097, a spread G02114, after the settings G02049" $ do
        let line = "@hyphenation-exceptions en\n\nx\n"
        sites line @?= [("G02052", 0)]
        listsOf line @?= Map.empty
        let kw = "@hyphenation-exceptions en ta-ble x=1\n\nx\n"
        sites kw @?= [("G02153", at kw "x=1")]
        listsOf kw @?= Map.fromList [("en", ["ta-ble"])]
        let body = "@hyphenation-exceptions en ta-ble\n  y\n\nx\n"
        map fst (sites body) @?= ["G02097"]
        let spread = "@hyphenation-exceptions en ta-ble *[[\"a-b\"]]\n\nx\n"
        sites spread @?= [("G02114", at spread "*[")]
        let late = "x\n\n@hyphenation-exceptions en ta-ble\n"
        sites late @?= [("G02049", at late "@hyphenation")],
      testCase "G02116 for a value that is no word nor string" $
        map fst (sites "@hyphenation-exceptions en [= 1]\n\nx\n") @?= ["G02116"],
      testCase "I11: each wrong word gives its code at the word, and is left out; the others stay" $ do
        let src = "@hyphenation-exceptions en ta-ble a- -a a--b ab1 \"\" \"-\" Ta-ble pro-ject\n\nx\n"
        sites src
          @?= [ ("G03128", at src "a- "),
                ("G03128", at src "-a "),
                ("G03128", at src "a--b"),
                ("G03127", at src "ab1"),
                ("G03127", at src "\"\""),
                ("G03128", at src "\"-\""),
                ("G03129", at src "Ta-ble")
              ]
        listsOf src @?= Map.fromList [("en", ["ta-ble", "pro-ject"])],
      testCase "I11: G03126 for a tag not of the form, G03130 for a second line of a tag but for case: the line is left out" $ do
        let bad = "@hyphenation-exceptions \"e n\" ta-ble\n\nx\n"
        sites bad @?= [("G03126", at bad "\"e n\"")]
        listsOf bad @?= Map.empty
        let twice = "@hyphenation-exceptions en ta-ble\n@hyphenation-exceptions EN pro-ject\n\nx\n"
        sites twice @?= [("G03130", at twice "EN")]
        listsOf twice @?= Map.fromList [("en", ["ta-ble"])],
      testCase "hyphenation-exceptions is a built-in block command name" $
        assertBool "builtin" ("hyphenation-exceptions" `elem` builtinBlockCommands)
    ]
