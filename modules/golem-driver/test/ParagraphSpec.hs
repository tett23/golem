module ParagraphSpec (verseTests, indentTests, listTests, separatorTests, hardBreakTests, akiTests, breakTests, pageControlTests, columnTests, inseparableTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (nub, sort, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Driver.Pdf (PdfLayout (..), SetLine (..))
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Look (..), Synthetic (..))
import Golem.Layout.Paginate (Flow (..), LineBox (..), PageOut (..), Slotted (..), paginate)
import Golem.LayoutSpec (PageGeometry (..), Rect (..), columnsFor, typeAreaFor)
import Golem.Pdf (spToPt)
import Golem.Project.Style (dimToSp, parseDim)
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

separatorTests :: [TestTree]
separatorTests =
  [ testCase "HTML: one newline separates paragraphs in the line style; a chapter entry keeps the blank-line style" $
      withSystemTempDirectory "golem-separator" $ \tmp -> do
        manifest <- TIO.readFile (fixture </> "manifest.toml")
        let rest = T.dropWhile (/= '\n') manifest
        TIO.writeFile (tmp </> "manifest.toml") ("chapters = [\"l.gm\", { file = \"b.gm\", paragraph-separator = \"blank-line\" }]\n" <> rest <> "\n[source]\nparagraph-separator = \"line\"\n")
        TIO.writeFile (tmp </> "l.gm") "一行目。\n二行目。\n三行目。\n"
        TIO.writeFile (tmp </> "b.gm") "前の行\n後の行\n"
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        l <- TIO.readFile (tmp </> "build/html/l.xhtml")
        assertBool (T.unpack l) ("<p>一行目。</p>\n<p>二行目。</p>\n<p>三行目。</p>" `T.isInfixOf` l)
        b <- TIO.readFile (tmp </> "build/html/b.xhtml")
        assertBool (T.unpack b) ("<p>前の行後の行</p>" `T.isInfixOf` b)
  ]

akiTests :: [TestTree]
akiTests =
  [ testCase "PDF: a paragraph is set with the aki set of its paragraph style" $ do
      let wide = TE.encodeUtf8 "\n[aki-sets.wide]\nrules = [{ before = \"kana\", after = \"kana\", optimum = \"全角\" }]\n\n[paragraph-styles.quote]\naki-set = \"wide\"\n"
          src = T.replicate 20 "あ" <> "\n\n@style quote\n  " <> T.replicate 20 "あ" <> "\n"
      (_, plain) <- verseLines (horizontal30 "\n[paragraph-styles.quote]\nspace-between = 0\n") src
      (_, styled) <- verseLines (horizontal30 wide) src
      length plain @?= 2
      length styled @?= 3
      (_, body) <- verseLines (horizontal30 (wide <> "\n[paragraph-styles.body]\naki-set = \"wide\"\n")) src
      length body @?= 4,
    testCase "HTML: [aki] is an empty span with a margin, between word joiners" $
      withVerseProject "" "a[aki 五分]b\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        assertBool (T.unpack page) ("<p>a&#x2060;<span class=\"aki\" style=\"margin-inline-start: 0.2em\"></span>&#x2060;b</p>" `T.isInfixOf` page),
    testCase "plain text: [aki] is as many ideographic spaces as its whole zw" $ do
      withVerseProject "" "a[aki 全角]b[aki 五分]c[aki 二分四分]d[aki 2zw]e[aki 3mm]f\n" $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        t <- TIO.readFile (tmp </> "build/text/horizontal/v.txt")
        t @?= "a\x3000\&bcd\x3000\x3000\&ef\n"
  ]

hardBreakTests :: [TestTree]
hardBreakTests =
  [ testCase "PDF: the line after a hard break gets no first-line indent" $ do
      let fs = 655360
      (flow, ls) <- verseLines (horizontal30 "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n") "東京都\\\n千代田区\n"
      map snd ls @?= [fs, 0]
      [length bs | FParagraph bs <- flow] @?= [2],
    testCase "PDF: a hard break in verse starts a verse line as before" $ do
      (_, withBreak) <- verseLines pdfStyle "@style verse\n  a\\\n  b\n"
      (_, plain) <- verseLines pdfStyle "@style verse\n  a\n  b\n"
      withBreak @?= plain,
    testCase "PDF: a paragraph of hard breaks is one paragraph for the widow and orphan rules" $ do
      (flow, ls) <- verseLines (horizontal30 "") "一行目\\\n二行目\\\n三行目\n"
      length ls @?= 3
      [length bs | FParagraph bs <- flow] @?= [3]
      -- one line left on a page: the paragraph moves whole rather than leave its first line alone
      case flow of
        [p@(FParagraph _)] -> map (map fst . poSlots) (paginate 1 4 [FParagraph [LineBox i [] [] [] 0 | i <- [100, 101, 102]], p]) @?= [[0, 1, 2], [0, 1, 2]]
        other -> assertFailure (show (length other)),
    testCase "HTML: a hard break is br inside the p; verse keeps its lines" $ do
      withVerseProject "" "a\\\nb\n\n- c\\\n  d\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        assertBool (T.unpack page) ("<p>a<br/>b</p>" `T.isInfixOf` page)
        assertBool (T.unpack page) ("<li>c<br/>d</li>" `T.isInfixOf` page)
        assertBool (T.unpack page) (not ("<span class=\"line\">" `T.isInfixOf` page))
      withVerseProject "" "@style verse\n  a\\\n  b\n" $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        assertBool (T.unpack page) ("<span class=\"line\">a</span>" `T.isInfixOf` page),
    testCase "plain text: a hard break is a newline" $
      withVerseProject "" "a\\\nb\n" $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        t <- TIO.readFile (tmp </> "build/text/horizontal/v.txt")
        t @?= "a\nb\n"
  ]

verseTests :: [TestTree]
verseTests =
  [ testCase "HTML: stanzas are p of the verse style, lines are span and br; the CSS hangs the lines" $
      withVerseProject "[paragraph-styles.verse]\nindent = \"3zw\"\nfirst-line-indent = \"-3zw\"\n" verseSource $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        assertBool
          (T.unpack page)
          ( "<p class=\"ps-verse\"><span class=\"line\">Full fathom five thy father lies;</span><br/>\n<span class=\"line\">Of his bones are coral made;</span></p>\n<p class=\"ps-verse\"><span class=\"line\">Nothing of him that doth fade,</span></p>\n"
              `T.isInfixOf` page
          )
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "line rule" (".line { display: block; }" `T.isInfixOf` css)
        assertBool "br rule" (".line + br { display: none; }" `T.isInfixOf` css)
        assertBool "hang" ("p.ps-verse { padding-inline-start: 3em; text-indent: -3em; }" `T.isInfixOf` css)
        assertBool "stanza gap" ("p.ps-verse + p.ps-verse { margin-block-start: 1em; }" `T.isInfixOf` css),
    testCase "HTML: no space rule when space-between is 0" $
      withVerseProject "[paragraph-styles.verse]\nspace-between = 0\nindent = \"10.5pt\"\n" verseSource $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "no stanza gap" (not ("p.ps-verse + p.ps-verse" `T.isInfixOf` css))
        assertBool "margin" ("p.ps-verse { margin-block: 0; }" `T.isInfixOf` css)
        assertBool "indent" ("p.ps-verse { padding-inline-start: 10.5pt; text-indent: -2em; }" `T.isInfixOf` css),
    testCase "plain text: lines on lines, stanzas separated by a blank line" $
      withVerseProject "" verseSource $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        t <- TIO.readFile (tmp </> "build/text/horizontal/v.txt")
        t @?= "Full fathom five thy father lies;\nOf his bones are coral made;\n\nNothing of him that doth fade,\n",
    testCase "PDF: a long line is broken and its continuation hangs" $ do
      let style = "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 30\nlines = 30\nline-pitch = \"15pt\"\ncolumns = 1\nposition = { top = \"18mm\", gutter = \"20mm\" }\n"
          fs = 655360
      (flow, ls) <- verseLines style ("@style verse\n  " <> T.replicate 45 "あ" <> "\n\n  い\n")
      ls @?= [(30 * fs, 0), (28 * fs, 2 * fs), (30 * fs, 0)]
      [length bs | FParagraph bs <- flow] @?= [2, 1]
      [n | FSpace n <- flow] @?= [1],
    testCase "PDF: the hang in vertical writing, and the space between stanzas from the style" $ do
      let fs = maybe 0 (dimToSp 0) (parseDim "13Q")
      (flow, ls) <- verseLines (pdfStyle <> "\n[paragraph-styles.verse]\nspace-between = 2\n") ("@style verse\n  " <> T.replicate 60 "あ" <> "\n\n  い\n")
      map snd ls @?= [0, 2 * fs, 0]
      [n | FSpace n <- flow] @?= [2],
    testCase "PDF: the attribute form and a label" $ do
      (flow, ls) <- verseLines pdfStyle "@label song\n@style verse\nあ\nい\n"
      length ls @?= 2
      [length bs | FParagraph bs <- flow] @?= [1, 1],
    testCase "PDF: a verse line takes the look of its inline elements" $ do
      (_, layout) <- layoutOk horizontalStyle "@style verse\n  前の[bold: 本文]後\n" []
      [bcText c | sl <- Map.elems (plLines layout), Box _ c <- lineItems (slLine sl), synBold (lkSynthetic (bcLook c))] @?= ["本", "文"]
  ]

indentTests :: [TestTree]
indentTests =
  [ testCase "PDF: the first line of a paragraph is indented by first-line-indent" $ do
      let fs = 655360
      (_, ls) <- verseLines (horizontal30 "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n") (T.replicate 45 "あ" <> "\n")
      ls @?= [(29 * fs, fs), (30 * fs, 0)],
    testCase "PDF: a hanging indent" $ do
      let fs = 655360
      (_, ls) <- verseLines (horizontal30 "\n[paragraph-styles.quote]\nindent = \"2zw\"\nfirst-line-indent = \"-2zw\"\n") ("@style quote\n" <> T.replicate 45 "あ" <> "\n")
      map snd ls @?= [0, 2 * fs]
      map fst ls @?= [30 * fs, 28 * fs],
    testCase "PDF: vertical, the first line starts a character lower" $ do
      let fs = maybe 0 (dimToSp 0) (parseDim "13Q")
          firstY pdf = do
            content <- BS.concat <$> inflateAll pdf
            case [dY d | d <- drawnGlyphs content, dGlyph d == fromEnum 'い'] of
              (y : _) -> pure (ptToRational y)
              [] -> assertFailure "no glyph"
      (_, ls) <- verseLines (pdfStyle <> "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n") (T.replicate 60 "あ" <> "\n")
      take 2 (map snd ls) @?= [fs, 0]
      a <- miniPdf fakeProvider True (pdfStyle <> "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n") "いろは\n" [] >>= firstY
      b <- miniPdf fakeProvider True pdfStyle "いろは\n" [] >>= firstY
      assertBool (show (a, b)) (abs ((b - a) - toRational fs / 65536) < 1 / 100),
    testCase "PDF: no indent in list items and the table of contents; indent in definitions" $ do
      let fs = 655360
          style = horizontal30 "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n"
      (_, items) <- verseLines style "- 項目\n- 項目\n"
      map snd items @?= [0, 0]
      (_, toc) <- verseLines style "@toc\n\n# 章\n"
      assertBool (show toc) (all ((== 0) . snd) toc)
      (_, defs) <- verseLines style "= 用語\n  説明の段落。\n"
      map snd defs @?= [0, fs],
    testCase "PDF: beside a wrap=start figure, the first line adds its indent to the exclusion" $ do
      img <- tinyImage
      (_, pl) <- layoutOk (horizontal24 <> "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n") (wrapped "start" "4zw" <> longPara 30) img
      (_, _, p, slot) <- theFigure pl
      take 2 (map (slIndent . snd) (linesFrom pl p slot)) @?= [60 * pt, 50 * pt],
    testCase "PDF: an indent that leaves less than 8 characters is G0725" $ do
      let style = replaceIn "characters = 12" "characters = 10" horizontalStyle <> "\n[paragraph-styles.body]\nindent = \"3zw\"\n"
      (errs, pdf) <- buildMini fakeProvider True style "本文。\n" []
      (nub errs, pdf) @?= ([DiagnosticCode "G0725"], Nothing),
    testCase "HTML: the indent of body and of verse, none in list items" $ do
      withVerseProject "[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n" "本文。\n" $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "body" ("p { padding-inline-start: 0em; text-indent: 1em; }" `T.isInfixOf` css)
        assertBool "list items" ("li p, li p[class] { padding-inline-start: 0; text-indent: 0; }" `T.isInfixOf` css)
      withVerseProject "" verseSource $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "verse" ("p.ps-verse { padding-inline-start: 2em; text-indent: -2em; }" `T.isInfixOf` css)
        assertBool "lines" (".line { display: block; }" `T.isInfixOf` css)
        assertBool "no body rule" (not ("\np { " `T.isInfixOf` css)),
    testCase "plain text: the first line starts with ideographic spaces" $ do
      let text style src = withVerseProject style src $ \tmp -> do
            _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
            TIO.readFile (tmp </> "build/text/horizontal/v.txt")
      text "[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n" "本文。\n\n- 項目\n" >>= (@?= "　本文。\n\n・項目\n")
      text "[paragraph-styles.body]\nfirst-line-indent = \"3mm\"\n" "本文。\n" >>= (@?= "本文。\n")
  ]

-- | The plain text of a one-file project, horizontal or vertical.
listText :: BS.ByteString -> T.Text -> FilePath -> IO T.Text
listText style src variant = withVerseProject style src $ \tmp -> do
  r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  TIO.readFile (tmp </> "build/text" </> variant </> "v.txt")

listTests :: [TestTree]
listTests =
  [ testCase "PDF: the marker hangs and the lines of an item start at the text" $ do
      (_, ls) <- verseLines horizontalStyle ("- " <> T.replicate 20 "あ" <> "\n")
      ls @?= [(120 * pt, 0), (110 * pt, 10 * pt)],
    testCase "PDF: the second paragraph of an item starts at the text" $ do
      (_, ls) <- verseLines horizontalStyle "- 一つ目の段落。\n  二つ目の段落。\n"
      map snd ls @?= [0, 10 * pt],
    testCase "PDF: a nested list starts at the text of the outer item" $ do
      (_, ls) <- verseLines horizontalStyle ("- 外\n  - " <> T.replicate 20 "あ" <> "\n")
      map snd ls @?= [0, 10 * pt, 20 * pt],
    testCase "PDF: the marker width of a numbered list is its widest number" $ do
      let items = T.concat (replicate 9 ("+ " <> T.replicate 16 "あ" <> "\n"))
      (_, ls) <- verseLines horizontalStyle items
      [ind | (k, (_, ind)) <- zip [0 :: Int ..] ls, odd k] @?= replicate 9 (20 * pt)
      (_, ls') <- verseLines horizontalStyle ("@number 100\n" <> items)
      [ind | (k, (_, ind)) <- zip [0 :: Int ..] ls', odd k] @?= replicate 9 (30 * pt),
    testCase "PDF: @number sets the numbers" $ do
      ts <- listPages horizontalStyle "+ 一\n@number 5\n+ 二\n+ 三\n"
      ts @?= ["1.一", "5.二", "6.三"],
    testCase "PDF: no glue or penalty between the marker and the text" $ do
      (_, pl) <- layoutOk horizontalStyle ("+ " <> T.replicate 20 "あ" <> "\n- い\n") []
      let firsts = [lineItems (slLine sl) | sl <- Map.elems (plLines pl)]
          beforeText = takeWhile (\case Box _ c -> bcText c `notElem` ["あ", "い"]; _ -> True)
      case firsts of
        (a : _ : b : _) -> do
          assertBool (show (beforeText a)) (all (\case Box {} -> True; _ -> False) (beforeText a))
          [bcText c | Box _ c <- beforeText a] @?= ["1", ".", ""]
          [bcText c | Box _ c <- beforeText b] @?= ["・", ""]
        _ -> assertFailure "lines",
    testCase "PDF: vertical, the number is a Number and the marker ends with 、" $ do
      let fs = maybe 0 (dimToSp 0) (parseDim "13Q")
      (_, pl) <- layoutOk pdfStyle ("+ " <> T.replicate 60 "あ" <> "\n") []
      case Map.elems (plLines pl) of
        (first : second : _) -> do
          take 3 [bcText c | Box _ c <- lineItems (slLine first)] @?= ["一", "、", ""]
          slIndent second @?= 2 * fs
        _ -> assertFailure "lines",
    testCase "PDF: lists, parallel and sequential, give the same bytes" $ do
      let src = "- " <> T.replicate 20 "あ" <> "\n  - 内[note: 注。]\n\n+ 一\n@number 9\n+ " <> T.replicate 30 "い" <> "\n"
      (e1, a) <- buildMini fakeProvider True horizontalStyle src []
      (e2, b) <- buildMini fakeProvider False horizontalStyle src []
      (e1, e2) @?= ([], [])
      assertBool "a PDF" (isJust a)
      a @?= b,
    testCase "PDF: the paragraph style's indent does not apply to list items" $ do
      (_, ls) <- verseLines (horizontalStyle <> "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n") ("- " <> T.replicate 20 "あ" <> "\n")
      map snd ls @?= [0, 10 * pt],
    testCase "PDF: lists nested so deep that less than 8 characters are left are G0727" $ do
      let style = replaceIn "characters = 12" "characters = 10" horizontalStyle
      (ok, _) <- buildMini fakeProvider False style "- 外\n  - 内の項目。\n" []
      ok @?= []
      r <- layoutMini style "- 一\n  - 二\n    - 三の項目。\n" []
      case r of
        Left ds -> do
          [diagCode d | d <- ds] @?= [DiagnosticCode "G0727"]
          [diagSpan d | d <- ds] /= [] @? "span"
        Right _ -> assertFailure "expected G0727",
    testCase "PDF: a note in a list item belongs to the line of its marker" $
      forM_ [8 .. 14] $ \k -> do
        (_, pl) <- layoutOk horizontalStyle ("- " <> T.replicate k "あ" <> "[note: 注。]" <> T.replicate 8 "い" <> "\n") []
        let marked = [i | (i, sl) <- zip [0 :: Int ..] (Map.elems (plLines pl)), any (\case Box _ c -> bcText c == "*1"; _ -> False) (lineItems (slLine sl))]
            noted = [i | (i, sl) <- zip [0 :: Int ..] (Map.elems (plLines pl)), not (null (slNotes sl))]
        (k, noted) @?= (k, marked),
    testCase "PDF: notes of two files with the same number keep their own bodies" $ do
      let manifest = replaceIn "chapters = [\"a.gm\"]" "chapters = [\"a.gm\", \"b.gm\"]" miniManifest
      (_, pl) <- layoutHeads manifest horizontalStyle [("a.gm", "一[note: 甲。]\n"), ("b.gm", "二[note: " <> T.replicate 30 "乙" <> "]\n")]
      let keys = [nid | sl <- Map.elems (plLines pl), (nid, _) <- slNotes sl]
          placed = [nid | p <- plPages pl, (nid, _, _) <- poFootnotes p]
      length keys @?= 2
      length (nub keys) @?= 2
      sort placed @?= sort keys,
    testCase "PDF: [lists] numbers set the marker, and its width" $ do
      ts <- listPages (horizontalStyle <> "\n[lists]\nnumbers = [\"({1})\"]\n") "+ 一\n+ 二\n"
      ts @?= ["(1)一", "(2)二"]
      (_, ls) <- verseLines (horizontalStyle <> "\n[lists]\nnumbers = [\"({1})\"]\n") ("+ " <> T.replicate 20 "あ" <> "\n")
      map snd ls @?= [0, 20 * pt],
    testCase "PDF: [lists] bullets by depth, the last one for deeper lists, with a gap" $ do
      let style = horizontalStyle <> TE.encodeUtf8 "\n[lists]\nbullets = [\"■\", \"□\"]\n"
      (_, pl) <- layoutOk (replaceIn "characters = 12" "characters = 30" style) "- 一\n  - 二\n    - 三\n" []
      map (T.take 1) (lineTexts pl) @?= ["■", "□", "□"]
      (_, ls) <- verseLines style ("- " <> T.replicate 20 "あ" <> "\n")
      -- 1 character and fs / 2, rounded up to whole characters
      map snd ls @?= [0, 20 * pt],
    testCase "a number its format cannot write is G0729, at the item" $ do
      r <- layoutMini (horizontalStyle <> TE.encodeUtf8 "\n[lists]\nnumbers = [\"{①}\"]\n") "+ 一\n@number 51\n+ 二\n" []
      case r of
        Left ds -> do
          [diagCode d | d <- ds] @?= [DiagnosticCode "G0729"]
          let lineStart = BS.length (TE.encodeUtf8 "+ 一\n@number 51\n")
          assertBool (show ds) (all (\d -> spanStart (diagSpan d) >= lineStart) ds)
        Right _ -> assertFailure "expected G0729"
      withVerseProject (horizontalStyle <> TE.encodeUtf8 "\n[lists]\nnumbers = [\"{①}\"]\n") "+ 一\n@number 51\n+ 二\n" $ \tmp -> do
        r' <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetText]}
        [diagCode d | d <- brDiagnostics r', isError d] @?= [DiagnosticCode "G0729"],
    testCase "HTML: [lists] writes a @counter-style for each depth" $
      withVerseProject (TE.encodeUtf8 "[lists]\nbullets = [\"■\", \"□\"]\nnumbers = [\"({1})\", \"{①}\"]\n") "- 一\n  - 二\n\n+ 一\n  + 二\n" $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        css <- TIO.readFile (tmp </> "build/html/style.css")
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        let has t = assertBool (T.unpack t <> "\n" <> T.unpack css) (t `T.isInfixOf` css)
        has "@counter-style golem-ul-1 { system: cyclic; symbols: \"■\"; suffix: \" \"; }"
        has "@counter-style golem-ul-2 { system: cyclic; symbols: \"□\"; suffix: \" \"; }"
        has "@counter-style golem-ol-1 { system: extends decimal; prefix: \"(\"; suffix: \") \"; }"
        has "@counter-style golem-ol-2 { system: fixed; symbols: \"①\"; suffix: \" \"; }"
        has "ul.list-1 { list-style-type: golem-ul-1; }"
        has "ol.list-2 { list-style-type: golem-ol-2; }"
        assertBool (T.unpack page) ("<ul class=\"list-1\">" `T.isInfixOf` page && "<ol class=\"list-2\">" `T.isInfixOf` page),
    testCase "HTML: no [lists], no @counter-style and no classes" $
      withVerseProject "" "- 一\n\n+ 一\n" $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        css <- TIO.readFile (tmp </> "build/html/style.css")
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        assertBool "css" (not ("@counter-style" `T.isInfixOf` css))
        assertBool "page" ("<ul>" `T.isInfixOf` page && "<ol>" `T.isInfixOf` page),
    testCase "plain text: [lists] markers by depth" $ do
      let style = TE.encodeUtf8 "[lists]\nbullets = [\"■\", \"□\"]\nnumbers = [\"({1})\", \"{a}.\"]\n"
      t <- listText style "- 一\n  - 二\n    - 三\n\n+ 一\n  + 二\n" "horizontal"
      t @?= "■ 一\n　□ 二\n　　□ 三\n\n(1) 一\n　a. 二\n"
      t' <- listText "" "- 一\n\n+ 一\n" "horizontal"
      t' @?= "・一\n\n1. 一\n"
  ]

-- | Manual control of page breaks (docs/adr ADR 0030).
pageControlTests :: [TestTree]
pageControlTests =
  [ testCase "PDF: page-lines +1 puts a line one pitch past the last line of the grid, horizontal and vertical" $
      forM_ [(fiveLines, dY), (verticalFive, dX)] $ \(style, axis) -> do
        pdf <- miniPdf fakeProvider True style (T.concat ["@page-lines +1\n\n"] <> T.intercalate "\n\n" ["一", "二", "三", "四", "五", "六"] <> "\n") []
        streams <- inflateAll pdf
        case filter (not . null) (map drawnGlyphs streams) of
          first : _ -> do
            let ps = sort (nub [read (T.unpack (TE.decodeUtf8 (axis d))) :: Double | d <- first])
                steps = zipWith (-) (drop 1 ps) ps
            length ps @?= 6
            assertBool (show steps) (all (\s -> abs (s - 15) < 0.01) steps)
          [] -> assertFailure "no glyphs",
    testCase "PDF: page-lines +1 past the trimmed page is G0737 and changes nothing" $ do
      let style = replaceIn "lines = 30" "lines = 36" horizontalStyle
      r <- layoutMini style "@page-lines +1\n\n一\n" []
      (_, layout) <- either (assertFailure . show) pure r
      map poLines (plPages layout) @?= [36]
      map diagCode (plNotices layout) @?= [DiagnosticCode "G0737"],
    testCase "PDF: a no-break that cannot be met and need-lines past the column are G0737, and the PDF is written" $ do
      r <- layoutMini fiveLines "@no-page-break\n\n一\n\n@need-lines 9\n\n二\n" []
      (_, layout) <- either (assertFailure . show) pure r
      map diagCode (plNotices layout) @?= [DiagnosticCode "G0737", DiagnosticCode "G0737"]
      _ <- miniPdf fakeProvider True fiveLines "@no-page-break\n\n一\n" []
      pure (),
    testCase "PDF: the same bytes in parallel and in sequence with the controls" $ do
      let src = "一\n\n@no-page-break\n\n二\n\n@need-lines 3\n\n三\n\n@page-lines -1\n\n四\n"
      a <- miniPdf fakeProvider True fiveLines src []
      b <- miniPdf fakeProvider False fiveLines src []
      a @?= b,
    testCase "HTML: the paragraph after a no-break avoids a break; need-lines and page-lines write nothing" $ do
      (page, css) <- htmlMini horizontalStyle "a\n\n@no-page-break\n\nb\n"
      assertBool (T.unpack page) ("<p>a</p>\n<p data-break-before=\"avoid\">b</p>\n" `T.isInfixOf` page)
      assertBool "avoid rule" ("[data-break-before=\"avoid\"] { page-break-before: avoid; break-before: avoid; }" `T.isInfixOf` css)
      (page', css') <- htmlMini horizontalStyle "a\n\n@need-lines 3\n\n@page-lines +1\n\nb\n"
      assertBool (T.unpack page') ("<p>a</p>\n<p>b</p>\n" `T.isInfixOf` page')
      assertBool "no rule" (not ("data-break-before" `T.isInfixOf` css')),
    testCase "plain text: the controls write nothing" $ do
      let text src = withVerseProject "" src $ \tmp -> do
            _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
            TIO.readFile (tmp </> "build/text/horizontal/v.txt")
      marked <- text "a\n\n@no-page-break\n\nb\n"
      plain <- text "a\n\nb\n"
      marked @?= plain
  ]
  where
    verticalFive = replaceIn "binding = \"left\"" "binding = \"right\"" (replaceIn "writing-mode = \"horizontal\"" "writing-mode = \"vertical\"" fiveLines)

breakTests :: [TestTree]
breakTests =
  [ testCase "PDF: a page break puts the second paragraph on the first line of page 2" $ do
      r <- pagesMini "" fiveLines "あ\n\n@page-break\n\nい\n" [] Map.empty
      pages <- either (assertFailure . show) pure r
      length pages @?= 2
      take 1 (pages !! 1) @?= ["い"],
    testCase "PDF: a blank page has no running head and no folio" $ do
      let style = fiveLines <> "\n[masters.body]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n"
      pdf <- miniPdf fakeProvider True style "あ\n\n@page-break\n\n@page-break\n\nい\n" []
      length (occurrences "/Type /Page " pdf) @?= 3
      streams <- inflateAll pdf
      -- two pages draw their text and folio; the blank page draws nothing
      length (filter (not . null . drawnGlyphs) streams) @?= 2
      r <- pagesMini "" style "あ\n\n@page-break\n\n@page-break\n\nい\n" [] Map.empty
      pages <- either (assertFailure . show) pure r
      pages !! 1 @?= [],
    testCase "HTML: a recto break marks the heading after it; only the rules used are written" $
      withVerseProject "" "@page-break recto\n# h\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        assertBool (T.unpack page) ("data-break-before=\"recto\">" `T.isInfixOf` page && "<h1 " `T.isInfixOf` page)
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "recto rule" ("[data-break-before=\"recto\"] { page-break-before: always; break-before: recto; }" `T.isInfixOf` css)
        assertBool "no page rule" (not ("[data-break-before=\"page\"]" `T.isInfixOf` css))
        assertBool "no verso rule" (not ("[data-break-before=\"verso\"]" `T.isInfixOf` css)),
    testCase "HTML: a body paragraph after a page break has the attribute and no class" $
      withVerseProject "" "a\n\n@page-break\n\nb\n" $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        assertBool (T.unpack page) ("<p>a</p>\n<p data-break-before=\"page\">b</p>\n" `T.isInfixOf` page),
    testCase "HTML: a break at the end of a file and a column break write nothing" $ do
      withVerseProject "" "a\n\n@page-break\n" $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        assertBool (T.unpack page) (not ("data-break-before" `T.isInfixOf` page))
        assertBool (T.unpack page) ("<p>a</p>\n</body>" `T.isInfixOf` page)
      withVerseProject "" "a\n\n@column-break\n\nb\n" $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        assertBool (T.unpack page) ("<p>a</p>\n<p>b</p>\n" `T.isInfixOf` page)
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "no rule" (not ("data-break-before" `T.isInfixOf` css)),
    testCase "plain text: a page break writes nothing" $ do
      let text src = withVerseProject "" src $ \tmp -> do
            _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
            TIO.readFile (tmp </> "build/text/horizontal/v.txt")
      broken <- text "a\n\n@page-break\n\nb\n"
      plain <- text "a\n\nb\n"
      broken @?= plain
      plain @?= "a\n\nb\n"
  ]

-- | pdfStyle with 20 characters a line, in two columns two em apart.
vertical2 :: BS.ByteString
vertical2 = replaceIn "characters = 42" "characters = 20" (replaceIn "columns = 1" "columns = 2\ncolumn-gap = \"2zw\"" pdfStyle)

-- | The page geometry of a style.
geometryOf :: BS.ByteString -> IO PageGeometry
geometryOf style = fst <$> layoutOk style "あ\n" []

columnTests :: [TestTree]
columnTests =
  [ testCase "PDF: a paragraph longer than two columns is set in the measure of a column" $ do
      (_, pl) <- layoutOk horizontal2 (longPara 80) []
      assertBool "column 1" (any ((== 1) . poColumn) (plPages pl))
      nub [lineTarget (slLine sl) | sl <- Map.elems (plLines pl)] @?= [12 * 10 * pt],
    testCase "PDF: the second column starts at the left edge of column 1, on the lines of column 0" $ do
      geom <- geometryOf horizontal2
      content <- miniPdf fakeProvider True horizontal2 (longPara 80) [] >>= fmap (take 1) . pageContents
      let ds = concatMap drawnGlyphs content
          x0 = TE.encodeUtf8 (spToPt (rectX (typeAreaFor geom 1)))
          x1 = TE.encodeUtf8 (spToPt (rectX (columnsFor geom 1 !! 1)))
          firstY x = take 1 (sortOn (negate . ptToRational) [dY d | d <- ds, dX d == x])
      assertBool "column 0" (not (null (firstY x0)))
      firstY x1 @?= firstY x0,
    testCase "PDF: vertical, the second column starts at the top of column 1, on the first grid line" $ do
      geom <- geometryOf vertical2
      content <- miniPdf fakeProvider True vertical2 (longPara 40) [] >>= fmap (take 1) . pageContents
      let ta = typeAreaFor geom 1
          c1 = columnsFor geom 1 !! 1
          x = TE.encodeUtf8 (spToPt (rectX ta + rectW ta - sum (take 1 (pgLineGrid geom))))
          y = TE.encodeUtf8 (spToPt (rectY c1 + rectH c1))
      assertBool "the first glyph of column 1" (any (any (\d -> dX d == x && dY d == y) . drawnGlyphs) content),
    testCase "PDF: sixty lines fill the two columns of one page" $ do
      (_, pl) <- layoutOk horizontal2 (longPara 72) []
      Map.size (plLines pl) @?= 60
      map (\p -> (poNumber p, poColumn p)) (plPages pl) @?= [(1, 0), (1, 1)],
    testCase "PDF: the running head of a page takes the headings of its columns in order (golem-driver ADR 0014)" $ do
      let style = horizontal2 <> "\n[masters.body]\nrunning-head = { position = \"top-outside\", content = \"heading.1.short\" }\n"
      (heads, pl) <- layoutHeads miniManifest style [("a.gm", "# 一\n\n" <> longPara 33 <> "# 二\n\n" <> longPara 2)]
      map (\p -> (poNumber p, poColumn p)) (plPages pl) @?= [(1, 0), (1, 1)]
      Map.lookup 1 heads @?= Just ["一"]
      (heads', _) <- layoutHeads miniManifest style [("a.gm", longPara 36 <> "# 二\n\n" <> longPara 2)]
      Map.lookup 1 heads' @?= Just ["二"],
    testCase "PDF: the folio is drawn once a page" $ do
      let style = horizontal2 <> "\n[masters.body]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n"
      content <- miniPdf fakeProvider True style (longPara 50) [] >>= pageContents
      length content @?= 1
      length [d | d <- concatMap drawnGlyphs content, dGlyph d == fromEnum '1'] @?= 1,
    testCase "PDF: a wrapped figure on a page of two columns is G0726 at the figure" $ do
      img <- tinyImage
      let source = longPara 2 <> wrapped "start" "4zw" <> longPara 10
      r <- layoutMini (figStyle horizontal2) source img
      case r of
        Left [d] -> do
          diagCode d @?= DiagnosticCode "G0726"
          [spanStart (diagSpan d)] @?= offsetsIn "@figure" source
        other -> assertFailure (show (either (map diagCode) (const []) other)),
    testCase "PDF: the index is set in the measure of a column and goes on in the second column" $ do
      let readings = ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ"]
          source = T.concat ["本文[index reading=" <> r <> ": 語" <> r <> "]。" | r <- readings] <> "\n\n@index\n"
      (_, pl) <- layoutOk (replaceIn "lines = 30" "lines = 5" horizontal2) source []
      let indexIn p = [sl | (_, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines pl)], "語" `T.isPrefixOf` setLineText sl]
      assertBool "in column 1" (any (\p -> poColumn p == 1 && not (null (indexIn p))) (plPages pl))
      nub [lineTarget (slLine sl) | p <- plPages pl, sl <- indexIn p] @?= [12 * 10 * pt],
    testCase "PDF: two columns, parallel and sequential, and two builds, give the same bytes" $ do
      let source = "# 一\n\n本文[note: 注。]。\n\n" <> longPara 80
      a <- miniPdf fakeProvider True horizontal2 source []
      b <- miniPdf fakeProvider False horizontal2 source []
      c <- miniPdf fakeProvider True horizontal2 source []
      a @?= b
      a @?= c
      qpdfCheck a,
    testCase "HTML and EPUB: the output of two columns is that of one column" $ do
      let out style = withSystemTempDirectory "golem-columns" $ \tmp -> do
            BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n")
            BS.writeFile (tmp </> "style.toml") style
            BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 ("# 一\n\n" <> longPara 10))
            r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
            assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
            buildFiles (tmp </> "build")
      one <- out horizontalStyle
      two <- out horizontal2
      assertBool "files" (not (Map.null one))
      two @?= one
      css <- maybe (assertFailure (show (Map.keys two))) pure (Map.lookup ("html" </> "style.css") two)
      assertBool "no columns" (not ("columns" `BS.isInfixOf` css) && not ("column-count" `BS.isInfixOf` css))
  ]

inseparableTests :: [TestTree]
inseparableTests =
  [ testCase "PDF: no line starts with the full stop after an ellipsis" $ do
      ls <- notoLines "……。"
      assertBool (show ls) (not (any ("。" `T.isPrefixOf`) ls))
      assertBool (show ls) (not (any (endsWithOne '…') ls)),
    testCase "PDF: a double dash of U+2015 is not split" $ do
      ls <- notoLines "――。"
      assertBool (show ls) (not (any (endsWithOne '―') ls))
      assertBool (show ls) (not (any ("。" `T.isPrefixOf`) ls))
  ]
  where
    endsWithOne ch t = T.length (T.takeWhileEnd (== ch) t) == 1
    -- Noto Serif JP of the 蟹工船 fixture, vertical, 38 characters a line;
    -- one paragraph for each n of 'あ' × n <> run <> 'い' × 40
    notoLines run = do
      noto <- notoBytes
      let style = replaceIn "characters = 42" "characters = 38" pdfStyle <> "\n[fonts.body]\nja = \"fonts/noto.otf\"\n"
          src = T.intercalate "\n\n" [T.replicate n "あ" <> run <> T.replicate 40 "い" | n <- [30 .. 41 :: Int]] <> "\n"
      r <- layoutMiniFonts realProvider miniManifest style src [("fonts/noto.otf", noto)]
      either (assertFailure . show) (pure . lineTexts . snd) r
