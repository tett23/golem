module ParagraphPitchSpec (tests) where

import Control.Monad (forM_)
import Data.Text (Text)
import Golem.Length qualified as L
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

page :: Text -> Text
page alignment = "[page]\nsize = \"B6\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 20\nlines = 20\nline-pitch = \"16pt\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n" <> alignment

check :: Text -> Assertion
check src = case parseStyle (FileId 0) src of
  Left ds -> assertFailure (show ds)
  Right _ -> pure ()

reject :: Text -> Assertion
reject src = case parseStyle (FileId 0) src of
  Left ds -> assertBool (show ds) (any ((== DiagnosticCode "G03006") . diagCode) ds)
  Right s -> assertFailure (show s)

tests :: TestTree
tests =
  testGroup
    "paragraph dimensions"
    [ testCase "root ADR 0397 I1: omitted alignment preserves existing configuration" $
        check (page "" <> "[paragraph-styles.body]\nspace-before = 1\n"),
      testCase "root ADR 0397 I2: free placement accepts independent pitch and spacing" $
        check (page "alignment = \"free\"\n" <> "[paragraph-styles.body]\nline-pitch = \"12pt\"\nspace-before = \"1pt\"\nspace-after = \"0pt\"\nspace-between = \"0.5zw\"\n"),
      testCase "root ADR 0397 I6: auto remains valid in grid layout" $
        check (page "alignment = \"grid\"\n" <> "[paragraph-styles.body]\nline-pitch = \"auto\"\n"),
      testCase "root ADR 0397 I6: dimensional fields are rejected in grid layout" $
        forM_ ["line-pitch", "space-before", "space-after", "space-between"] $ \key ->
          reject (page "" <> "[paragraph-styles.body]\n" <> key <> " = \"1pt\"\n"),
      testCase "root ADR 0397 I6: invalid free dimensions are rejected" $
        forM_ ["line-pitch = \"0pt\"", "line-pitch = \"-1pt\"", "space-before = \"-1pt\"", "space-after = \"bad\""] $ \field ->
          reject (page "alignment = \"free\"\n" <> "[paragraph-styles.body]\n" <> field <> "\n"),
      testCase "root ADR 0397 I6: code cannot define line pitch" $
        reject (page "alignment = \"free\"\n" <> "[paragraph-styles.code]\nline-pitch = \"auto\"\n"),
      testCase "root ADR 0397 I6: code cannot bypass forbidden spacing with dimensions" $
        forM_ ["space-between", "space-before", "space-after"] $ \key ->
          reject (page "alignment = \"free\"\n" <> "[paragraph-styles.code]\n" <> key <> " = \"1pt\"\n"),
      testCase "root ADR 0397 I6: invalid alignment is rejected" $
        reject (page "alignment = \"other\"\n"),
      testCase "root ADR 0397 I2: zw resolves against inherited paragraph size" $
        case parseStyle (FileId 0) (page "alignment = \"free\"\n" <> "[paragraph-styles.body]\nsize = \"9pt\"\nline-pitch = \"1zw\"\nspace-between = \"0.5zw\"\nspace-before = 1\n[paragraph-styles.dialogue]\nbased-on = \"body\"\n") of
          Left ds -> assertFailure (show ds)
          Right style -> case paraStyle style (Just "dialogue") of
            Nothing -> assertFailure "missing dialogue style"
            Just d -> do
              resolvedParagraphPitch style d @?= Just (L.toSp L.Pt 9)
              (resolvedParagraphSpacing style d . SpacingDim =<< psSpaceBetweenDim d) @?= Just (L.toSp L.Pt (9 / 2))
              (resolvedParagraphSpacing style d . SpacingLines =<< psSpaceBefore d) @?= Just (L.toSp L.Pt 16),
      testCase "root ADR 0397 I6: inherited dimensions fail in grid mode" $
        reject (page "" <> "[paragraph-styles.body]\nline-pitch = \"12pt\"\n[paragraph-styles.dialogue]\nbased-on = \"body\"\n"),
      testCase "root ADR 0397 I6: rounded zero pitch fails" $
        reject (page "alignment = \"free\"\n" <> "[paragraph-styles.body]\nline-pitch = \"0.0000000001pt\"\n")
    ]
