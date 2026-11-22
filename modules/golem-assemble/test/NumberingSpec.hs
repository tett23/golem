-- | numberSeparator (golem-html ADR 0002) and titleSeparator (Golem ADR 0372).
module NumberingSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble.Numbering
import Golem.TestSupport.Enum
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "number separators (golem-html ADR 0002)"
    [ testCase "ADR 0372 I1: inv1_number_title_separator_property: the separator is empty when the number or the title is empty" $
        case checkAll 6 separatorInputs violations of
          Passed n -> assertBool "checked" (n > 1000)
          failed -> assertFailure (show failed),
      testCase "ADR 0372 I1: inv1_number_title_separator_case_1: the empty string: no separator" $ do
        -- an empty separator written, and an empty number and title
        titleSeparator "ja" (Just "") "1" "題" @?= ""
        titleSeparator "ja" (Just "：") "" "" @?= ""
        titleSeparator "ja" Nothing "" "" @?= "",
      testCase "ADR 0372 I1: inv1_number_title_separator_case_2: a title alone: no separator" $ do
        titleSeparator "ja" (Just "：") "" "題" @?= ""
        titleSeparator "en" Nothing "" "Title" @?= "",
      testCase "ADR 0372 I1: inv1_number_title_separator_case_3: both: the string written, once" $ do
        titleSeparator "ja" (Just " | ") "1" "題" @?= " | "
        -- written after a number that ends with a space too
        titleSeparator "en" (Just ": ") "Chapter 1 " "Title" @?= ": ",
      testCase "ADR 0372: without a separator written, that of the language" $ do
        titleSeparator "ja" Nothing "第1章" "題" @?= "\x3000"
        titleSeparator "en" Nothing "1" "Title" @?= " "
        titleSeparator "en" Nothing "Chapter 1: " "Title" @?= "",
      testCase "J1: number separator uses the primary language subtag" $ do
        let cases = [("", False), ("j", False), ("ja", True), ("JA", True), ("ja-JP", True), ("ja-", True), ("jam", False), ("ja_JP", False), ("en", False), ("en-ja", False)]
        mapM_ (\(lang, expected) -> (numberSeparator lang "1" == "\x3000") @?= expected) cases,
      testCase "J2: number separator ignores case" $ do
        let cases = [("", False), ("j", False), ("ja", True), ("JA", True), ("ja-JP", True), ("ja-", True), ("jam", False), ("ja_JP", False), ("en", False), ("en-ja", False)]
        mapM_ (\(lang, _) -> numberSeparator lang "1" @?= numberSeparator (T.toUpper lang) "1") cases,
      testCase "an ideographic space in a Japanese book" $ do
        numberSeparator "ja" "第3章" @?= "\x3000"
        numberSeparator "ja-JP" "1.2" @?= "\x3000"
        numberSeparator "JA" "1" @?= "\x3000",
      testCase "a space in a book of any other language" $ do
        numberSeparator "en" "1" @?= " "
        numberSeparator "EN-us" "1" @?= " "
        numberSeparator "zh" "1" @?= " "
        numberSeparator "jav" "1" @?= " ",
      testCase "nothing after a number that ends with a space" $ do
        numberSeparator "en" "Chapter 1: " @?= ""
        numberSeparator "ja" "第1章\x3000" @?= ""
        numberSeparator "ja" "1\t" @?= ""
    ]

{- | The inputs of titleSeparator from small parts: the language, the
separator written (none, empty or not), the number and the title, each
empty, a space, an ideographic space or a letter.
-}
separatorInputs :: Tiers (Text, Maybe Text, Text, Text)
separatorInputs = cons4 (,,,) (Tiers [["ja", "en", ""]]) written texts texts
  where
    texts = mapT T.pack (listsOf (Tiers [[' ', '\x3000', 'a', '題']]))
    written = value Nothing \/ mapT Just texts

-- | I1: the separator is empty when the number or the title is empty.
violations :: (Text, Maybe Text, Text, Text) -> [Violation]
violations (lang, written, number, title) =
  [ Violation "I1" (show (lang, written, number, title, s))
  | T.null number || T.null title,
    let s = titleSeparator lang written number title,
    not (T.null s)
  ]
