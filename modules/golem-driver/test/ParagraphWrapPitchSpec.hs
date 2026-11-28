module ParagraphWrapPitchSpec (paragraphWrapPitchTests) where

import Data.Char (isSpace)
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Layout.KnuthPlass (Line (..))
import Golem.Layout.Paginate (PageOutAt (..), Slotted (..))
import Golem.Length (Sp (..))
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..))
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support hiding (pt)
import System.Timeout (timeout)
import Test.Tasty
import Test.Tasty.HUnit

pt :: Integer -> Sp
pt n = Sp (65536 * n)

paragraphWrapPitchTests :: TestTree
paragraphWrapPitchTests =
  testGroup
    "root ADR 0397 multi-paragraph wrapping"
    [ testGroup
        "root ADR 0483 forced prefixes"
        [ testCase ("root ADR 0483 I1, I3: " <> name <> ", keep-last=" <> show lastKeep) $ do
            imageFiles <- tinyImage
            let style =
                  replaceIn "lines = 30" "lines = 4" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle)))
                    <> TE.encodeUtf8 ("\n[paragraph-styles.stuck]\nkeep-first-lines = 2\nkeep-last-lines = " <> T.pack (show lastKeep) <> "\n")
                source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=3zw\n\n@style stuck\n" <> body <> "\n"
            result <- timeout 5000000 $ do
              (_, layout) <- layoutOk style source imageFiles
              let text = T.concat (lineTexts layout)
              T.filter (not . isSpace) text @?= T.filter (not . isSpace) body
              let placed = [ident | page <- plPages layout, (_, SLine ident) <- poSlots page]
              placed @?= nub placed
              length placed @?= Map.size (plLines layout)
              assertBool "placed rows exist" (not (null (plPages layout)))
            assertBool "forced placement finishes without repeating the same retry" (case result of Just () -> True; Nothing -> False)
        | lastKeep <- [2 :: Int, 4],
          (name, body) <- [("49 kana", T.replicate 49 "あ"), ("ordered kana", T.take 49 (T.replicate 10 "あいうえお")), ("discardable glue", T.intercalate " " (replicate 25 "あい"))]
        ],
      testGroup
        "actual columns after wrapping"
        [ testCase ("root ADR 0397 I8 I10: " <> mode <> " keeps a moved paragraph whole and restores its full width") $ do
            imageFiles <- tinyImage
            let style =
                  replaceIn
                    "writing-mode = \"horizontal\""
                    ("writing-mode = \"" <> T.pack mode <> "\"")
                    (replaceIn "characters = 12" "characters = 20" (replaceIn "lines = 30" "lines = 12" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle)))))
                    <> "\n[paragraph-styles.dialogue]\nline-pitch = \"18pt\"\nkeep-first-lines = 1\nkeep-last-lines = 1\n[paragraph-styles.stage]\nsize = \"6pt\"\nindent = \"2zw\"\nline-pitch = \"12pt\"\nspace-before = \"4pt\"\n"
                source = "# 題\n\n@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=4zw\n\n@style dialogue\n登場人物の台詞です。折り返した行の間隔と、次の台詞への間隔を別にします。[note: 脚注の本文です。台詞の行送りを変えても、注の内部の行送りは変えません。]\n\n@style stage\nここは読まないト書きです。二字下がった行で、本文より短い行送りを使います。\n"
            (_, layout) <- layoutOk style source imageFiles
            let stageIds = [ident | (ident, sl) <- Map.toList (plLines layout), slSize sl == pt 6]
                stagePages = [poNumber page | page <- plPages layout, (_, SLine ident) <- poSlots page, ident `elem` stageIds]
                figurePages = [poNumber page | page <- plPages layout, (_, SWrapped _) <- poSlots page]
            assertBool "wrapped figure is present" (not (null figurePages))
            assertBool "multiple stage rows" (length stageIds >= 2)
            assertBool "stage paragraph is after the figure's page" (not (null stagePages) && all (> maximum figurePages) stagePages)
            [lineTarget (slLine sl) | ident <- stageIds, Just sl <- [Map.lookup ident (plLines layout)]] @?= replicate (length stageIds) (pt 188)
            [slIndent sl | ident <- stageIds, Just sl <- [Map.lookup ident (plLines layout)]] @?= replicate (length stageIds) (pt 12)
        | mode <- ["horizontal", "vertical"]
        ],
      testCase "root ADR 0397 I8 I10: keep-with-next trials the following paragraph at its actual cursor width" $ do
        imageFiles <- tinyImage
        let style =
              replaceIn "lines = 30" "lines = 6" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle)))
                <> "\n[paragraph-styles.body]\nkeep-first-lines = 1\nkeep-last-lines = 1\n[paragraph-styles.lead]\nsize = \"6pt\"\nline-pitch = \"15pt\"\nkeep-with-next = 1\n[paragraph-styles.following]\nsize = \"9pt\"\nline-pitch = \"30pt\"\nkeep-first-lines = 1\nkeep-last-lines = 1\n"
            source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n" <> T.replicate 36 "あ" <> "\n\n@style lead\n前\n\n@style following\n後\n"
        (_, layout) <- layoutOk style source imageFiles
        let pagesAt size = [poNumber page | page <- plPages layout, (_, SLine ident) <- poSlots page, Just set <- [Map.lookup ident (plLines layout)], slSize set == size]
        assertBool "the lead exists" (not (null (pagesAt (pt 6))))
        pagesAt (pt 6) @?= take 1 (pagesAt (pt 9))
        [diagCode d | d <- plNotices layout, diagCode d == DiagnosticCode "G07111"] @?= [],
      testCase "root ADR 0397 I8 I10: stanza keeps count original verse lines after a wrapped figure" $ do
        imageFiles <- tinyImage
        let style =
              replaceIn "lines = 30" "lines = 6" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle)))
                <> "\n[paragraph-styles.body]\nkeep-first-lines = 1\nkeep-last-lines = 1\n[paragraph-styles.verse]\nsize = \"9pt\"\nline-pitch = \"15pt\"\nline-breaks = \"keep\"\nkeep-first-lines = 2\nkeep-last-lines = 2\n"
            source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n" <> T.replicate 12 "あ" <> "\n\n@style verse\n" <> T.unlines (replicate 4 (T.replicate 20 "い"))
        (_, layout) <- layoutOk style source imageFiles
        let versePages = [poNumber page | page <- plPages layout, (_, SLine ident) <- poSlots page, Just set <- [Map.lookup ident (plLines layout)], slSize set == pt 9]
            bodyPages = [poNumber page | page <- plPages layout, (_, SLine ident) <- poSlots page, Just set <- [Map.lookup ident (plLines layout)], slSize set == pt 10]
        assertBool "verse rows exist" (length versePages >= 4)
        case versePages of
          firstVersePage : _ -> assertBool "the first two verses move together" (firstVersePage > maximum bodyPages)
          [] -> assertFailure "no verse was placed",
      testCase "root ADR 0397 I10: a need-lines control preserves the active figure exclusion" $ do
        imageFiles <- tinyImage
        let style = TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle))
            figure = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n"
            paragraph = T.replicate 48 "あ" <> "\n"
        (_, baseline) <- layoutOk style (figure <> paragraph) imageFiles
        (_, controlled) <- layoutOk style (figure <> "@need-lines 1\n\n" <> paragraph) imageFiles
        let shape layout = [(lineTarget (slLine set), slIndent set) | set <- Map.elems (plLines layout)]
        shape controlled @?= shape baseline
        map poSlots (plPages controlled) @?= map poSlots (plPages baseline),
      testGroup
        "explicit no-page-break after wrapping"
        [ testCase ("root ADR 0397 I8 I10: " <> T.unpack control <> " retains the prior tail") $ do
            imageFiles <- tinyImage
            let style =
                  replaceIn "lines = 30" "lines = 6" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle)))
                    <> "\n[paragraph-styles.body]\nkeep-first-lines = 1\nkeep-last-lines = 1\n[paragraph-styles.lead]\nsize = \"6pt\"\nline-pitch = \"15pt\"\n[paragraph-styles.following]\nsize = \"9pt\"\nline-pitch = \"15pt\"\nkeep-first-lines = 1\nkeep-last-lines = 1\n"
                source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n" <> T.replicate 36 "あ" <> "\n\n@style lead\n前\n\n" <> control <> "\n\n@style following\n" <> T.replicate 45 "い" <> "\n"
            (_, layout) <- layoutOk style source imageFiles
            let pagesAt size = [poNumber page | page <- plPages layout, (_, SLine ident) <- poSlots page, Just set <- [Map.lookup ident (plLines layout)], slSize set == size]
            assertBool "the lead exists" (not (null (pagesAt (pt 6))))
            pagesAt (pt 6) @?= take 1 (pagesAt (pt 9))
        | control <- ["@no-page-break", "@no-page-break 2"]
        ],
      testCase "root ADR 0397 I8 I10: a chain of kept paragraphs uses actual widths throughout" $ do
        imageFiles <- tinyImage
        let style =
              replaceIn "lines = 30" "lines = 6" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle)))
                <> "\n[paragraph-styles.body]\nkeep-first-lines = 1\nkeep-last-lines = 1\n[paragraph-styles.lead]\nsize = \"6pt\"\nline-pitch = \"15pt\"\nkeep-with-next = 1\n[paragraph-styles.middle]\nsize = \"8pt\"\nline-pitch = \"30pt\"\nkeep-with-next = 1\n[paragraph-styles.following]\nsize = \"9pt\"\nline-pitch = \"30pt\"\nkeep-first-lines = 1\nkeep-last-lines = 1\n"
            source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n" <> T.replicate 12 "あ" <> "\n\n@style lead\n前\n\n@style middle\n中\n\n@style following\n後\n"
        (_, layout) <- layoutOk style source imageFiles
        let pagesAt size = [poNumber page | page <- plPages layout, (_, SLine ident) <- poSlots page, Just set <- [Map.lookup ident (plLines layout)], slSize set == size]
        assertBool "the lead exists" (not (null (pagesAt (pt 6))))
        pagesAt (pt 6) @?= pagesAt (pt 8)
        pagesAt (pt 6) @?= pagesAt (pt 9),
      testCase "root ADR 0397 I9 I10: committed source prefixes carry each note, label and index mark once" $ do
        imageFiles <- tinyImage
        let style =
              replaceIn "lines = 30" "lines = 6" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle)))
                <> "\n[paragraph-styles.body]\nkeep-first-lines = 1\nkeep-last-lines = 1\n"
            source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n@label p\n" <> T.replicate 80 "あ" <> "[index reading=き: 記][note: 注]" <> T.replicate 80 "あ" <> "\n"
        (_, layout) <- layoutOk style source imageFiles
        let notes = [(key, rows) | set <- Map.elems (plLines layout), (key, rows) <- slNotes set]
            chunks = [(key, count) | page <- plPages layout, (key, _, count) <- poFootnotes page]
        concatMap poLabels (plPages layout) @?= ["p"]
        length (concatMap poMarks (plPages layout)) @?= 1
        length notes @?= 1
        sum (map snd chunks) @?= sum [length rows | (_, rows) <- notes]
        nub (map fst chunks) @?= map fst notes
        T.count "あ" (T.concat (lineTexts layout)) @?= 160,
      testCase "root ADR 0397 I8 I10: wider continuation rebreaks retain two final display rows" $ do
        imageFiles <- tinyImage
        let style = replaceIn "lines = 30" "lines = 6" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle)))
            source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=3zw\n  " <> T.replicate 4 "図" <> "\n\n" <> T.replicate 44 "あ" <> "\n"
        (_, layout) <- layoutOk style source imageFiles
        let counts = [length [() | (_, SLine _) <- poSlots page] | page <- plPages layout]
        counts @?= [3, 2]
        map (lineTarget . slLine) (Map.elems (plLines layout)) @?= replicate 3 (pt 80) <> replicate 2 (pt 120)
        [diagCode d | d <- plNotices layout, diagCode d == DiagnosticCode "G07113"] @?= [],
      testGroup
        "original source prefixes after wrapping"
        [ testCase ("root ADR 0397 I10: rebreak consumes " <> name <> " once") $ do
            imageFiles <- tinyImage
            let style =
                  replaceIn "lines = 30" "lines = 6" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle)))
                    <> "\n[paragraph-styles.body]\nkeep-first-lines = 1\nkeep-last-lines = 1\n"
                source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n" <> input <> "\n"
            (_, layout) <- layoutOk style source imageFiles
            let rows = [ident | page <- plPages layout, (_, SLine ident) <- poSlots page]
                compact = T.filter (not . isSpace)
            assertBool "paragraph spans physical pages" (length (nub [poNumber page | page <- plPages layout, not (null (poSlots page))]) >= 2)
            rows @?= nub rows
            length rows @?= Map.size (plLines layout)
            compact (T.concat (lineTexts layout)) @?= compact expected
        | let words' = ["word" <> T.pack (show n) <> "hyphenation" | n <- [1 :: Int .. 80]],
          let shyWords = [T.replace "hyphenation" "hy\xAD\&phenation" word | word <- words'],
          (name, input, expected) <-
            [ ("discardable glue", T.unwords words', T.concat words'),
              ("discretionary hyphens", "[lang en: " <> T.intercalate " " shyWords <> "]", T.concat words'),
              ("forced breaks", T.intercalate "\\\n" (map (T.unwords . take 12) (take 6 (iterate (drop 12) words'))), T.concat (take 72 words'))
            ]
        ],
      testCase "root ADR 0397 I10: a dimensional paragraph gap positions the next paragraph beside the figure" $ do
        imageFiles <- tinyImage
        let style =
              replaceIn "line-pitch = \"15pt\"" "line-pitch = \"10pt\"" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle)))
                <> "\n[paragraph-styles.body]\nline-pitch = \"10pt\"\nspace-between = \"12pt\"\n[figures]\nwrap-gap = \"0pt\"\n"
            source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\nあ\n\n" <> longPara 12
        (_, layout) <- layoutOk style source imageFiles
        length [sl | sl <- Map.elems (plLines layout), lineTarget (slLine sl) < pt 120] @?= 2
        let starts = [start | page <- plPages layout, (start, SLine _) <- poSlots page]
        take 2 starts @?= [pt 0, pt 22],
      testCase "root ADR 0397 I10: an initial paragraph gap is counted once beside the figure" $ do
        imageFiles <- tinyImage
        let style =
              replaceIn "line-pitch = \"15pt\"" "line-pitch = \"10pt\"" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle)))
                <> "\n[paragraph-styles.body]\nline-pitch = \"10pt\"\nspace-before = \"12pt\"\n[figures]\nwrap-gap = \"0pt\"\n"
            source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n" <> longPara 12 <> "い\n"
        (_, layout) <- layoutOk style source imageFiles
        let starts = [start | page <- plPages layout, (start, SLine _) <- poSlots page]
        take 3 starts @?= [pt 12, pt 22, pt 32]
        last starts - last (init starts) @?= pt 10,
      testCase "root ADR 0397 I13: free need-lines overflow reports lengths, retaining the requested line count" $ do
        let style =
              replaceIn "lines = 30" "lines = 5" (replaceIn "line-pitch = \"15pt\"" "line-pitch = \"10pt\"" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle))))
        (_, layout) <- layoutOk style "@need-lines 9\n\nあ\n" []
        [(diagCode d, diagMessage d) | d <- plNotices layout]
          @?= [(DiagnosticCode "G07037", "@need-lines 9 の長さ 90pt は段の長さ 50pt を超えます")],
      testCase "root ADR 0397 I13: heading exceeding adjusted free capacity reports dimensions" $ do
        let style =
              replaceIn "lines = 30" "lines = 5" (replaceIn "line-pitch = \"15pt\"" "line-pitch = \"20pt\"" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle))))
                <> "\n[headings.1]\nsize = \"1zw\"\nlines = 4\n"
        (_, layout) <- layoutOk style "@page-lines -1\n\n# 題\n" []
        let messages = [diagMessage d | d <- plNotices layout, diagCode d == DiagnosticCode "G07100"]
        assertBool (show (plNotices layout)) (any (\m -> "80pt" `T.isInfixOf` m && "70pt" `T.isInfixOf` m) messages),
      testCase "root ADR 0397 I10: wrapping uses the figure origin when its exclusion exactly fills the column" $ do
        imageFiles <- tinyImage
        let style =
              replaceIn "lines = 30" "lines = 2" (replaceIn "line-pitch = \"15pt\"" "line-pitch = \"20pt\"" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle))))
                <> "\n[figures]\nwrap-gap = \"0pt\"\n"
        (_, layout) <- layoutOk style "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n" imageFiles
        [(position, slot) | page <- plPages layout, (position, slot@SWrapped {}) <- poSlots page] @?= [(0, SWrapped 0)],
      testCase "root ADR 0397 I10: free wrapping exclusion overflow reports lengths" $ do
        imageFiles <- tinyImage
        let style =
              replaceIn "lines = 30" "lines = 2" (replaceIn "line-pitch = \"15pt\"" "line-pitch = \"10pt\"" (TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle))))
                <> "\n[figures]\nwrap-gap = \"0pt\"\n"
        result <- layoutMini style "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n" imageFiles
        case result of
          Left ds ->
            [(diagCode d, diagMessage d) | d <- ds]
              @?= [(DiagnosticCode "G07023", "回り込む図版の除外領域（長さ 30pt）が段の長さ 20pt を超えます")]
          Right _ -> assertFailure "overlong wrapping exclusion unexpectedly fitted"
    ]
