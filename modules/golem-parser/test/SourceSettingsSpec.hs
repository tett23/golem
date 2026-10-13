module SourceSettingsSpec (tests) where

import Data.Text (Text)
import Golem.Parser.SourceSettings
import Test.Tasty
import Test.Tasty.HUnit

-- | The separator a value of paragraph-separator gives, or the error.
separator :: Text -> Either Text ParagraphSeparator
separator v = case lookup "paragraph-separator" sourceKeys of
  Nothing -> Left "no key"
  Just f -> (\g -> ssParagraphSeparator (g (SourceSettings LineSeparated))) <$> f v

isLeft :: Either a b -> Bool
isLeft = either (const True) (const False)

tests :: TestTree
tests =
  testGroup
    "source settings (docs/adr ADR 0013)"
    [ testCase "the default separates paragraphs by a blank line" $
        ssParagraphSeparator defaultSourceSettings @?= BlankLineSeparated,
      testCase "paragraph-separator takes line and blank-line" $ do
        separator "line" @?= Right LineSeparated
        separator "blank-line" @?= Right BlankLineSeparated
        ssParagraphSeparator . ($ defaultSourceSettings) <$> maybe (Left "no key") ($ "line") (lookup "paragraph-separator" sourceKeys) @?= Right LineSeparated,
      testCase "other values are errors" $ do
        assertBool "Line" (isLeft (separator "Line"))
        assertBool "lines" (isLeft (separator "lines"))
    ]
