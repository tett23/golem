-- | The alignment, the spaces before and after, and the end indent of paragraph styles (docs/adr/0189).
module AlignSpaceSpec (alignSpaceTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Golem.Driver
import Golem.Driver.Pdf (PdfLayout (..), PlacedFigure (..), SetLine (..))
import Golem.Layout.KnuthPlass (Line (..))
import Golem.Layout.Paginate (PageOut (..), Slotted (..))
import Golem.Length (Sp (..))
import Golem.Project.Style (dimToSp, parseDim)
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | The grid lines of the lines of each page.
slotsOf :: BS.ByteString -> T.Text -> IO [[Int]]
slotsOf style src = do
  (_, pl) <- layoutOk style src []
  pure (map (map fst . poSlots) (plPages pl))

-- | horizontalStyle with paragraph styles.
styled :: BS.ByteString -> BS.ByteString
styled extra = horizontalStyle <> "\n" <> extra

fs :: Sp
fs = 655360

-- | The indents of the lines of each page: (page number, indents).
indentsByPage :: PdfLayout -> [(Int, [Sp])]
indentsByPage pl = [(poNumber p, [slIndent sl | (_, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines pl)]]) | p <- plPages pl]

alignSpaceTests :: [TestTree]
alignSpaceTests =
  [ testCase "PDF: paragraphs of the same style are apart by space-between only" $ do
      let style = styled "[paragraph-styles.quote]\nspace-before = 2\nspace-after = 3\nspace-between = 1\n"
      slotsOf style "@style quote\nあ\n\n@style quote\nい\n" >>= (@?= [[0, 2]])
      slotsOf (styled "[paragraph-styles.quote]\nspace-before = 2\nspace-after = 3\n") "@style quote\nあ\n\n@style quote\nい\n" >>= (@?= [[0, 1]]),
    testCase "PDF: between paragraphs of different styles, the greater of the space after and the space before" $ do
      let style = styled "[paragraph-styles.a]\nspace-after = 2\n\n[paragraph-styles.b]\nspace-before = 1\n\n[paragraph-styles.c]\nspace-before = 3\n"
      slotsOf style "@style a\nあ\n\n@style b\nい\n" >>= (@?= [[0, 3]])
      slotsOf style "@style a\nあ\n\n@style c\nい\n" >>= (@?= [[0, 4]])
      slotsOf style "あ\n\n@style b\nい\n\nう\n" >>= (@?= [[0, 2, 3]])
      slotsOf style "@style a\nあ\n\nい\n" >>= (@?= [[0, 3]]),
    testCase "PDF: a block that is not a paragraph counts 0" $ do
      let style = styled "[paragraph-styles.quote]\nspace-before = 2\nspace-after = 1\n"
      slotsOf style "@style quote\nあ\n\n- 項目\n" >>= (@?= [[0, 2]])
      slotsOf style "- 項目\n\n@style quote\nあ\n" >>= (@?= [[0, 3]]),
    testCase "PDF: a blank line between two paragraphs takes the place of their spaces" $ do
      let style = styled "[paragraph-styles.quote]\nspace-before = 2\nspace-after = 2\n"
      slotsOf style "あ\n\n@blank-line\n\n@style quote\nい\n\n@blank-line\n\nう\n" >>= (@?= [[0, 2, 4]]),
    testCase "PDF: the space before at the top of a column is dropped, with no diagnostic" $ do
      (_, pl) <- layoutOk (styled "[paragraph-styles.quote]\nspace-before = 2\n") "@style quote\nあ\n" []
      map (map fst . poSlots) (plPages pl) @?= [[0]]
      plNotices pl @?= [],
    testCase "PDF: the space after at the end of a column is dropped at the top of the next" $ do
      let style = fiveLines <> "\n[paragraph-styles.quote]\nspace-after = 2\n"
      (_, pl) <- layoutOk style "あ\n\nい\n\nう\n\nえ\n\n@style quote\nお\n\nか\n" []
      map (map fst . poSlots) (plPages pl) @?= [[0, 1, 2, 3, 4], [0]]
      plNotices pl @?= [],
    testCase "PDF: a paragraph that keeps its lines has its spaces before the first line and after the last" $
      slotsOf (styled "[paragraph-styles.poem]\nline-breaks = \"keep\"\nspace-before = 1\nspace-after = 2\n") "あ\n\n@style poem\nい\nろ\nは\n\nう\n" >>= (@?= [[0, 2, 3, 4, 7]]),
    testCase "PDF: the spaces of a paragraph with rules are outside the area of its rules" $ do
      let rule = "rule-before = { weight = \"0.5pt\", space-before = \"3pt\", space-after = \"2pt\" }\n"
      plain <- slotsOf (styled ("[paragraph-styles.sec]\n" <> rule)) "前。\n\n@style sec\n節。\n\n後。\n"
      spaced <- slotsOf (styled ("[paragraph-styles.sec]\n" <> rule <> "space-before = 2\nspace-after = 1\n")) "前。\n\n@style sec\n節。\n\n後。\n"
      case (plain, spaced) of
        ([[a, b, c]], [[a', b', c']]) -> do
          a' @?= a
          b' - b @?= 2
          c' - c @?= 3
        other -> assertFailure (show other),
    testCase "PDF: the spaces are not in list items nor in definitions" $ do
      let style = styled "[paragraph-styles.quote]\nspace-before = 2\nspace-after = 2\n"
      slotsOf style "- 項目\n\n  @style quote\n  あ\n" >>= (@?= [[0, 1]])
      slotsOf style "= 用語\n  @style quote\n  説明。\n\n  @style body\n  説明。\n" >>= (@?= [[0, 1, 2]]),
    testCase "PDF: the line lengths of a paragraph with end-indent" $ do
      (_, ls) <- verseLines (horizontal30 "\n[paragraph-styles.quote]\nindent = \"2zw\"\nfirst-line-indent = \"1zw\"\nend-indent = \"3zw\"\n") ("@style quote\n" <> T.replicate 45 "あ" <> "\n")
      map fst ls @?= [24 * fs, 25 * fs]
      map snd ls @?= [3 * fs, 2 * fs],
    testCase "PDF: left, center and right in the area left by the indents" $ do
      let style a = horizontal30 ("\n[paragraph-styles.quote]\nindent = \"2zw\"\nend-indent = \"4zw\"\nalign = \"" <> a <> "\"\n")
      forM_ [("left", 2), ("center", 13), ("right", 24), ("left-justified", 2), ("center-justified", 13), ("right-justified", 24)] $ \(a, at) -> do
        (_, ls) <- verseLines (style a) "@style quote\nあい\n"
        ls @?= [(24 * fs, at * fs)],
    testCase "PDF: in vertical writing left is the top and right the bottom" $ do
      let size = maybe 0 (dimToSp 0) (parseDim "13Q")
      forM_ [("left", 0), ("right", 40)] $ \(a, at) -> do
        (_, ls) <- verseLines (pdfStyle <> "\n[paragraph-styles.quote]\nalign = \"" <> a <> "\"\n") "@style quote\nあい\n"
        ls @?= [(42 * size, at * size)],
    testCase "PDF: the justified values set the lines but the last as left-justified" $ do
      let src = "@style quote\n" <> T.replicate 45 "あ" <> "\n"
          style a = horizontal30 ("\n[paragraph-styles.quote]\nalign = \"" <> a <> "\"\n")
      (_, base) <- verseLines (style "left-justified") src
      (_, centred) <- verseLines (style "center-justified") src
      (_, right) <- verseLines (style "right-justified") src
      (_, full) <- verseLines (style "fully-justified") src
      base @?= [(30 * fs, 0), (30 * fs, 0)]
      centred @?= [(30 * fs, 0), (30 * fs, Sp (unSp (15 * fs) `div` 2))]
      right @?= [(30 * fs, 0), (30 * fs, 15 * fs)]
      full @?= base,
    testCase "PDF: a paragraph that keeps its lines aligns each line" $ do
      (_, ls) <- verseLines (horizontal30 "\n[paragraph-styles.poem]\nline-breaks = \"keep\"\nalign = \"right\"\n") "@style poem\nあ\nあい\n"
      ls @?= [(30 * fs, 29 * fs), (30 * fs, 28 * fs)],
    testCase "PDF: G07025 counts end-indent" $ do
      let style e = replaceIn "characters = 12" "characters = 10" horizontalStyle <> fakeBody <> "\n[paragraph-styles.quote]\nend-indent = \"" <> e <> "\"\n"
      ok <- buildMarksFilesWith "本文。\n" (\o -> o {optCheckOnly = True}) (Just (style "2zw")) fakeFontFiles
      map diagCode (bErrors ok) @?= []
      over <- buildMarksFilesWith "本文。\n" (\o -> o {optCheckOnly = True}) (Just (style "3zw")) fakeFontFiles
      map diagMessage (bErrors over) @?= ["段落スタイルの字下げが大きすぎます。行長を段落の文字の大きさの 8 字分以上残してください: quote"],
    testCase "PDF: towards-spine and away-from-spine go to the side of the spine of each page" $
      forM_ [(False, "towards-spine", [0, 11 * fs]), (False, "away-from-spine", [11 * fs, 0]), (True, "towards-spine", [11 * fs, 0]), (True, "away-from-spine", [0, 11 * fs])] $ \(right, a, sides) -> do
        let page = if right then replaceIn "binding = \"left\"" "binding = \"right\"" fiveLines else fiveLines
            style v = page <> "\n[paragraph-styles.quote]\nalign = \"" <> v <> "\"\n"
            src = "@style quote\n" <> T.intercalate "\\\n" (replicate 7 "あ") <> "\n"
        (_, pl) <- layoutOk (style a) src []
        (_, left) <- layoutOk (style "left") src []
        let byPage = indentsByPage pl
        map fst byPage @?= [1, 2]
        [nub' is | (_, is) <- byPage] @?= map pure sides
        map (lineItems . slLine) (Map.elems (plLines pl)) @?= map (lineItems . slLine) (Map.elems (plLines left)),
    testCase "PDF: the keys do not apply to list items, captions and footnotes" $ do
      img <- tinyImage
      let src = "- 項目[note: 注。]\n\n" <> wrappedFigure
          wrappedFigure = "@figure images/tiny.jpg alt=\"t\"\n  キャプション。\n"
          style extra = horizontal24 <> "\n[paragraph-styles.body]\n" <> extra
      (_, plain) <- layoutOk (style "") src img
      (_, keyed) <- layoutOk (style "align = \"center\"\nend-indent = \"2zw\"\nspace-before = 1\nspace-after = 1\n") src img
      [(slIndent sl, slLine sl, slNotes sl) | sl <- Map.elems (plLines keyed)] @?= [(slIndent sl, slLine sl, slNotes sl) | sl <- Map.elems (plLines plain)]
      map pfCaption (Map.elems (plFigures keyed)) @?= map pfCaption (Map.elems (plFigures plain)),
    testCase "HTML: the CSS of each align, and the spine of the first page" $ do
      let table =
            [ ("left", "text-align: start"),
              ("center", "text-align: center"),
              ("right", "text-align: end"),
              ("center-justified", "text-align: justify; text-align-last: center"),
              ("right-justified", "text-align: justify; text-align-last: end"),
              ("fully-justified", "text-align: justify; text-align-last: justify")
            ]
      forM_ table $ \(v, decls) -> do
        (_, css) <- htmlMini (styled ("[paragraph-styles.quote]\nalign = \"" <> v <> "\"\n")) "@style quote\nあ\n"
        assertBool (T.unpack css) (("p.ps-quote { " <> decls <> "; }") `T.isInfixOf` css)
      forM_ [(False, "towards-spine", "left"), (False, "away-from-spine", "right"), (True, "towards-spine", "right"), (True, "away-from-spine", "left")] $ \(right, v, side) -> do
        let page = if right then replaceIn "binding = \"left\"" "binding = \"right\"" horizontalStyle else horizontalStyle
        (_, css) <- htmlMini (page <> "\n[paragraph-styles.quote]\nalign = \"" <> v <> "\"\n") "@style quote\nあ\n"
        assertBool (T.unpack css) (("p.ps-quote { text-align: " <> side <> "; }") `T.isInfixOf` css),
    testCase "HTML: end-indent and the spaces, and nothing for the defaults" $ do
      (_, css) <- htmlMini (styled "[paragraph-styles.quote]\nend-indent = \"2zw\"\nspace-before = 1\nspace-after = 2\n") "あ\n\n@style quote\nい\n\nう\n"
      forM_ ["p.ps-quote { padding-inline-end: 2em; }", "p.ps-quote { margin-block-start: 1em; }", "p.ps-quote + :not(.ps-quote):not(.blank-line) { margin-block-start: 2em; }", "div.blank-line + p.ps-quote { margin-block-start: 0; }"] $ \r ->
        assertBool (T.unpack r) (r `T.isInfixOf` css)
      (_, plain) <- htmlMini horizontalStyle "あ\n"
      forM_ ["text-align: justify", "text-align: start", "padding-inline-end", "blank-line +"] $ \r ->
        assertBool (T.unpack r) (not (r `T.isInfixOf` plain))
  ]
  where
    nub' = foldr (\x acc -> if x `elem` acc then acc else x : acc) []
