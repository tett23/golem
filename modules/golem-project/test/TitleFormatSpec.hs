{- | The key title-format of [headings.<l>] and of the paragraph styles
(root ADR 0463): a format of text, escapes and slots, read where
number-title-separator is read.
-}
module TitleFormatSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Assemble.Numbering (TitlePiece (..))
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

-- | The codes of the errors of a style.toml, or nothing when it reads.
codesOf :: Text -> [Text]
codesOf src = case parseStyle (FileId 0) src of
  Right _ -> []
  Left ds -> [c | d <- ds, let DiagnosticCode c = diagCode d]

-- | The title format of [headings.1] of a style.toml that reads.
headingFormat :: Text -> Maybe [TitleFormatPart]
headingFormat src = case parseStyle (FileId 0) src of
  Right s -> Map.lookup 1 (stHeadings s) >>= hsTitleFormat
  Left ds -> error (show ds)

tests :: TestTree
tests =
  testGroup
    "title-format (root ADR 0463)"
    [ testCase "root ADR 0463 I2: the slots and the text of a format, in order" $
        parseTitleFormat "{title}（{number}）{separator}{meta.title}{set.part}{set.ns.part?}{vars.series}"
          @?= Right
            [ FormatPiece TitleTitle,
              FormatPiece (TitleText "（"),
              FormatPiece TitleNumber,
              FormatPiece (TitleText "）"),
              FormatPiece TitleSeparator,
              FormatRef (RefMeta "title") False,
              FormatRef (RefVar ["part"]) False,
              FormatRef (RefVar ["ns", "part"]) True,
              FormatRef (RefProjectVar ["series"]) False
            ],
      testCase "root ADR 0463 I2: the escapes are text, and an empty format has no pieces" $ do
        parseTitleFormat "\\{number\\}{number}" @?= Right [FormatPiece (TitleText "{number}"), FormatPiece TitleNumber]
        parseTitleFormat "" @?= Right [],
      testCase "root ADR 0463 I2: [headings.1] and a paragraph style read title-format" $ do
        headingFormat "[headings.1]\nnumber = \"第{n}章\"\ntitle-format = \"{number}{separator}{title}\"\n"
          @?= Just [FormatPiece TitleNumber, FormatPiece TitleSeparator, FormatPiece TitleTitle]
        case parseStyle (FileId 0) "[paragraph-styles.caption]\ntitle-format = \"{title}（{number}）\"\n" of
          Right s -> (Map.lookup "caption" (stParaStyles s) >>= psTitleFormat) @?= Just [FormatPiece TitleTitle, FormatPiece (TitleText "（"), FormatPiece TitleNumber, FormatPiece (TitleText "）")]
          Left ds -> assertFailure (show ds),
      testCase "root ADR 0463 I1: without title-format, no format" $
        headingFormat "[headings.1]\nnumber = \"第{n}章\"\n" @?= Nothing,
      testCase "root ADR 0463 I6: an unknown slot is one G03296, however many are wrong" $ do
        codesOf "[headings.1]\ntitle-format = \"{nmber}{titel}\"\n" @?= ["G03296"]
        codesOf "[paragraph-styles.caption]\ntitle-format = \"{nmber}{titel}\"\n" @?= ["G03296"],
      testCase "root ADR 0463 I6: {{ and }} are no braces in title-format: one G03296" $
        codesOf "[headings.1]\ntitle-format = \"{{number}}\"\n" @?= ["G03296"],
      testCase "root ADR 0463 I6: a { not closed and a newline are G03296" $ do
        codesOf "[headings.1]\ntitle-format = \"{number\"\n" @?= ["G03296"]
        codesOf "[headings.1]\ntitle-format = \"{number}\\n{title}\"\n" @?= ["G03296"],
      testCase "root ADR 0463 I6: the message names title-format and the reason" $
        case parseStyle (FileId 0) "[headings.1]\ntitle-format = \"{nmber}\"\n" of
          Left [d] -> diagMessage d @?= "title-format を書式として読めません: 未知の差し込みです: {nmber} (headings.1.title-format)"
          r -> assertFailure (show r),
      testCase "root ADR 0463 I7: a title-format that is not a string is G03006" $ do
        codesOf "[headings.1]\ntitle-format = 1\n" @?= ["G03006"]
        codesOf "[paragraph-styles.caption]\ntitle-format = true\n" @?= ["G03006"],
      testCase "root ADR 0463 I6: a notation after a slot of the format is G03296" $
        codesOf "[headings.1]\ntitle-format = \"{number:kanji}\"\n" @?= ["G03296"]
    ]
