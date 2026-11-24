module SeparatorSpec (visibleSeparatorTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Layout.Paginate (PageOutAt (..))
import Golem.LayoutSpec (PageGeometry (..), Rect (..), typeAreaFor)
import Golem.Length (Unit (Pt), fromSp)
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..), SrcSpan (..))
import Golem.Typeset (PdfLayout (..))
import Support
import Test.Tasty
import Test.Tasty.HUnit

visibleSeparatorTests :: [TestTree]
visibleSeparatorTests =
  [ testCase "root ADR 0398 I4: free HTML separators use the base pitch rather than the paragraph override" $ do
      let style = replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" horizontalStyle <> "\n[paragraph-styles.body]\nline-pitch = \"12.5pt\"\n[separators.default]\nkind = \"text\"\ntext = \"*\"\nspace-before = 1\nspace-after = 1\n"
      (_, css) <- htmlMini style "前。\n---\n後。\n"
      assertBool "separator occupies the physical base pitch" (".separator { display: block; block-size: 15pt; line-height: 15pt; }" `T.isInfixOf` css),
    testCase "root ADR 0398 I7: a free separator hold moves to the next column when that empty column fits" $ do
      let style = replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" (replaceIn "lines = 30" "lines = 4" horizontalStyle) <> "\n[separators.default]\nkind = \"text\"\ntext = \"*\"\n"
      (_, layout) <- layoutOk style "前。\n\n中。\n---\n後。\n" []
      map (map (fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0, 15], [0, 15]],
    testCase "root ADR 0398 I4: free separators preserve fractional cursor positions and base-pitch spaces" $ do
      let style = replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" horizontalStyle <> "\n[paragraph-styles.body]\nline-pitch = \"12.5pt\"\n[separators.default]\nkind = \"text\"\ntext = \"*\"\nspace-before = 1\nspace-after = 1\n"
      (_, layout) <- layoutOk style "前。\n---\n後。\n" []
      map (map (fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0, 27.5, 57.5]],
    testCase "root ADR 0398 I4: visible separator owns one line and both spaces" $ do
      let style = horizontalStyle <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\nspace-before = 1\nspace-after = 1\n"
      (_, layout) <- layoutOk style "前。\n---\n後。\n" []
      map (map ((/ 15) . fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0, 2, 4]]
      Map.size (plLines layout) @?= 3,
    testCase "root ADR 0398 I7: separator and next line move together" $ do
      let style = replaceIn "lines = 30" "lines = 3" horizontalStyle <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\n"
      (_, layout) <- layoutOk style "前。\n\n中。\n---\n後。\n" []
      map (map ((/ 15) . fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0, 1], [0, 1]],
    testCase "root ADR 0398 I7: a visible separator survives at the top" $ do
      let style = replaceIn "lines = 30" "lines = 3" horizontalStyle <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\nspace-before = 1\n"
      (_, layout) <- layoutOk style "---\n後。\n" []
      map (map ((/ 15) . fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0, 1]],
    testCase "root ADR 0398 I4: adjacent separators take the larger boundary" $ do
      let style = horizontalStyle <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\nspace-after = 2\n[separators.scene]\nkind = \"text\"\ntext = \"＊＊\"\nspace-before = 1\n"
      (_, layout) <- layoutOk style "前。\n---\n@separator scene\n後。\n" []
      map (map ((/ 15) . fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0, 1, 4, 5]],
    testCase "root ADR 0398 A4: vertical visible separator occupies one line" $ do
      let style = replaceIn "lines = 30" "lines = 12" (replaceIn "writing-mode = \"horizontal\"" "writing-mode = \"vertical\"" horizontalStyle) <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\nspace-before = 1\nspace-after = 1\n"
      (_, layout) <- layoutOk style "前。\n---\n後。\n" []
      map (map ((/ 15) . fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0, 2, 4]],
    testCase "root ADR 0398 I4: explicit blanks take the maximum at a separator" $ do
      let style = horizontalStyle <> TE.encodeUtf8 "\n[separators.default]\nkind = \"text\"\ntext = \"＊\"\nspace-before = 1\nspace-after = 1\n"
      (_, layout) <- layoutOk style "前。\n@blank-line 2\n---\n後。\n" []
      map (map ((/ 15) . fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0, 3, 5]],
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
    <> [ testCase ("root ADR 0398 I4: rule is centered inside its occupied line in " <> T.unpack mode <> " " <> T.unpack direction) $ do
           let fitting = if direction == "vertical" then replaceIn "lines = 30" "lines = 12" horizontalStyle else horizontalStyle
               base = replaceIn "writing-mode = \"horizontal\"" ("writing-mode = \"" <> direction <> "\"") fitting
               style = replaceIn "[page.grid]" ("[page.grid]\nalignment = \"" <> mode <> "\"") base <> "\n[separators.default]\nkind = \"rule\"\n[separators.default.rule]\nweight = \"0.5pt\"\n"
               source = "前。\n---\n後。\n"
           (geom, layout) <- layoutOk style source []
           pdf <- miniPdf fakeProvider True style source []
           content <- BS.concat <$> inflateAll pdf
           case (plPages layout, rulesIn content) of
             ([page], [[x, y, w, h]]) -> case map fst (poSlots page) of
               [_, slot, _] -> do
                 let area = typeAreaFor geom 1
                     edge = if direction == "vertical" then rectX area + rectW area else rectY area + rectH area
                     expected = fromSp Pt (edge - slot) - fromSp Pt (pgLinePitch geom) / 2
                     actual = if direction == "vertical" then ptToRational x + ptToRational w / 2 else ptToRational y + ptToRational h / 2
                 assertBool (show (actual, expected)) (abs (actual - expected) < 1 / 10000)
               other -> assertFailure (show other)
             other -> assertFailure (show other)
       | mode <- ["grid", "free"],
         direction <- ["horizontal", "vertical"]
       ]
    <> [ testCase ("root ADR 0398 I7: an impossible empty-column separator hold is an error in " <> T.unpack mode) $ do
           let base = replaceIn "lines = 30" (if mode == "grid" then "lines = 1" else "lines = 2") horizontalStyle
               style = replaceIn "[page.grid]" ("[page.grid]\nalignment = \"" <> mode <> "\"") base <> "\n[separators.default]\nkind = \"text\"\ntext = \"*\"\n"
           (errors, result) <- buildMiniErrors fakeProvider True style "lead\n---\n後。\n" []
           let failed = filter ((== DiagnosticCode "G07134") . diagCode) errors
           map (spanStart . diagSpan) failed @?= [5]
           assertBool "no PDF on impossible separator hold" (case result of Nothing -> True; Just _ -> False)
       | mode <- ["grid", "free"]
       ]
    <> [ testCase ("root ADR 0398 I7: separator hold respects the document end and explicit break in " <> T.unpack mode) $ do
           let base = replaceIn "lines = 30" (if mode == "grid" then "lines = 1" else "lines = 2") horizontalStyle
               style = replaceIn "[page.grid]" ("[page.grid]\nalignment = \"" <> mode <> "\"") base <> "\n[separators.default]\nkind = \"text\"\ntext = \"*\"\nspace-after = 2\n"
           (_, ending) <- layoutOk style "---\n" []
           map (length . poSlots) (plPages ending) @?= [1]
           (_, broken) <- layoutOk style "---\n@page-break\n後。\n" []
           map (length . poSlots) (plPages broken) @?= [1, 1]
       | mode <- ["grid", "free"]
       ]
    <> [ testCase ("root ADR 0398 I7: separator and following line fit an exact empty column in " <> T.unpack mode) $ do
           let base = replaceIn "font-size = \"10pt\"" "font-size = \"15pt\"" (replaceIn "lines = 30" "lines = 2" horizontalStyle)
               style = replaceIn "[page.grid]" ("[page.grid]\nalignment = \"" <> mode <> "\"") base <> "\n[separators.default]\nkind = \"text\"\ntext = \"*\"\n"
           (_, layout) <- layoutOk style "---\n後。\n" []
           map (map (fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0, 15]]
       | mode <- ["grid", "free"]
       ]
    <> [ testCase ("root ADR 0398 I7: consecutive visible separators move as one chain in " <> T.unpack mode) $ do
           let base = replaceIn "font-size = \"10pt\"" "font-size = \"15pt\"" (replaceIn "lines = 30" "lines = 3" horizontalStyle)
               style = replaceIn "[page.grid]" ("[page.grid]\nalignment = \"" <> mode <> "\"") base <> "\n[separators.default]\nkind = \"text\"\ntext = \"*\"\n"
           (_, layout) <- layoutOk style "前。\n---\n---\n後。\n" []
           map (map (fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0], [0, 15, 30]]
       | mode <- ["grid", "free"]
       ]
    <> [ testCase ("root ADR 0398 I7: a separator hold over need-lines moves to an empty column that fits it in " <> T.unpack mode) $ do
           let base = replaceIn "font-size = \"10pt\"" "font-size = \"15pt\"" (replaceIn "lines = 30" "lines = 3" horizontalStyle)
               style = replaceIn "[page.grid]" ("[page.grid]\nalignment = \"" <> mode <> "\"") base <> "\n[separators.default]\nkind = \"text\"\ntext = \"*\"\n"
           (_, layout) <- layoutOk style "前。\n---\n@need-lines 2\n後。\n" []
           map (map (fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0], [0, 15]]
       | mode <- ["grid", "free"]
       ]
    <> [ testCase ("root ADR 0398 I7: a separator hold over need-lines that no empty column fits is an error in " <> T.unpack mode <> " with " <> show need <> " lines needed") $ do
           let base = replaceIn "font-size = \"10pt\"" "font-size = \"15pt\"" (replaceIn "lines = 30" ("lines = " <> lines') horizontalStyle)
               style = replaceIn "[page.grid]" ("[page.grid]\nalignment = \"" <> mode <> "\"") base <> "\n[separators.default]\nkind = \"text\"\ntext = \"*\"\n"
           (errors, result) <- buildMiniErrors fakeProvider True style ("lead\n---\n@need-lines " <> T.pack (show need) <> "\n後。\n") []
           map (spanStart . diagSpan) (filter ((== DiagnosticCode "G07134") . diagCode) errors) @?= [5]
           assertBool "no PDF on impossible separator hold" (case result of Nothing -> True; Just _ -> False)
       | mode <- ["grid", "free"],
         (lines', need) <- [("2", 2 :: Int), ("3", 5)]
       ]
    <> [ testCase ("root ADR 0398 I7: a separator hold over need-lines counts the space after the separator in " <> T.unpack mode) $ do
           let base = replaceIn "font-size = \"10pt\"" "font-size = \"15pt\"" (replaceIn "lines = 30" "lines = 4" horizontalStyle)
               style = replaceIn "[page.grid]" ("[page.grid]\nalignment = \"" <> mode <> "\"") base <> "\n[separators.default]\nkind = \"text\"\ntext = \"*\"\nspace-after = 1\n"
           (_, layout) <- layoutOk style "前。\n\n中。\n---\n@need-lines 2\n後。\n" []
           map (map (fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0, 15], [0, 30]]
       | mode <- ["grid", "free"]
       ]
    <> [ testCase ("root ADR 0398 I7: the need-lines asked for before a separator hold reports nothing of its own in " <> T.unpack mode) $ do
           let base = replaceIn "font-size = \"10pt\"" "font-size = \"15pt\"" (replaceIn "lines = 30" "lines = 3" horizontalStyle)
               style = replaceIn "[page.grid]" ("[page.grid]\nalignment = \"" <> mode <> "\"") base <> "\n[separators.default]\nkind = \"text\"\ntext = \"*\"\n"
           (_, layout) <- layoutOk style "@page-lines -1\n前。\n---\n@need-lines 2\n後。\n" []
           [(diagCode d, diagMessage d, spanStart (diagSpan d)) | d <- plNotices layout] @?= []
           map (map (fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0], [0, 15]]
       | mode <- ["grid", "free"]
       ]
    -- a paragraph of three lines, which the widow and orphan rules keep whole
    <> [ testCase ("root ADR 0398 I7: a separator hold goes with what a no-break keeps after the next block in " <> T.unpack mode) $ do
           (_, layout) <- layoutOk (heldStyle mode 5 "") ("前。\n---\n中。\n@no-page-break\n" <> threeLines <> "\n") []
           [(diagCode d, spanStart (diagSpan d)) | d <- plNotices layout] @?= []
           map (map ((/ 15) . fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0], [0, 1, 2, 3, 4]]
       | mode <- ["grid", "free"]
       ]
    <> [ testCase ("root ADR 0398 I7: a separator hold goes with what a keep-with-next keeps after the next block in " <> T.unpack mode) $ do
           (_, layout) <- layoutOk (heldStyle mode 5 leadStyle) ("前。\n---\n@style lead\n中。\n\n" <> threeLines <> "\n") []
           [(diagCode d, spanStart (diagSpan d)) | d <- plNotices layout] @?= []
           map (map ((/ 15) . fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0], [0, 1, 2, 3, 4]]
       | mode <- ["grid", "free"]
       ]
    <> [ testCase ("root ADR 0398 I7: a separator hold stays with the next block when what the no-break keeps fits no column with it in " <> T.unpack mode) $ do
           (_, layout) <- layoutOk (heldStyle mode 4 "") ("前。\n---\n中。\n@no-page-break\n" <> threeLines <> "\n") []
           -- only the no-break written is reported, at its position
           [(diagCode d, spanStart (diagSpan d)) | d <- plNotices layout] @?= [(DiagnosticCode "G07037", 18)]
           map (map ((/ 15) . fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0], [0, 1], [0, 1, 2]]
       | mode <- ["grid", "free"]
       ]
    <> [ testCase ("root ADR 0398 I7: a separator hold stays with the next block when what the keep-with-next keeps fits no column with it in " <> T.unpack mode) $ do
           (_, layout) <- layoutOk (heldStyle mode 4 leadStyle) ("前。\n---\n@style lead\n中。\n\n" <> threeLines <> "\n") []
           [(diagCode d, spanStart (diagSpan d)) | d <- plNotices layout] @?= [(DiagnosticCode "G07111", leadAt)]
           map (map ((/ 15) . fromSp Pt . fst) . poSlots) (plPages layout) @?= [[0], [0, 1], [0, 1, 2]]
       | mode <- ["grid", "free"]
       ]
    <> [ testCase ("root ADR 0398 I7: a separator hold before a no-break that no empty column fits is an error in " <> T.unpack mode) $ do
           (errors, result) <- buildMiniErrors fakeProvider True (heldStyle mode 2 "" <> "space-after = 1\n") "---\n中。\n@no-page-break\n後。\n" []
           [(diagCode d, spanStart (diagSpan d)) | d <- errors] @?= [(DiagnosticCode "G07134", 0)]
           assertBool "no PDF on impossible separator hold" (case result of Nothing -> True; Just _ -> False)
       | mode <- ["grid", "free"]
       ]
  where
    threeLines = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひ。"
    leadStyle = "\n[paragraph-styles.lead]\nkeep-with-next = 1\n"
    -- the paragraph of the style lead
    leadAt = 23
    heldStyle mode lines' extra =
      let base = replaceIn "font-size = \"10pt\"" "font-size = \"15pt\"" (replaceIn "lines = 30" ("lines = " <> T.pack (show (lines' :: Int))) horizontalStyle)
       in replaceIn "[page.grid]" ("[page.grid]\nalignment = \"" <> mode <> "\"") base <> extra <> "\n[separators.default]\nkind = \"text\"\ntext = \"*\"\n"
