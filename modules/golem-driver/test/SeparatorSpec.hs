module SeparatorSpec (visibleSeparatorTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text.Encoding qualified as TE
import Golem.Layout.Paginate (PageOut (..))
import Golem.Syntax (DiagnosticCode (..))
import Golem.Typeset (PdfLayout (..))
import Support
import Test.Tasty
import Test.Tasty.HUnit

visibleSeparatorTests :: [TestTree]
visibleSeparatorTests =
  [ testCase "root ADR 0398 I4: visible separator owns one line and both spaces" $ do
      let style = horizontalStyle <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\nspace-before = 1\nspace-after = 1\n"
      (_, layout) <- layoutOk style "前。\n---\n後。\n" []
      map (map fst . poSlots) (plPages layout) @?= [[0, 2, 4]]
      Map.size (plLines layout) @?= 3,
    testCase "root ADR 0398 I7: separator and next line move together" $ do
      let style = replaceIn "lines = 30" "lines = 3" horizontalStyle <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\n"
      (_, layout) <- layoutOk style "前。\n\n中。\n---\n後。\n" []
      map (map fst . poSlots) (plPages layout) @?= [[0, 1], [0, 1]],
    testCase "root ADR 0398 I7: a visible separator survives at the top" $ do
      let style = replaceIn "lines = 30" "lines = 3" horizontalStyle <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\nspace-before = 1\n"
      (_, layout) <- layoutOk style "---\n後。\n" []
      map (map fst . poSlots) (plPages layout) @?= [[0, 1]],
    testCase "root ADR 0398 I4: adjacent separators take the larger boundary" $ do
      let style = horizontalStyle <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\nspace-after = 2\n[separators.scene]\nkind = \"text\"\ntext = \"＊＊\"\nspace-before = 1\n"
      (_, layout) <- layoutOk style "前。\n---\n@separator scene\n後。\n" []
      map (map fst . poSlots) (plPages layout) @?= [[0, 1, 4, 5]],
    testCase "root ADR 0398 A4: vertical visible separator occupies one line" $ do
      let style = replaceIn "lines = 30" "lines = 12" (replaceIn "writing-mode = \"horizontal\"" "writing-mode = \"vertical\"" horizontalStyle) <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\nspace-before = 1\nspace-after = 1\n"
      (_, layout) <- layoutOk style "前。\n---\n後。\n" []
      map (map fst . poSlots) (plPages layout) @?= [[0, 2, 4]],
    testCase "root ADR 0398 I4: explicit blanks take the maximum at a separator" $ do
      let style = horizontalStyle <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\nspace-before = 1\nspace-after = 1\n"
      (_, layout) <- layoutOk style "前。\n@blank-line 2\n---\n後。\n" []
      map (map fst . poSlots) (plPages layout) @?= [[0, 3, 5]],
    testCase "root ADR 0398 A2: PDF draws a rule in one occupied line" $ do
      let style = horizontalStyle <> "\n[separators.default]\nkind = \"rule\"\nspace-before = 1\nspace-after = 1\n[separators.default.rule]\nlength = \"10zw\"\nweight = \"0.5pt\"\n"
      pdf <- miniPdf fakeProvider True style "前。\n---\n後。\n" []
      content <- BS.concat <$> inflateAll pdf
      length (rulesIn content) @?= 1,
    testCase "root ADR 0398 A5: oversized text reports G07134 and rule length G03006" $ do
      let textStyle = horizontalStyle <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"あいうえおかきくけこさしすせそ\"\n"
          ruleStyle = horizontalStyle <> "\n[separators.default]\nkind = \"rule\"\n[separators.default.rule]\nlength = \"1000zw\"\n"
      (textCodes, _) <- buildMini fakeProvider True textStyle "---\n後。\n" []
      (ruleCodes, _) <- buildMini fakeProvider True ruleStyle "---\n後。\n" []
      assertBool "text too long" (DiagnosticCode "G07134" `elem` textCodes)
      assertBool "rule length is a style error" (DiagnosticCode "G03006" `elem` ruleCodes)
  ]
