{- | The hyphenation exceptions of a book and of a file (docs/adr ADR 0272,
its section 3): looked up by the language of the word (RFC 4647 lookup),
the file's first, then the book's, then the bundled ones, then the
patterns.
-}
module ExceptionsSpec (exceptionsTests) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Text (Text)
import Golem.Layout.Hyphenation
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Hyphenation.Languages
import Test.Tasty
import Test.Tasty.HUnit

-- | The parts of a word with the exceptions of a file and of a book, in a language span (Nothing: outside one).
parts :: Map Text [Text] -> Map Text [Text] -> Maybe Text -> Text -> [Text]
parts file book lang w = maybe [w] (`hyphenate` w) (exceptionPatterns "ja" file book lang)

none :: Map Text [Text]
none = Map.empty

bundled :: [Text]
bundled = ["associate", "associates", "declination", "obligatory", "philanthropic", "present", "presents", "project", "projects", "reciprocity", "recognizance", "reformation", "retribution", "table"]

exceptionsTests :: TestTree
exceptionsTests =
  testGroup
    "hyphenation exceptions (docs/adr ADR 0272)"
    [ testCase "I5: a word of the list breaks at its hyphens, one without hyphens not at all, one not in the list by the patterns" $ do
        let book = Map.fromList [("en", ["hyphe-na-tion", "algorithm"])]
        parts none book Nothing "hyphenation" @?= ["hyphe", "na", "tion"]
        parts none book Nothing "algorithm" @?= ["algorithm"]
        parts none book Nothing "typesetting" @?= hyphenate englishUS "typesetting",
      testCase "I5: no two and three letters: a-ble breaks after one letter" $
        parts none (Map.fromList [("en", ["a-ble"])]) Nothing "able" @?= ["a", "ble"],
      testCase "I5: the word is looked up in lower case, as written in the list" $
        parts none (Map.fromList [("en", ["Go-lem"])]) Nothing "GOLEM" @?= ["GO", "LEM"],
      testCase "I5: a word of the book replaces the bundled one, the other 13 stay" $ do
        let book = Map.fromList [("en", ["tab-le"])]
        parts none book Nothing "table" @?= ["tab", "le"]
        length [w | w <- bundled, w /= "table"] @?= 13
        [w | w <- bundled, w /= "table", parts none book Nothing w /= hyphenate englishUS w] @?= [],
      testCase "I6: en-GB words take the key en; en words do not take a key en-US only" $ do
        let en = Map.fromList [("en", ["algo-rithm"])]
            enUS = Map.fromList [("en-US", ["algo-rithm"])]
        parts none en (Just "en-GB") "algorithm" @?= ["algo", "rithm"]
        parts none enUS (Just "en") "algorithm" @?= hyphenate englishUS "algorithm"
        parts none enUS (Just "en-us") "algorithm" @?= ["algo", "rithm"],
      testCase "I6: the words outside a span are of en-US: they take the key en" $
        parts none (Map.fromList [("en", ["algo-rithm"])]) Nothing "algorithm" @?= ["algo", "rithm"],
      testCase "I6: sv has no patterns (docs/adr ADR 0276): its list alone hyphenates, the other words stay whole" $ do
        let book = Map.fromList [("sv", ["ma-nu-skript"])]
        parts none book (Just "sv") "manuskript" @?= ["ma", "nu", "skript"]
        parts none book (Just "sv") "typografi" @?= ["typografi"]
        isNothing (exceptionPatterns "ja" none none (Just "sv")) @?= True,
      testCase "I6: no key of the language: the patterns as without a list" $
        parts none (Map.fromList [("fr", ["algo-rithm"])]) Nothing "algorithm" @?= hyphenate englishUS "algorithm",
      testCase "RFC 4647 lookup: the tag, then its subtags taken off from the end, a single letter with the one before it" $ do
        let m = Map.fromList [("en", 1 :: Int), ("zh-Hant", 2)]
        lookupTag m "en-Latn-US" @?= Just 1
        lookupTag m "zh-Hant-x-a" @?= Just 2
        lookupTag m "EN" @?= Just 1
        lookupTag m "fr" @?= Nothing,
      testCase "I12: the file's list first, then the book's, then the bundled, then the patterns" $ do
        let file = Map.fromList [("en", ["ta-b-le"])]
            book = Map.fromList [("en", ["tabl-e", "algo-rithm"])]
        -- only in the book
        parts none book Nothing "table" @?= ["tabl", "e"]
        -- only in the file
        parts file none Nothing "table" @?= ["ta", "b", "le"]
        -- in both, at different places: the file's
        parts file book Nothing "table" @?= ["ta", "b", "le"]
        -- different words in both: each
        parts file book Nothing "algorithm" @?= ["algo", "rithm"]
        -- the bundled, then the patterns
        parts file book Nothing "project" @?= ["project"]
        parts file book Nothing "hyphenation" @?= hyphenate englishUS "hyphenation",
      testCase "I12: the file's en and the book's en-US are looked up apart" $ do
        let file = Map.fromList [("en", ["ta-b-le"])]
            book = Map.fromList [("en-US", ["tabl-e", "algo-rithm"])]
        parts file book (Just "en-US") "table" @?= ["ta", "b", "le"]
        parts file book (Just "en-US") "algorithm" @?= ["algo", "rithm"]
        parts file book (Just "en") "algorithm" @?= hyphenate englishUS "algorithm"
    ]
