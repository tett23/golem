module PageElementsSpec (headingTests, emphasisTests, wrapTests, captionTests, sidenoteTests, footnoteTests, noteRuleTests, runningHeadTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (isSuffixOf, nub, sort, sortOn)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Data.Ratio ((%))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.Assemble (HeadingInfo (..))
import Golem.Doc.IR (InlineF (..))
import Golem.Driver
import Golem.Driver.Pdf (PdfLayout (..), PlacedFigure (..), PlacedSidenote (..), SetLine (..), figureRect, headingDefaults, runningHeadLines, syntheticStroke, syntheticStrokeJa, syntheticStrokeLatin, usedRoles)
import Golem.Layout.Japanese (BoxKind (..), boxKind)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Paginate (HeadingBlock (..), PageOut (..), Slotted (..))
import Golem.Layout.Wrap (Exclusion (..))
import Golem.LayoutSpec (PageGeometry (..), Rect (..), baselineRatio, pageGeometry, sidenoteAreaFor, typeAreaFor)
import Golem.Length (Sp (..))
import Golem.Pdf (spToPt)
import Golem.Project.Style (Dim (..), HeadForm (..), HeadPick (..), RunningContent (..), RunningPart (..), RunningRef (..), dimToSp, parseDim, parseRunningFormat, parseStyle)
import Golem.Syntax
import Support
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | Footnote marks, note bodies and note numbers (golem-driver ADR 0018).
footnoteTests :: [TestTree]
footnoteTests =
  [ testCase "PDF: notes 1 of two files each set the body of their own file" $ do
      content <- projectPdf twoFiles (horizontalStyle <> "\n[notes]\nnumbering = \"file\"\n") [("a.gm", "一[note: 甲。]\n"), ("b.gm", "二[note: 乙。]\n")]
      let count c = length [() | d <- drawnGlyphs content, dGlyph d == fromEnum c]
      (count '甲', count '乙') @?= (1, 1),
    testCase "PDF: the first line of a note body starts with its mark and an aki" $ do
      (_, pl) <- layoutHeads twoFiles horizontalStyle [("a.gm", "一[note: 甲。]\n"), ("b.gm", "二[note: 乙。]\n")]
      let firsts = [l | sl <- Map.elems (plLines pl), (_, l : _) <- slNotes sl]
          start l = case lineItems l of
            -- the mark, a quarter em [aki] (golem-layout ADR 0018), the body
            (Box _ c : Box _ a : Box _ d : _) | T.null (bcText a) -> Just (bcText c, bcText d)
            _ -> Nothing
      map start firsts @?= [Just ("*1", "甲"), Just ("*1", "乙")],
    testCase "PDF: horizontal, the mark is half the size, raised to the top of the em box, before the next character" $ do
      content <- miniPdf fakeProvider True horizontalStyle "漢[note: 注。]字\n" [] >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          s = 10 :: Rational
          m = 5
          small = [d | d <- ds, ptToRational (dSize d) == m]
          at c xs = [(ptToRational (dX d), ptToRational (dY d)) | d <- xs, dGlyph d == fromEnum c]
      case (at '*' small, at '1' small, at '漢' ds, at '字' ds) of
        ([(_, ys)], [(x1, _)], [(_, yk)], [(xj, _)]) -> do
          -- the fake fonts: the centre of the em box at 0.38, Latin half an em wide
          assertBool (show (ys - yk)) (abs (ys - yk - (38 / 100 + 1 / 2) * (s - m)) < 1 / 100)
          assertBool (show (x1, xj)) (xj >= x1 + m / 2)
        other -> assertFailure (show other),
    testCase "PDF: vertical, the mark is horizontal text whose right end is half the size right of the centre line" $ do
      content <- miniPdf fakeProvider True pdfStyle "漢[note: 注。]字\n" [] >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          s = toRational (unSp (maybe 0 (dimToSp 0) (parseDim "13Q"))) / 65536
          m = toRational (unSp (maybe 0 (dimToSp 0) (parseDim "13Q")) `div` 2) / 65536
          near a b = abs (a - b) < 1 / 100
          markOf c = [d | d <- ds, dGlyph d == fromEnum c, near (ptToRational (dSize d)) m]
      case (markOf '*', markOf '1', [d | d <- ds, dGlyph d == fromEnum '漢']) of
        ([star], [one], [kan]) -> do
          assertBool "the horizontal font" (dFont star /= dFont kan)
          dMatrix star @?= ["1", "0", "0", "1"]
          let right = ptToRational (dX one) + m / 2
          assertBool (show (right, ptToRational (dX kan) + s / 2)) (near right (ptToRational (dX kan) + s / 2))
        other -> assertFailure (show other),
    testCase "PDF: horizontal, mark-size 0.65zw sets the mark at that size, raised to the top of the em box (golem-driver ADR 0025)" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> "\n[notes]\nmark-size = \"0.65zw\"\n") "漢[note: 注。]字\n" [] >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          s = 10 :: Rational
          m = toRational (unSp (dimToSp (10 * 65536) (Zw (65 % 100)))) / 65536
          near a b = abs (a - b) < 1 / 100
          small = [d | d <- ds, near (ptToRational (dSize d)) m]
          at c xs = [(ptToRational (dX d), ptToRational (dY d)) | d <- xs, dGlyph d == fromEnum c]
      case (at '*' small, at '1' small, at '漢' ds, at '字' ds) of
        ([(_, ys)], [(x1, _)], [(_, yk)], [(xj, _)]) -> do
          assertBool (show (ys - yk)) (abs (ys - yk - (38 / 100 + 1 / 2) * (s - m)) < 1 / 100)
          assertBool (show (x1, xj)) (xj >= x1 + m / 2)
        other -> assertFailure (show other),
    testCase "PDF: vertical, mark-size 0.65zw keeps the right end of the mark half the size right of the centre line (golem-driver ADR 0025)" $ do
      content <- miniPdf fakeProvider True (pdfStyle <> "\n[notes]\nmark-size = \"0.65zw\"\n") "漢[note: 注。]字\n" [] >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          sSp = maybe 0 (dimToSp 0) (parseDim "13Q")
          s = toRational (unSp sSp) / 65536
          m = toRational (unSp (dimToSp sSp (Zw (65 % 100)))) / 65536
          near a b = abs (a - b) < 1 / 100
          markOf c = [d | d <- ds, dGlyph d == fromEnum c, near (ptToRational (dSize d)) m]
      case (markOf '*', markOf '1', [d | d <- ds, dGlyph d == fromEnum '漢']) of
        ([_], [one], [kan]) -> do
          let right = ptToRational (dX one) + m / 2
          assertBool (show (right, ptToRational (dX kan) + s / 2)) (near right (ptToRational (dX kan) + s / 2))
        other -> assertFailure (show other),
    testCase "PDF: mark-format {n}) gives the mark 1) in the text and at the start of the note (golem-driver ADR 0025)" $ do
      (_, pl) <- layoutOk (horizontalStyle <> "\n[notes]\nmark-format = \"{n})\"\n") "一[note: 甲。]\n" []
      let marks = [bcText c | sl <- Map.elems (plLines pl), Box _ c <- lineItems (slLine sl), boxKind c == KindNoteMark]
          firsts = [l | sl <- Map.elems (plLines pl), (_, l : _) <- slNotes sl]
          start l = case lineItems l of
            -- the mark, a quarter em [aki] (golem-layout ADR 0018), the body
            (Box _ c : Box _ a : Box _ d : _) | T.null (bcText a) -> Just (bcText c, bcText d)
            _ -> Nothing
      marks @?= ["1)"]
      map start firsts @?= [Just ("1)", "甲")],
    testCase "PDF: the default values written give the same page contents as none (golem-driver ADR 0025)" $ do
      a <- miniPdf fakeProvider True horizontalStyle "漢[note: 注。]字\n" [] >>= inflateAll
      b <- miniPdf fakeProvider True (horizontalStyle <> "\n[notes]\nmark-size = \"0.5zw\"\nmark-format = \"*{n}\"\n") "漢[note: 注。]字\n" [] >>= inflateAll
      a @?= b,
    testCase "by default the notes of a chapter in two files count on, in the PDF, HTML and plain text" $
      withSystemTempDirectory "golem-notes" $ \tmp -> do
        BS.writeFile (tmp </> "manifest.toml") (replaceIn "chapters = [\"a.gm\"]" "chapters = [[\"a.gm\", \"b.gm\"]]" miniManifest <> "\n[targets.html]\n\n[targets.text]\nvariants = [\"horizontal\"]\n")
        BS.writeFile (tmp </> "style.toml") (withBodyFont horizontalStyle)
        writeFiles tmp (bodyFontFiles horizontalStyle)
        BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 "一[note: 甲。]\n")
        BS.writeFile (tmp </> "b.gm") (TE.encodeUtf8 "二[note: 乙。]\n")
        r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf, TargetHtml, TargetText], optFonts = fakeProvider}
        filter isError (brDiagnostics r) @?= []
        let written = brWritten r
            readAll suffix = mconcat <$> mapM TIO.readFile (filter (suffix `isSuffixOf`) written)
        html <- readAll ".xhtml"
        txt <- readAll ".txt"
        assertBool (T.unpack html) ("href=\"#note-2\"" `T.isInfixOf` html)
        assertBool (T.unpack txt) ("*2" `T.isInfixOf` txt)
        pdf <- maybe (assertFailure "no PDF") BS.readFile (listToMaybe' (filter (".pdf" `isSuffixOf`) written))
        content <- BS.concat <$> inflateAll pdf
        let drawn = [dGlyph d | d <- drawnGlyphs content]
        assertBool "the mark *2" (fromEnum '2' `elem` drawn)
  ]
  where
    twoFiles = replaceIn "chapters = [\"a.gm\"]" "chapters = [\"a.gm\", \"b.gm\"]" miniManifest
    listToMaybe' = \case
      (x : _) -> Just x
      [] -> Nothing

-- | The rule before the footnotes of a page (golem-driver ADR 0024).
noteRuleTests :: [TestTree]
noteRuleTests =
  [ testCase "horizontal: a rule of the length through the middle of the separator line, from the left of the type area" $ do
      content <- miniPdf fakeProvider True (ruled horizontalStyle "") "漢[note: 注。]字\n" [] >>= fmap BS.concat . inflateAll
      case (rulesIn content, glyphsOf '注' content) of
        ([[x, y, w, h]], [(_, yn)]) -> do
          near (ptToRational x) (mmPt 20)
          near (ptToRational w) 50
          near (ptToRational h) 0.3
          -- the em box of the note line starts 8.8pt above its baseline; the separator line is one pitch (15pt) above
          near (ptToRational y + 0.15) (yn + 8.8 + 5 + 5)
        other -> assertFailure (show other),
    testCase "no rule on a page without footnotes, nor without [notes.rule]" $ do
      pdf <- miniPdf fakeProvider True (ruled fiveLines "") ("漢[note: 注。]字\n\n" <> T.replicate 120 "あ" <> "\n") []
      pages <- pageContents pdf
      map (length . rulesIn) pages @?= 1 : replicate (length pages - 1) 0
      plain <- miniPdf fakeProvider True horizontalStyle "漢[note: 注。]字\n" [] >>= fmap BS.concat . inflateAll
      rulesIn plain @?= [],
    testCase "the rule on a page of a footnote continued from the page before" $ do
      pdf <- miniPdf fakeProvider True (ruled fiveLines "") ("漢[note: " <> T.replicate 40 "注" <> "]字\n") []
      pages <- pageContents pdf
      map (length . rulesIn) pages @?= [1, 1],
    testCase "vertical: a rule down from the top of the type area" $ do
      content <- miniPdf fakeProvider True (ruled pdfStyle "") "漢[note: 注。]字\n" [] >>= fmap BS.concat . inflateAll
      let size = 13 / 4 * 72 / 25.4
          pitch = 22 / 4 * 72 / 25.4
      case (rulesIn content, glyphsOf '注' content) of
        ([[x, y, w, h]], [(xn, _)]) -> do
          near (ptToRational w) 0.3
          near (ptToRational h) (5 * size)
          -- B6: 182mm high, the type area 18mm from the top
          near (ptToRational y + ptToRational h) (mmPt (182 - 18))
          -- the separator line is one pitch right of the note line
          near (ptToRational x + 0.15) (xn + pitch)
        other -> assertFailure (show other),
    testCase "two columns: the rule only in the column of the footnote, from its left" $ do
      content <- miniPdf fakeProvider True (ruled horizontal2 "") "前。\n\n@column-break\n\n漢[note: 注。]字\n" [] >>= fmap BS.concat . inflateAll
      case rulesIn content of
        [[x, _, w, _]] -> do
          near (ptToRational x) (mmPt 20 + 140)
          near (ptToRational w) 50
        other -> assertFailure (show other),
    testCase "spaces: space-after exactly below the rule, space-before at least above it" $ do
      let style = ruled fiveLines "space-before = \"15pt\"\nspace-after = \"5pt\"\n"
      pdf <- miniPdf fakeProvider True style ("漢[note: 注。]" <> T.replicate 60 "あ" <> "\n") []
      pages <- pageContents pdf
      case pages of
        (first : _) -> case (rulesIn first, glyphsOf '注' first, map snd (glyphsOf 'あ' first)) of
          ([[_, y, _, h]], [(_, yn)], ys@(_ : _)) -> do
            let bottom = ptToRational y
                top = bottom + ptToRational h
                lastBody = minimum ys
            near (bottom - (yn + 8.8)) 5
            assertBool (show (lastBody - 1.2 - top)) (lastBody - 1.2 - top >= 15)
            -- two separator lines: the body has two lines on a page of five with one note line
            length (nub ys) @?= 2
          other -> assertFailure (show other)
        [] -> assertFailure "no pages",
    testCase "a rule longer than the line is G07001" $ do
      (errs, pdf) <- buildMini fakeProvider True (horizontalStyle <> "\n[notes.rule]\nlength = \"13zw\"\n") "漢[note: 注。]字\n" []
      (errs, pdf) @?= ([DiagnosticCode "G07001"], Nothing),
    testCase "a coloured rule is filled with the CMYK of its swatch inside q and Q (golem-driver ADR 0028)" $ do
      let style = horizontalStyle <> "\n[color.swatches]\naccent = { cmyk = [0, 100, 100, 0] }\n" <> "\n[notes.rule]\nlength = \"5zw\"\nweight = \"0.3pt\"\ncolor = \"accent\"\n"
      content <- miniPdf fakeProvider True style "漢[note: 注。]字\n" [] >>= fmap BS.concat . inflateAll
      let ls = BC.lines content
          rule = [i | (i, l) <- zip [0 :: Int ..] ls, drop 4 (BC.words l) == ["re", "f"]]
      case rule of
        [i] -> map (ls !!) [i - 2, i - 1, i + 1] @?= ["q", "0 1 1 0 k 0 1 1 0 K", "Q"]
        other -> assertFailure (show other),
    testCase "a dotted rule is a disc per dot, drawn without stroking (golem-driver ADR 0028)" $ do
      let style = horizontalStyle <> "\n[notes.rule]\nlength = \"5zw\"\nweight = \"1pt\"\nstyle = \"dotted\"\n"
      content <- miniPdf fakeProvider True style "漢[note: 注。]字\n" [] >>= fmap BS.concat . inflateAll
      let ls = map BC.words (BC.lines content)
      -- 5zw of 10pt: (50 - 1) / 3 rounded, and one more
      length [l | l <- ls, l == ["f"]] @?= 17
      rulesIn content @?= []
      [l | l <- ls, lastIs ["S", "J", "d"] l] @?= [],
    testCase "the line styles draw no stroke, line cap nor dash pattern (golem-driver ADR 0028)" $
      forM_ ["dashed", "wavy", "thick-thin", "japanese-dots"] $ \st -> do
        let style = horizontalStyle <> "\n[notes.rule]\nlength = \"5zw\"\nweight = \"1pt\"\nstyle = \"" <> st <> "\"\n"
        content <- miniPdf fakeProvider True style "漢[note: 注。]字\n" [] >>= fmap BS.concat . inflateAll
        [l | l <- map BC.words (BC.lines content), lastIs ["S", "J", "d"] l] @?= [],
    testCase "parallel and sequential builds with a rule agree" $ do
      let style = ruled fiveLines "space-before = \"15pt\"\nspace-after = \"5pt\"\n"
          source = "漢[note: " <> T.replicate 40 "注" <> "]字\n"
      a <- miniPdf fakeProvider True style source []
      b <- miniPdf fakeProvider False style source []
      a @?= b
      qpdfCheck a
  ]
  where
    ruled style extra = style <> "\n[notes.rule]\nlength = \"5zw\"\nweight = \"0.3pt\"\n" <> extra
    lastIs ops l = case reverse l of
      (o : _) -> o `elem` ops
      [] -> False
    near a b = assertBool (show (fromRational a :: Double, fromRational b :: Double)) (abs (a - b) < 1 / 100)
    mmPt mm = mm * 72 / 25.4
    glyphsOf c content = [(ptToRational (dX d), ptToRational (dY d)) | d <- drawnGlyphs content, dGlyph d == fromEnum c]

-- | Builds a project of several files to PDF with the fake fonts and returns its content streams.
projectPdf :: BS.ByteString -> BS.ByteString -> [(FilePath, T.Text)] -> IO BS.ByteString
projectPdf manifest style sources = withSystemTempDirectory "golem-project" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  writeFiles tmp (bodyFontFiles style)
  forM_ sources $ \(to, src) -> BS.writeFile (tmp </> to) (TE.encodeUtf8 src)
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
  filter isError (brDiagnostics r) @?= []
  case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> BS.readFile p >>= fmap BS.concat . inflateAll
    _ -> assertFailure "no PDF"

-- | The running head tests (ADR 0014).
runningHeadTests :: [TestTree]
runningHeadTests =
  [ testCase "first and last headings of a page" $ do
      let h1 = Map.fromList [(1, Just umi)]
          h12 = Map.fromList [(1, Just umi), (2, Just asa)]
          h12' = Map.fromList [(1, Just umi), (2, Just hiru)]
          h1' = Map.fromList [(1, Just yama), (2, Nothing)]
          at c st hs = listToMaybe (runningHeadLines meta Map.empty c st hs)
      -- 海 and 一 朝 start on the page
      at (heading 1 HeadShort PickFirst) Map.empty [umi, asa] @?= Just "海"
      at (heading 2 HeadShort PickFirst) Map.empty [umi, asa] @?= Just "朝"
      at (heading 2 HeadShort PickLast) Map.empty [umi, asa] @?= Just "朝"
      -- only 二 昼 starts
      at (heading 2 HeadShort PickFirst) h12 [hiru] @?= Just "昼"
      at (heading 1 HeadShort PickFirst) h12 [hiru] @?= Just "海"
      -- no heading starts
      at (heading 2 HeadShort PickFirst) h12' [] @?= Just "昼"
      at (heading 2 HeadShort PickLast) h12' [] @?= Just "昼"
      -- only 第二章 山 starts: first is the value at the start, last is none
      at (heading 2 HeadShort PickFirst) h12' [yama] @?= Just "昼"
      at (heading 2 HeadShort PickLast) h12' [yama] @?= Nothing
      at (heading 1 HeadShort PickFirst) h12' [yama] @?= Just "山"
      -- the next page
      at (heading 2 HeadShort PickFirst) h1' [] @?= Nothing
      at (heading 1 HeadShort PickFirst) h1 [] @?= Just "海",
    testCase "numbered headings, unnumbered headings, title and none" $ do
      lines'' (heading 1 HeadNumbered PickFirst) Map.empty [umi] @?= ["第一章　海"]
      lines'' (heading 1 HeadNumbered PickFirst) Map.empty [umi {hiNumbers = Nothing, hiNumberText = Nothing}] @?= ["海"]
      lines'' (fmt [["{meta.title}"]]) Map.empty [umi] @?= ["書名"]
      lines'' RunningNone Map.empty [umi] @?= [],
    testCase "before the first heading there is none" $
      lines'' (heading 1 HeadShort PickFirst) Map.empty [] @?= [],
    -- golem-driver ADR 0022: formats
    testCase "the title and the chapter on one line; none before the first chapter (ADR 0022)" $ do
      lines'' (fmt [["{meta.title}　{heading.1.short}"]]) Map.empty [umi] @?= ["書名　海"]
      lines'' (fmt [["{meta.title}　{heading.1.short}"]]) Map.empty [] @?= [],
    testCase "? leaves no trailing space (ADR 0022)" $ do
      let f = fmt [["{heading.1.short}　{heading.2.short?}"]]
      lines'' f Map.empty [umi] @?= ["海"]
      lines'' f Map.empty [umi, asa] @?= ["海　朝"]
      lines'' (fmt [["{heading.1.short}　{heading.2.short}"]]) Map.empty [umi] @?= [],
    testCase "two lines, and the lines without a value left out (ADR 0022)" $ do
      let f = fmt [["{meta.title}"], ["{heading.1.short}"]]
      lines'' f Map.empty [] @?= ["書名"]
      lines'' f Map.empty [umi] @?= ["書名", "海"],
    testCase "the number of a heading (ADR 0022)" $ do
      lines'' (fmt [["{heading.1.number}"]]) Map.empty [umi] @?= ["第一章"]
      lines'' (fmt [["{heading.1.number}"]]) Map.empty [umi {hiNumbers = Nothing, hiNumberText = Nothing}] @?= [],
    testCase "metadata that is not there (ADR 0022)" $ do
      lines'' (fmt [["{meta.edition}版"]]) Map.empty [umi] @?= []
      lines'' (fmt [["{meta.edition?}版"]]) Map.empty [umi] @?= ["版"],
    testCase "fixed text is on every page (ADR 0022)" $ do
      lines'' (fmt [["校正刷り"]]) Map.empty [] @?= ["校正刷り"]
      lines'' (fmt [["校正刷り"]]) Map.empty [umi] @?= ["校正刷り"],
    testCase "variables of the file (ADR 0022)" $ do
      runningHeadLines meta (Map.fromList [(["revision"], "r1")]) (fmt [["{set.revision}"]]) Map.empty [] @?= ["r1"]
      runningHeadLines meta (Map.fromList [(["values", "price"], "100")]) (fmt [["{set.values.price}"]]) Map.empty [] @?= ["100"]
      forM_ [("\"r1\"", "r1"), ("3", "3"), ("0.5", "0.5")] $ \(v, shown) -> do
        (heads, _) <- layoutHeads miniManifest (headsStyle "content = [\"{set.revision}\"]") [("a.gm", "@set revision = " <> v <> "\n\n" <> twoChapters)]
        Map.lookup 2 heads @?= Just [shown],
    testCase "even pages the title, odd pages the chapter; none on recto and blank pages" $ do
      (heads, _) <- layoutHeads miniManifest (headsStyle "even = \"title\", odd = \"heading.1.short\"") [("a.gm", twoChapters)]
      Map.toList heads @?= [(1, []), (2, ["T"]), (3, ["海"]), (4, []), (5, []), (6, ["T"])],
    testCase "formats give the table of the vocabulary (ADR 0022)" $ do
      (a, _) <- layoutHeads miniManifest (headsStyle "even = \"title\", odd = \"heading.1.short\"") [("a.gm", twoChapters)]
      (b, _) <- layoutHeads miniManifest (headsStyle "even = [\"{meta.title}\"], odd = [\"{heading.1.short}\"]") [("a.gm", twoChapters)]
      b @?= a,
    testCase "no fixed text on a page where a recto heading starts (ADR 0022)" $ do
      (heads, _) <- layoutHeads miniManifest (headsStyle "content = [\"PROOF\"]") [("a.gm", twoChapters)]
      Map.toList heads @?= [(1, []), (2, ["PROOF"]), (3, ["PROOF"]), (4, []), (5, []), (6, ["PROOF"])],
    testCase "the folio is drawn on a recto page, not on a blank page" $ do
      (errs, pdf) <- buildMini fakeProvider False (headsStyle "even = \"title\", odd = \"heading.1.short\"") twoChapters []
      errs @?= []
      content <- BS.concat <$> maybe (assertFailure "no PDF") inflateAll pdf
      assertBool "folio 1" ("<0031> Tj" `BS.isInfixOf` content)
      assertBool "folio 5" ("<0035> Tj" `BS.isInfixOf` content)
      assertBool "no folio 4" (not ("<0034> Tj" `BS.isInfixOf` content))
      assertBool "title on even pages" ("<0054> Tj" `BS.isInfixOf` content),
    testCase "two lines at the head keep the last line where one line is; at the foot the first (ADR 0022)" $ do
      let drawnAt rh = do
            (errs, pdf) <- buildMini fakeProvider False (headsStyleAt rh) twoChapters []
            errs @?= []
            content <- BS.concat <$> maybe (assertFailure "no PDF") inflateAll pdf
            pure (\c -> [(milli (dX d), milli (dY d)) | d <- drawnGlyphs content, dGlyph d == fromEnum c])
      one' <- drawnAt "position = \"top-outside\", content = [\"Z\"]"
      two <- drawnAt "position = \"top-outside\", content = [\"Q\", \"Z\"]"
      let pitch = 15000
      assertBool "Z drawn" (not (null (two 'Z')))
      map snd (two 'Z') @?= map snd (one' 'Z')
      map snd (two 'Q') @?= map ((+ pitch) . snd) (two 'Z')
      -- both lines end at the fore-edge
      map fst (two 'Q') @?= map fst (two 'Z')
      oneFoot <- drawnAt "position = \"bottom-center\", content = [\"Z\"]"
      twoFoot <- drawnAt "position = \"bottom-center\", content = [\"Z\", \"Q\"]"
      map snd (twoFoot 'Z') @?= map snd (oneFoot 'Z')
      map snd (twoFoot 'Q') @?= map (subtract pitch . snd) (twoFoot 'Z'),
    testCase "a variable the file does not define is G02067 at the top of the file (ADR 0022)" $ do
      (ds, srcs, _) <- buildHeads (headsStyle "content = [\"{set.revision}\"]") [("a.gm", twoChapters)] Nothing
      case [d | d <- ds, diagCode d == DiagnosticCode "G02067"] of
        [d] -> do
          fmap siPath (Map.lookup (spanFile (diagSpan d)) srcs) @?= Just "a.gm"
          (spanStart (diagSpan d), spanEnd (diagSpan d)) @?= (0, 0)
          diagMessage d @?= "柱が参照する変数 revision が、このファイルにありません（マスターページ body）"
        other -> assertFailure (show other)
      (ds', _, _) <- buildHeads (headsStyle "content = [\"{set.revision?}\"]") [("a.gm", twoChapters)] Nothing
      [d | d <- ds', isError d] @?= [],
    testCase "a variable that is not a string or a number is G02068 (ADR 0022)" $ do
      (ds, srcs, _) <- buildHeads (headsStyle "content = [\"{set.revision}\"]") [("a.gm", "@set revision = true\n\n" <> twoChapters)] Nothing
      [(described d, fmap siPath (Map.lookup (spanFile (diagSpan d)) srcs)) | d <- ds, isError d] @?= [(("G02068", "柱に出せるのは文字列と数です: revision は 真偽値", FileId 1, 0, 0), Just "a.gm")],
    testCase "an imported variable (ADR 0022)" $ do
      (heads, _) <- layoutHeads miniManifest (headsStyle "content = [\"{set.values.price}\"]") [("a.gm", "@import common/values.gm as values\n\n" <> twoChapters), ("common/values.gm", "@set price = 100\n")]
      Map.lookup 2 heads @?= Just ["100"],
    testCase "no G02067 in a build without the PDF (ADR 0022)" $ do
      (ds, _, _) <- buildHeads (headsStyle "content = [\"{set.revision}\"]") [("a.gm", twoChapters)] (Just [TargetHtml])
      [d | d <- ds, diagCode d == DiagnosticCode "G02067"] @?= [],
    testCase "a line wider than the type area is G07051, and the PDF is written (ADR 0022)" $ do
      (ds, srcs, pdf) <- buildHeads (headsStyle "content = [\"ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJ\"]") [("a.gm", twoChapters)] Nothing
      [(diagSeverity d, described d, fmap siPath (Map.lookup (spanFile (diagSpan d)) srcs)) | d <- ds, diagCode d == DiagnosticCode "G07051"] @?= [(Warning, ("G07051", "柱の行が版面の幅を超えています（2 ページ）: ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJ", FileId 2, 0, 0), Just "style.toml")]
      [d | d <- ds, isError d] @?= []
      assertBool "a PDF" (isJust pdf),
    testCase "a line exactly as wide as the type area is not G07051; one more character is (ADR 0022)" $ do
      -- the type area is 12 characters of 10pt; the fake font sets Latin half an em wide
      let g07051 t = do
            (ds, _, _) <- buildHeads (headsStyle ("content = [\"" <> TE.encodeUtf8 t <> "\"]")) [("a.gm", twoChapters)] Nothing
            pure [diagMessage d | d <- ds, diagCode d == DiagnosticCode "G07051"]
      forM_ [(T.replicate 24 "A", T.replicate 25 "A"), (T.replicate 12 "字", T.replicate 13 "字")] $ \(fits, over) -> do
        g07051 fits >>= (@?= [])
        g07051 over >>= (@?= ["柱の行が版面の幅を超えています（2 ページ）: " <> over]),
    testCase "the short title of @toc-title" $ do
      (heads, _) <- layoutHeads miniManifest (headsStyle "content = \"heading.1.short\"") [("a.gm", "@toc-title 短\n# 長い題\n\n" <> lines' 11 <> "\n")]
      Map.lookup 2 heads @?= Just ["短"],
    testCase "master pages per chapter file" $ do
      let manifest = BS.concat ["chapters = [{ file = \"front.gm\", master = \"front\" }, { file = \"a.gm\", master = \"body\" }, \"b.gm\"]\n", BS.drop (BS.length "chapters = [\"a.gm\"]\n") miniManifest]
          style =
            BS.concat
              [ shortGrid,
                flatHeadings,
                "[masters.appendix]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n\n",
                "[masters.front]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n\n",
                "[masters.body]\nrunning-head = { position = \"top-outside\", content = \"heading.1.short\" }\n"
              ]
      (heads, _) <-
        layoutHeads manifest style [("front.gm", "# 目次\n\n" <> lines' 5 <> "\n"), ("a.gm", "# 甲\n\n" <> lines' 5 <> "\n"), ("b.gm", "# 乙\n\n" <> lines' 5 <> "\n")]
      Map.toList heads @?= [(1, []), (2, ["甲"]), (3, ["乙"])],
    testCase "running heads do not move page breaks" $ do
      (_, a) <- layoutHeads miniManifest (headsStyle "content = \"heading.1.short\"") [("a.gm", twoChapters)]
      (_, b) <- layoutHeads miniManifest (headsStyle "even = \"title\", odd = \"heading.1.numbered.last\"") [("a.gm", twoChapters)]
      plPages a @?= plPages b,
    testCase "formats do not move page breaks (ADR 0022)" $ do
      (_, a) <- layoutHeads miniManifest (headsStyle "content = [\"{heading.1.short}\"]") [("a.gm", twoChapters)]
      (_, b) <- layoutHeads miniManifest (headsStyle "content = [\"{meta.title}\", \"PROOF {heading.1.numbered}\"]") [("a.gm", twoChapters)]
      plPages a @?= plPages b,
    testCase "parallel and sequential builds agree, and twice" $ do
      let style = headsStyle "even = \"title\", odd = \"heading.1.short\""
      (_, p1) <- buildMini fakeProvider True style twoChapters []
      (_, p2) <- buildMini fakeProvider False style twoChapters []
      (_, p3) <- buildMini fakeProvider False style twoChapters []
      assertBool "a PDF" (isJust p1)
      p1 @?= p2
      p2 @?= p3,
    testCase "parallel and sequential builds of two-line formats agree (ADR 0022)" $ do
      let style = headsStyle "even = [\"{meta.title}\", \"{heading.1.short}\"], odd = [\"{heading.1.numbered}\"]"
      (e1, p1) <- buildMini fakeProvider True style twoChapters []
      (_, p2) <- buildMini fakeProvider False style twoChapters []
      e1 @?= []
      assertBool "a PDF" (isJust p1)
      p1 @?= p2
  ]
  where
    sp0 = mkSpan (FileId 0) 0 0
    info l n nt t = HeadingInfo l (Just [n]) (Just nt) [Text sp0 t] t (FileId 0)
    umi = info 1 1 "第一章" "海"
    asa = info 2 1 "一" "朝"
    hiru = info 2 2 "二" "昼"
    yama = info 1 2 "第二章" "山"
    meta = Map.fromList [("title", "書名"), ("language", "ja")]
    lines'' = runningHeadLines meta Map.empty
    heading l f p = RunningLines ([PartRef (RefHeading l f p) False] :| [])
    -- a format, read as style.toml reads it
    fmt ls = case traverse (fmap concat . traverse parseRunningFormat) ls of
      Right (x : xs) -> RunningLines (x :| xs)
      other -> error (show other)
    -- a number of the content stream in thousandths
    milli :: BS.ByteString -> Integer
    milli b = round (read (BC.unpack (if "." `BS.isPrefixOf` b then "0" <> b else b)) * 1000 :: Double)
    -- n lines of twelve characters
    lines' n = T.replicate (12 * n) "あ"
    -- 海: pages 1 to 3, a blank page 4, 山: pages 5 and 6
    twoChapters = T.intercalate "\n\n" ["# 海", lines' 5, lines' 6, lines' 6, "# 山", lines' 5, lines' 6] <> "\n"
    shortGrid = replaceIn "lines = 30\n" "lines = 6\n" horizontalStyle <> "\n"
    headsStyle rh = headsStyleAt ("position = \"top-outside\", " <> rh)
    headsStyleAt rh =
      BS.concat
        [ shortGrid,
          "[headings.1]\npage-break = \"recto\"\nsize = \"1zw\"\nlines = 1\n\n",
          "[masters.body]\nrunning-head = { ",
          rh,
          " }\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n"
        ]
    -- builds the one-chapter project with these files: its diagnostics, its sources and its PDF
    buildHeads style files targets = withSystemTempDirectory "golem-heads" $ \tmp -> do
      BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n")
      BS.writeFile (tmp </> "style.toml") (withBodyFont style)
      writeFiles tmp (bodyFontFiles style)
      writeTexts tmp files
      r <- build (defaultOptions tmp) {optTargets = Just (fromMaybe [TargetPdf] targets), optFonts = fakeProvider}
      pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
        [p] -> Just <$> BS.readFile p
        _ -> pure Nothing
      pure (brDiagnostics r, brSources r, pdf)

-- | Glyph runs of a content stream: the Tf size and each glyph id with its origin.
glyphRuns :: BS.ByteString -> [(BS.ByteString, [(Int, BS.ByteString, BS.ByteString)])]
glyphRuns content = go (BC.lines content)
  where
    go [] = []
    go (l : rest)
      | (_ : _ : size : "Tf" : _) <- BC.words l =
          let (body, rest') = break ((== "ET") . BC.strip) rest
           in (size, [g | b <- body, Just g <- [glyph b]]) : go rest'
      | otherwise = go rest
    glyph l = case reverse (BC.words l) of
      ("Tj" : hexg : "Tm" : y : x : _) -> Just (read ("0x" <> BC.unpack (BC.filter (`notElem` ("<>" :: String)) hexg)), x, y)
      _ -> Nothing

headingTests :: [TestTree]
headingTests =
  [ testCase "a 20pt heading wraps in the measure and is drawn at 20pt" $ do
      let source = "# あいうえおかきく\n\n本文。\n"
          kana = [0x3042, 0x3044, 0x3046, 0x3048, 0x304A, 0x304B, 0x304D, 0x304F]
          headingYs pdf = do
            content <- BS.concat <$> inflateAll pdf
            pure (nub [y | (_, gs) <- glyphRuns content, (g, _, y) <- gs, g `elem` kana], tfSizes content)
      (big, sizes) <- miniPdf fakeProvider True (horizontalStyle <> "\n[headings.1]\nsize = \"20pt\"\n") source [] >>= headingYs
      length big @?= 2
      assertBool (show sizes) ("20" `elem` sizes)
      (plain, _) <- miniPdf fakeProvider True (horizontalStyle <> flatHeadings) source [] >>= headingYs
      length plain @?= 1,
    testCase "a heading role with its own font embeds both fonts, each with its own glyphs" $ do
      (sans, serif) <- realLatinFonts
      pdf <- miniPdf realProvider True (horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.heading]\nlatin = \"fonts/serif.ttf\"\n\n[headings.1]\nfont = \"heading\"\n") "# Zebra\n\nquick\n" [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)]
      streams <- inflateAll pdf
      let cmaps = filter ("beginbfchar" `BS.isInfixOf`) streams
      length cmaps @?= 2
      assertBool "heading glyphs only in one font" (any (\c -> "<005a>" `BS.isInfixOf` c && not ("<0071>" `BS.isInfixOf` c)) cmaps)
      assertBool "body glyphs only in the other" (any (\c -> "<0071>" `BS.isInfixOf` c && not ("<005a>" `BS.isInfixOf` c)) cmaps)
      qpdfCheck pdf,
    testCase "two roles on the same file embed one font program" $ do
      (sans, _) <- realLatinFonts
      pdf <- miniPdf realProvider True (horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.heading]\nlatin = \"fonts/sans.otf\"\n\n[headings.1]\nfont = \"heading\"\nsize = \"20pt\"\n") "# Zebra\n\nquick\n" [("fonts/sans.otf", sans)]
      length (occurrences "/FontFile" pdf) @?= 1,
    testCase "naming the body role and the body size changes nothing" $ do
      (sans, _) <- realLatinFonts
      let base = horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n"
          files = [("fonts/sans.otf", sans)]
      a <- miniPdf realProvider True (base <> "\n[headings.1]\nsize = \"10pt\"\n") "# Zebra\n\nquick\n" files
      b <- miniPdf realProvider True (base <> "\n[headings.1]\nfont = \"body\"\nsize = \"10pt\"\n") "# Zebra\n\nquick\n" files
      -- style.toml is an input of the instance ID (golem-pdf ADR 0004), so the trailer differs
      let withoutId pdf = fst (BS.breakSubstring "/ID [" pdf)
      withoutId a @?= withoutId b
      assertBool "instance ID" (snd (pdfIds a) /= snd (pdfIds b)),
    testCase "heading roles: parallel and sequential, and two builds, give the same bytes" $ do
      (sans, serif) <- realLatinFonts
      let style = horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.heading]\nlatin = \"fonts/serif.ttf\"\n\n[headings.1]\nfont = \"heading\"\nsize = \"20pt\"\n"
          files = [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)]
          source = "# Zebra crossing\n\nThe quick brown fox jumps over the lazy dog.\n\n# Second\n\nquick\n"
      a <- miniPdf realProvider True style source files
      b <- miniPdf realProvider False style source files
      c <- miniPdf realProvider True style source files
      a @?= b
      a @?= c
      qpdfCheck a,
    testCase "different fonts with the same PostScript name are an error" $ do
      (sans, _) <- realLatinFonts
      (errs, pdf) <- buildMiniErrors realProvider True (horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.heading]\nlatin = \"fonts/sans2.otf\"\n\n[headings.1]\nfont = \"heading\"\n") "# Zebra\n\nquick\n" [("fonts/sans.otf", sans), ("fonts/sans2.otf", sans <> BS.replicate 4 0)]
      [(c, m, st, en) | (c, m, _, st, en) <- map described errs] @?= [("G08005", "PostScript 名が同じ異なるフォントがあります: SourceSansPro-Regular（fonts/sans.otf、fonts/sans2.otf）", 0, 0)]
      pdf @?= Nothing,
    testCase "a heading taller than the page is an error" $ do
      let style = BC.pack (T.unpack (T.replace "lines = 30" "lines = 3" (T.pack (BC.unpack horizontalStyle)))) <> "\n[headings.1]\nsize = \"60pt\"\n"
      (errs, pdf) <- buildMini fakeProvider True style "# A\n\nx\n" []
      errs @?= [DiagnosticCode "G07024"]
      pdf @?= Nothing
      layoutMini style "# A\n\nx\n" [] >>= (@?= [("G07024", "見出しが版面に入りません（1 の見出し: A）", FileId 1, 0, 4)]) . layoutErrors,
    testCase "the default size and lines of a heading by language and level (golem-driver ADR 0032)" $ do
      headingDefaults "ja" 1 @?= (Zw (3 % 2), 5)
      headingDefaults "ja-JP" 3 @?= (Zw 1, 2)
      headingDefaults "en" 1 @?= (Zw (3 % 2), 6)
      headingDefaults "fr" 2 @?= (Zw (5 % 4), 4),
    testCase "the default size and lines of every level, in Japanese and in English (golem-driver ADR 0032)" $ do
      map (headingDefaults "ja") [1 .. 5] @?= [(Zw (3 % 2), 5), (Zw (5 % 4), 3), (Zw 1, 2), (Zw 1, 1), (Zw 1, 1)]
      map (headingDefaults "en") [1 .. 5] @?= [(Zw (3 % 2), 6), (Zw (5 % 4), 4), (Zw 1, 2), (Zw 1, 1), (Zw 1, 1)],
    testCase "a heading with only a number is 1.5 times the body and takes five lines in Japanese (golem-driver ADR 0032)" $ do
      let style = horizontalStyle <> "\n[headings.1]\nnumber = \"{n}\"\n"
          source = "# 見出し\n\n本文。\n"
      content <- miniPdf fakeProvider True style source [] >>= fmap BS.concat . inflateAll
      assertBool (show (tfSizes content)) ("15" `elem` tfSizes content)
      (_, pl) <- layoutOk style source []
      headingGap pl @?= [5],
    testCase "the same heading takes six lines in an English book (golem-driver ADR 0032)" $ do
      let style = horizontalStyle <> "\n[headings.1]\nnumber = \"{n}\"\n"
          manifest = replaceIn "language = \"ja\"" "language = \"en\"" miniManifest
      (_, pl) <- layoutMiniWith manifest style "# Heading\n\nbody.\n" [] >>= either (assertFailure . show) pure
      headingGap pl @?= [6],
    testCase "size 1zw and lines 1 keep each line of a heading on the body grid (golem-driver ADR 0032)" $ do
      let style = horizontalStyle <> "\n[headings.1]\nsize = \"1zw\"\nlines = 1\n"
      (_, pl) <- layoutOk style "# 見出し\n\n本文。\n" []
      headingGap pl @?= [1]
      map (\hb -> (hbSpan hb, hbOffset hb)) (Map.elems (plHeadings pl)) @?= [(1, 0)],
    testCase "the default lines are cut to a page of three lines; lines = 4 is G07024 (golem-driver ADR 0032)" $ do
      let three = replaceIn "lines = 30" "lines = 3" horizontalStyle
      (ok, _) <- buildMini fakeProvider True three "# A\n\nx\n" []
      ok @?= []
      (errs, pdf) <- buildMini fakeProvider True (three <> "\n[headings.1]\nlines = 4\n") "# A\n\nx\n" []
      errs @?= [DiagnosticCode "G07024"]
      pdf @?= Nothing
      layoutMini (three <> "\n[headings.1]\nlines = 4\n") "# A\n\nx\n" [] >>= (@?= [("G07024", "見出しが版面に入りません（1 の見出し: A）", FileId 1, 0, 4)]) . layoutErrors,
    -- golem-layout ADR 0020
    testCase "G07100: a heading taller than a column cut by page-lines is a notice, and the PDF is written" $ do
      let source = "@page-lines -29\n\n# A\n\nx\n"
          files extra = [("manifest.toml", miniManifest <> extra), ("style.toml", withBodyFont horizontalStyle), ("a.gm", TE.encodeUtf8 source)] <> fakeFontFiles
          pdfOf n = [b | (p, b) <- nOutputs n, ".pdf" `isSuffixOf` p]
      loud <- buildNotified (files "") id
      [(diagCode d, diagSeverity d) | d <- nDiagnostics loud] @?= [(DiagnosticCode "G07100", Notice)]
      length (pdfOf loud) @?= 1
      (_, pl) <- layoutOk horizontalStyle source []
      map described (plNotices pl) @?= [("G07100", "見出しが段に入りません（1 の見出し: A。見出しは 5 行、段の残りは 1 行）", FileId 1, 17, 21)]
      -- silenced, the PDF is the same but for its ID, which comes from manifest.toml
      quiet <- buildNotified (files "\n[diagnostics]\nsilence-notices = [\"G07100\"]\n") id
      nDiagnostics quiet @?= []
      quietStreams <- mapM inflateAll (pdfOf quiet)
      loudStreams <- mapM inflateAll (pdfOf loud)
      quietStreams @?= loudStreams
      none <- buildNotified (files "") (\o -> o {optNoNotices = True})
      nDiagnostics none @?= []
      nOutputs none @?= nOutputs loud,
    testCase "no G07100 for a heading of five lines in a column cut to five lines (golem-layout ADR 0020)" $ do
      (codes, pdf) <- buildMini fakeProvider True horizontalStyle "@page-lines -25\n\n# A\n\nx\n" []
      codes @?= []
      assertBool "the PDF" (isJust pdf)
      (_, pl) <- layoutOk horizontalStyle "@page-lines -25\n\n# A\n\nx\n" []
      plNotices pl @?= [],
    testCase "default headings: parallel and sequential, and two builds, give the same bytes (golem-driver ADR 0032)" $ do
      let source = "# 一\n\n本文。\n\n## 二\n\n### 三\n\n本文。\n"
      a <- miniPdf fakeProvider True horizontalStyle source []
      b <- miniPdf fakeProvider False horizontalStyle source []
      c <- miniPdf fakeProvider True horizontalStyle source []
      a @?= b
      a @?= c
  ]
  where
    -- the grid lines from each heading to the line after it on its page
    headingGap pl =
      [ next - h
      | p <- plPages pl,
        (h, SHeading {}) <- poSlots p,
        next <- take 1 [l | (l, SLine _) <- poSlots p, l > h]
      ]

emphasisTests :: [TestTree]
emphasisTests =
  [ testCase "synthetic bold strokes the outline and keeps every glyph where it was" $ do
      a <- miniPdf fakeProvider True horizontalStyle "前の[bold: 本文]後\n" [] >>= fmap BS.concat . inflateAll
      b <- miniPdf fakeProvider True horizontalStyle "前の本文後\n" [] >>= fmap BS.concat . inflateAll
      assertBool "2 Tr" ("2 Tr" `BS.isInfixOf` a)
      sort [(dGlyph d, dX d, dY d) | d <- drawnGlyphs a] @?= sort [(dGlyph d, dX d, dY d) | d <- drawnGlyphs b],
    testCase "strong as italic slants Latin and Japanese alike, upright vertical glyphs too" $ do
      let slanted content = [(dGlyph d, dMatrix d) | d <- drawnGlyphs content, dGlyph d `elem` map fromEnum ("Gと組版" :: String)]
      h <- miniPdf fakeProvider True (horizontalStyle <> "\n[character-styles.strong]\nbased-on = \"italic\"\n") "[strong: Golem と組版]\n" [] >>= fmap BS.concat . inflateAll
      assertBool (show (slanted h)) (length (slanted h) == 4 && all ((== ["1", "0", "0.2", "1"]) . snd) (slanted h))
      v <- miniPdf fakeProvider True (pdfStyle <> "\n[character-styles.strong]\nbased-on = \"italic\"\n") "[strong: Golem と組版]\n" [] >>= fmap BS.concat . inflateAll
      let upright = [m | (g, m) <- slanted v, g /= fromEnum 'G']
      assertBool (show (slanted v)) (length upright == 3 && all (== ["1", "0", "0.2", "1"]) upright)
      assertBool "turned Latin" (any ((== ["0", "-1", "1", "-0.2"]) . snd) (slanted v)),
    testCase "an italic role with only Latin sets Latin upright in it and slants the Japanese" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[character-styles.italic]\nfont = \"wide\"\n") "本[italic: Golem と組版]\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          latin = [d | d <- ds, dGlyph d == fromEnum 'G']
          ja = [d | d <- ds, dGlyph d == fromEnum '組']
          body = [d | d <- ds, dGlyph d == fromEnum '本']
      map dMatrix latin @?= [["1", "0", "0", "1"]]
      map dMatrix ja @?= [["1", "0", "0.2", "1"]]
      assertBool "the Latin role's font" (map dFont latin /= map dFont body)
      map dFont ja @?= map dFont body,
    testCase "a bold role with wider metrics breaks into more lines" $ do
      let source = "[bold: ab cd ef gh ij kl mn op]\n"
          rows pdf = do
            content <- BS.concat <$> inflateAll pdf
            pure (length (nub [dY d | d <- drawnGlyphs content, dGlyph d `elem` map fromEnum ['a' .. 'p']]))
      plain <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n") source fakeFontFiles >>= rows
      wide <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[character-styles.bold]\nfont = \"wide\"\n") source fakeFontFiles >>= rows
      assertBool (show (plain, wide)) (wide > plain),
    testCase "a bold role with its own font embeds it with the bold glyphs only" $ do
      (sans, serif) <- realLatinFonts
      pdf <- miniPdf realProvider True (horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.bold]\nlatin = \"fonts/serif.ttf\"\n\n[character-styles.bold]\nfont = \"bold\"\n") "[bold: Zebra] quick\n" [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)]
      cmaps <- filter ("beginbfchar" `BS.isInfixOf`) <$> inflateAll pdf
      length cmaps @?= 2
      assertBool "bold glyphs only in one font" (any (\c -> "<005a>" `BS.isInfixOf` c && not ("<0071>" `BS.isInfixOf` c)) cmaps)
      qpdfCheck pdf,
    testCase "colour is process CMYK, saved and restored, once per run of a swatch" $ do
      pdf <- miniPdf fakeProvider True (horizontalStyle <> "\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n") "前[color accent: 赤い語]後\n" []
      content <- BS.concat <$> inflateAll pdf
      assertBool "fill" ("q\n0 0.8 1 0 k 0 0.8 1 0 K\n" `BS.isInfixOf` content)
      length (occurrences "0 0.8 1 0 k" content) @?= 1
      let (_, afterColour) = BS.breakSubstring "0 0.8 1 0 k" content
      assertBool "restored" ("Q\n" `BS.isInfixOf` afterColour)
      assertBool "process colour only" (not (any (`BS.isInfixOf` pdf) ["/DeviceRGB", "/Separation", "/DeviceN"])),
    testCase "a character style sets its role and size" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n\n[character-styles.term]\nfont = \"heading\"\nsize = \"2zw\"\n") "本[style term: 語]\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
      assertBool "the heading role's font" ([dFont d | d <- ds, dGlyph d == fromEnum '語'] /= [dFont d | d <- ds, dGlyph d == fromEnum '本'])
      [dSize d | d <- ds, dGlyph d == fromEnum '語'] @?= ["20"],
    testCase "emphasis, styles and colour: parallel and sequential, and two builds, give the same bytes" $ do
      let style = horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[character-styles.italic]\nfont = \"wide\"\n\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n"
          source = "[strong: 強い] [bold: Bold] [italic: Golem と組版] [color accent: 赤 [bold: 太い]]。\n"
      a <- miniPdf fakeProvider True style source fakeFontFiles
      b <- miniPdf fakeProvider False style source fakeFontFiles
      c <- miniPdf fakeProvider True style source fakeFontFiles
      a @?= b
      a @?= c
      qpdfCheck a,
    testCase "HTML: a bold role is declared bold and b names it before the body" $ withSystemTempDirectory "golem-mini" $ \tmp -> do
      BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "[targets.html]\n")
      BS.writeFile (tmp </> "style.toml") "[fonts.body]\nja = \"fonts/b.otf\"\n\n[fonts.gothic]\nja = \"fonts/h.otf\"\n\n[character-styles.bold]\nfont = \"gothic\"\n"
      BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 "[bold: 太い]\n")
      writeFiles tmp fakeFontFiles
      r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
      assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
      cssText <- TIO.readFile (tmp </> "build/html/style.css")
      assertBool (T.unpack cssText) ("@font-face { font-family: \"golem-gothic-ja\"; src: url(\"fonts/h.otf\"); font-weight: bold; }" `T.isInfixOf` cssText)
      assertBool (T.unpack cssText) ("b { font-family: \"golem-gothic-ja\", \"golem-body-ja\", serif; font-weight: bold; }" `T.isInfixOf` cssText)
      assertBool "strong too" ("strong { font-family: \"golem-gothic-ja\", \"golem-body-ja\", serif; font-weight: bold; }" `T.isInfixOf` cssText),
    testCase "the stroke of synthetic bold: 1/80 of the size for Japanese, 1/60 for Latin (golem-driver ADR 0012)" $ do
      syntheticStroke syntheticStrokeJa 655360 @?= 8192
      syntheticStroke syntheticStrokeLatin 655360 @?= 10922
      ja <- miniPdf fakeProvider True horizontalStyle "前の[bold: 本文]後\n" [] >>= fmap (strokeRuns . BS.concat) . inflateAll
      nub [w | (_, Just w, _) <- ja] @?= ["0.125"]
      latin <- miniPdf fakeProvider True horizontalStyle "[bold: Golem]\n" [] >>= fmap (strokeRuns . BS.concat) . inflateAll
      nub [w | (_, Just w, _) <- latin] @?= [TE.encodeUtf8 (spToPt 10922)],
    testCase "Japanese and Latin in one bold run get their own strokes, and the glyphs stay" $ do
      let style = horizontalStyle <> fakeBody
      runs <- miniPdf fakeProvider True style "[bold: 本Golem]\n" fakeFontFiles >>= fmap (strokeRuns . BS.concat) . inflateAll
      widthsOf '本' runs @?= [Just "0.125"]
      widthsOf 'G' runs @?= [Just (TE.encodeUtf8 (spToPt 10922))]
      a <- miniPdf fakeProvider True style "[bold: 本Golem]\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      b <- miniPdf fakeProvider True style "本Golem\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      sort [(dGlyph d, dX d, dY d) | d <- drawnGlyphs a] @?= sort [(dGlyph d, dX d, dY d) | d <- drawnGlyphs b],
    testCase "the stroke follows the size" $ do
      runs <- miniPdf fakeProvider True (horizontalStyle <> "\n[character-styles.big]\nsize = \"2zw\"\n") "[style big: [bold: 本]]\n" [] >>= fmap (strokeRuns . BS.concat) . inflateAll
      widthsOf '本' runs @?= [Just "0.25"],
    testCase "a bold role with Japanese only: Japanese in it without a stroke, Latin synthetic" $ do
      runs <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n\n[character-styles.bold]\nfont = \"heading\"\n") "[bold: 本Golem]\n" fakeFontFiles >>= fmap (strokeRuns . BS.concat) . inflateAll
      widthsOf '本' runs @?= [Nothing]
      widthsOf 'G' runs @?= [Just (TE.encodeUtf8 (spToPt 10922))]
      -- the body role is /F1 and the heading role /F2
      (nub [f | (f, _, gs) <- runs, fromEnum '本' `elem` gs], nub [f | (f, _, gs) <- runs, fromEnum 'G' `elem` gs]) @?= (["/F1"], ["/F2"]),
    testCase "a character style colours its text" $ do
      pdf <- miniPdf fakeProvider True (horizontalStyle <> "\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n\n[character-styles.term]\ncolor = \"accent\"\n") "前[style term: 語]後\n" []
      content <- BS.concat <$> inflateAll pdf
      assertBool "fill" ("0 0.8 1 0 k" `BS.isInfixOf` content),
    testCase "a paragraph style sets the role of its paragraphs" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n\n[paragraph-styles.quote]\nfont = \"heading\"\n") "本\n\n@style quote\n語\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
      ([dFont d | d <- ds, dGlyph d == fromEnum '語'], [dFont d | d <- ds, dGlyph d == fromEnum '本']) @?= (["/F2"], ["/F1"]),
    testCase "a role with one side leaves the other side in the outer face, synthetic" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[character-styles.bold]\nfont = \"wide\"\n") "本[bold: 語Go]\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
      [dFont d | d <- ds, dGlyph d == fromEnum '語'] @?= [dFont d | d <- ds, dGlyph d == fromEnum '本']
      ([dFont d | d <- ds, dGlyph d == fromEnum 'G'], [dFont d | d <- ds, dGlyph d == fromEnum '本']) @?= (["/F2"], ["/F1"])
      assertBool "the Japanese side is synthetic bold" ("2 Tr" `BS.isInfixOf` content)
  ]

wrapTests :: [TestTree]
wrapTests =
  [ testCase "the exclusion of a wrapped figure covers its image and caption" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (wrapped "end" "4zw" <> longPara 30) img
      (_, pf, _, _) <- theFigure pl
      let n = toInteger (length (pfCaption pf))
      (pfAlong pf, pfAcross pf, pfImageLines pf) @?= (40 * pt, 60 * pt, 4)
      n @?= 3
      fmap exLines (pfExclusion pf) @?= Just (fromInteger ((((4 + n - 1) * 15 + 10 + 10) + 14) `div` 15)),
    testCase "lines beside the figure are shorter; the rest of the paragraph is full" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (wrapped "end" "4zw" <> longPara 30) img
      (_, pf, p, slot) <- theFigure pl
      ex <- maybe (assertFailure "no exclusion") pure (pfExclusion pf)
      let beside = [sl | (s, sl) <- linesFrom pl p slot, s < slot + exLines ex]
          rest = [sl | (_, sl) <- linesFrom pl p (slot + exLines ex)]
      length beside @?= exLines ex
      map (lineTarget . slLine) beside @?= replicate (exLines ex) (190 * pt)
      map slIndent beside @?= replicate (exLines ex) 0
      length rest @?= 7
      assertBool "full lines" (all ((== 240 * pt) . lineTarget . slLine) rest),
    testCase "wrap=start indents the lines beside it; the image sits at the line start or end" $ do
      img <- tinyImage
      (geom, pl) <- layoutOk horizontal24 (wrapped "start" "4zw" <> longPara 30) img
      (_, pf, p, slot) <- theFigure pl
      ex <- maybe (assertFailure "no exclusion") pure (pfExclusion pf)
      let ta = typeAreaFor geom (poNumber p)
      map (slIndent . snd) (take (exLines ex) (linesFrom pl p slot)) @?= replicate (exLines ex) (50 * pt)
      rectX (figureRect geom (poNumber p) ta slot pf) @?= rectX ta
      (geom', pl') <- layoutOk horizontal24 (wrapped "end" "4zw" <> longPara 30) img
      (_, pf', p', slot') <- theFigure pl'
      let ta' = typeAreaFor geom' (poNumber p')
          r = figureRect geom' (poNumber p') ta' slot' pf'
      rectX r + rectW r @?= rectX ta' + rectW ta',
    testCase "a paragraph after a short one beside the figure starts short" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (wrapped "end" "4zw" <> "短い段落。\n\n" <> longPara 30) img
      (_, _, p, slot) <- theFigure pl
      case linesFrom pl p slot of
        (_ : (_, second) : _) -> lineTarget (slLine second) @?= 190 * pt
        other -> assertFailure (show (length other)),
    testCase "a heading after a wrapped figure starts below the exclusion" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (wrapped "end" "4zw" <> "# 見出し\n\n本文。\n") img
      (_, pf, p, slot) <- theFigure pl
      ex <- maybe (assertFailure "no exclusion") pure (pfExclusion pf)
      [s | (s, SHeading {}) <- poSlots p] @?= [slot + exLines ex],
    testCase "a wrapped figure that does not fit goes to the next page with its lines" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (longPara 60 <> wrapped "end" "4zw" <> longPara 30) img
      (_, _, p, slot) <- theFigure pl
      (poNumber p, slot) @?= (2, 0)
      case plPages pl of
        (first : _) -> assertBool (show (poSlots first)) (all ((< 26) . fst) (poSlots first))
        [] -> assertFailure "no pages",
    testCase "vertical: the image hangs from the top at its grid line; lines beside it are indented" $ do
      img <- tinyImage
      (geom, pl) <- layoutOk (figStyle pdfStyle) (wrapped "start" "4zw" <> longPara 30) img
      (_, _, p, slot) <- theFigure pl
      (_, pf, _, _) <- theFigure pl
      let ta = typeAreaFor geom (poNumber p)
          r = figureRect geom (poNumber p) ta slot pf
          fs = pgFontSize geom
      rectY r + rectH r @?= rectY ta + rectH ta
      rectX r + rectW r @?= rectX ta + rectW ta - fromIntegral slot * pgLinePitch geom
      ex <- maybe (assertFailure "no exclusion") pure (pfExclusion pf)
      map (slIndent . snd) (take (exLines ex) (linesFrom pl p slot)) @?= replicate (exLines ex) (5 * fs),
    testCase "a width that is not a length, or leaves too short lines, is G07022" $ do
      img <- tinyImage
      a <- layoutMini horizontal24 (wrapped "end" "3em" <> longPara 3) img
      layoutErrors a @?= [("G07022", "回り込む図版の幅が不正です。寸法で書き、行の残りを本文の 8 字分以上にしてください: 3em", FileId 1, 0, 75)]
      b <- layoutMini horizontal24 (wrapped "end" "22zw" <> longPara 3) img
      layoutErrors b @?= [("G07022", "回り込む図版の幅が不正です。寸法で書き、行の残りを本文の 8 字分以上にしてください: 22zw", FileId 1, 0, 76)],
    testCase "a wrapped figure that leaves exactly 8 characters beside it is not G07022; one character wider is" $ do
      -- 24 characters: the width, the gap of 1zw and 8 characters
      img <- tinyImage
      a <- layoutMini horizontal24 (wrapped "end" "15zw" <> longPara 3) img
      layoutErrors a @?= []
      b <- layoutMini horizontal24 (wrapped "end" "16zw" <> longPara 3) img
      map (\(c, m, _, _, _) -> (c, m)) (layoutErrors b) @?= [("G07022", "回り込む図版の幅が不正です。寸法で書き、行の残りを本文の 8 字分以上にしてください: 16zw")],
    testCase "an exclusion longer than the page is G07023 at the figure" $ do
      img <- tinyImage
      let source = "前の段落。\n\n" <> wrapped "end" "10zw" <> longPara 3
      r <- layoutMini (replaceIn "lines = 30" "lines = 10" horizontal24) source img
      layoutErrors r @?= [("G07023", "回り込む図版の除外領域が一ページの行数を超えます（12 行）", FileId 1, 17, 93)],
    testCase "an exclusion as long as the page is not G07023; one line longer is" $ do
      img <- tinyImage
      let source = "前の段落。\n\n" <> wrapped "end" "10zw" <> longPara 3
          errorsAt n = either (map (\d -> (diagCode d, diagMessage d))) (const []) <$> layoutMini (replaceIn "lines = 30" ("lines = " <> T.pack (show n)) horizontal24) source img
      -- the exclusion takes 12 lines
      rs <- mapM (\n -> (n,) <$> errorsAt n) [10 .. 13 :: Int]
      rs @?= [(n, [(DiagnosticCode "G07023", "回り込む図版の除外領域が一ページの行数を超えます（12 行）")]) | n <- [10, 11]] <> [(12, []), (13, [])],
    testCase "a figure that does not wrap takes its image and caption lines; the caption is drawn" $ do
      img <- tinyImage
      let source = "@figure images/tiny.jpg alt=\"t\"\n  キャプション。\n\n後の段落。\n"
      (_, pl) <- layoutOk horizontal24 source img
      (_, pf, p, slot) <- theFigure pl
      (pfImageLines pf, length (pfCaption pf)) @?= (24, 1)
      [s | (s, SLine _) <- poSlots p, s > slot] @?= [slot + 25]
      content <- miniPdf fakeProvider True horizontal24 source img >>= fmap BS.concat . inflateAll
      assertBool "caption glyphs" (fromEnum 'キ' `elem` map dGlyph (drawnGlyphs content)),
    testCase "vertical: a figure that does not wrap is inside the type area" $ do
      img <- tinyImage
      (geom, pl) <- layoutOk (figStyle (replaceIn "characters = 42" "characters = 20" pdfStyle)) "@figure images/tiny.jpg alt=\"t\"\n  キャプション。\n\n後の段落。\n" img
      (_, pf, p, slot) <- theFigure pl
      let ta = typeAreaFor geom (poNumber p)
          r = figureRect geom (poNumber p) ta slot pf
      assertBool (show (r, ta)) (rectX r >= rectX ta && rectX r + rectW r <= rectX ta + rectW ta && rectY r >= rectY ta && rectY r + rectH r <= rectY ta + rectH ta),
    testCase "a page reference beside a wrapped figure converges" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (wrapped "end" "4zw" <> "参照は[ref-page later]ページ。" <> longPara 10 <> longPara 60 <> "@label later\n後の段落。\n") img
      assertBool "pages" (length (plPages pl) >= 2),
    testCase "wrapped figures: parallel and sequential, and two builds, give the same bytes" $ do
      img <- tinyImage
      let source = wrapped "start" "4zw" <> longPara 20 <> wrapped "end" "6zw" <> "短い。\n\n" <> longPara 20
      a <- miniPdf fakeProvider True horizontal24 source img
      b <- miniPdf fakeProvider False horizontal24 source img
      c <- miniPdf fakeProvider True horizontal24 source img
      a @?= b
      a @?= c
      qpdfCheck a
  ]

-- | Every placed sidenote with its page number.
sidenotesOf :: PdfLayout -> [(Int, PlacedSidenote)]
sidenotesOf pl = [(n, ps) | (n, pss) <- Map.toList (plSidenotes pl), ps <- pss]

-- | The grid line of the line that holds the n-th sidenote marker of a page.
slotOfMarker :: PdfLayout -> Int -> Int -> Maybe Int
slotOfMarker pl page k =
  case [slot | p <- plPages pl, poNumber p == page, (slot, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines pl)], _ <- slSidenotes sl] of
    xs | k < length xs -> Just (xs !! k)
    _ -> Nothing

twoLineNote :: T.Text
twoLineNote = "[sidenote: あいうえおかきくけ]"

-- | horizontal24 with a caption style.
captionStyle :: BS.ByteString -> BS.ByteString
captionStyle keys = horizontal24 <> "\n[paragraph-styles.caption]\n" <> keys

-- | A figure that is not wrapped, with a caption of n full-width characters, and a paragraph after it.
figureWith :: Int -> T.Text
figureWith n = "@figure images/tiny.jpg alt=\"t\"\n  " <> T.replicate n "甲" <> "\n\n後の段落。\n"

-- | The grid line of the first line after a figure, from the figure's first grid line.
afterFigure :: PdfLayout -> IO Int
afterFigure pl = do
  (_, _, p, slot) <- theFigure pl
  case [s | (s, SLine _) <- poSlots p, s > slot] of
    (s : _) -> pure (s - slot)
    [] -> assertFailure "no line after the figure"

captionTests :: [TestTree]
captionTests =
  [ testCase "a small wrapped caption: its size, its pitch and the exclusion" $ do
      img <- tinyImage
      (_, pl) <- layoutOk (captionStyle "size = \"8pt\"\n") (wrapped "end" "4zw" <> longPara 30) img
      (_, pf, _, _) <- theFigure pl
      (pfCaptionSize pf, pfCaptionPitch pf) @?= (8 * pt, 12 * pt)
      let n = toInteger (length (pfCaption pf))
      fmap exLines (pfExclusion pf) @?= Just (fromInteger ((4 * 15 + (n - 1) * 12 + 8 + 10 + 14) `div` 15)),
    testCase "a small caption takes fewer grid lines; the text after it stays on the grid" $ do
      img <- tinyImage
      (_, pl) <- layoutOk (captionStyle "size = \"6pt\"\n") (figureWith 100) img
      (_, pf, _, _) <- theFigure pl
      (length (pfCaption pf), pfCaptionPitch pf, pfCaptionSpan pf) @?= (3, 9 * pt, 2)
      afterFigure pl >>= (@?= 24 + 2)
      (_, plain) <- layoutOk horizontal24 (figureWith 100) img
      (_, pf', _, _) <- theFigure plain
      length (pfCaption pf') @?= 5
      afterFigure plain >>= (@?= 24 + 5),
    testCase "the caption is drawn at its size from the top of its grid lines" $ do
      img <- tinyImage
      let style = captionStyle "size = \"6pt\"\n"
      (geom, pl) <- layoutOk style (figureWith 100) img
      (_, _, p, slot) <- theFigure pl
      pdf <- miniPdf fakeProvider True style (figureWith 100) img
      content <- BS.concat <$> inflateAll pdf
      let ta = typeAreaFor geom (poNumber p)
          top = toRational (unSp (rectY ta + rectH ta)) / 65536
          ys = sortOn negate (nub [ptToRational (dY d) | d <- drawnGlyphs content, dSize d == "6"])
          first = top - toRational (unSp (fromIntegral (slot + 24) * 15 * pt + Sp (round (toRational (unSp (6 * pt)) * baselineRatio)))) / 65536
      case ys of
        (y1 : y2 : _) -> do
          assertBool (show (y1, first)) (abs (y1 - first) < 1 / 100)
          assertBool (show (y1, y2)) (abs (y1 - y2 - 9) < 1 / 100)
        other -> assertFailure (show other),
    testCase "a caption role sets the caption, the body stays in the body role" $ do
      img <- tinyImage
      content <- miniPdf fakeProvider True (captionStyle "font = \"heading\"\n" <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n") (figureWith 4) (img <> fakeFontFiles) >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
      (nub [dFont d | d <- ds, dGlyph d == fromEnum '甲'], nub [dFont d | d <- ds, dGlyph d == fromEnum '後']) @?= (["/F2"], ["/F1"]),
    testCase "a small caption fits where a body-size one is G07023" $ do
      img <- tinyImage
      let short = replaceIn "lines = 30" "lines = 8" horizontal24
          source = "@figure images/tiny.jpg alt=\"t\" wrap=end width=4zw\n  " <> T.replicate 14 "甲" <> "\n\n" <> longPara 2
      (errs, _) <- buildMini fakeProvider True short source img
      errs @?= [DiagnosticCode "G07023"]
      layoutMini short source img >>= (@?= [("G07023", "回り込む図版の除外領域が一ページの行数を超えます（10 行）", FileId 1, 0, 96)]) . layoutErrors
      (errs', _) <- buildMini fakeProvider True (short <> "\n[paragraph-styles.caption]\nsize = \"5pt\"\n") source img
      errs' @?= [],
    testCase "vertical: the caption is in the type area, its first centre line half its size from the grid" $ do
      img <- tinyImage
      let style = figStyle (replaceIn "characters = 42" "characters = 20" pdfStyle) <> "\n[paragraph-styles.caption]\nsize = \"10Q\"\n"
          q = maybe 0 (dimToSp 0) (parseDim "10Q")
      (geom, pl) <- layoutOk style (figureWith 10) img
      (_, pf, p, slot) <- theFigure pl
      pdf <- miniPdf fakeProvider True style (figureWith 10) img
      content <- BS.concat <$> inflateAll pdf
      let ta = typeAreaFor geom (poNumber p)
          right = toRational (unSp (rectX ta + rectW ta)) / 65536
          xs = sortOn negate (nub [ptToRational (dX d) | d <- drawnGlyphs content, dGlyph d == fromEnum '甲'])
          expected = right - toRational (unSp (fromIntegral (slot + pfImageLines pf) * pgLinePitch geom + Sp (unSp q `div` 2))) / 65536
      case xs of
        (x : _) -> do
          assertBool (show (x, expected)) (abs (x - expected) < 1 / 100)
          assertBool "in the type area" (x > toRational (unSp (rectX ta)) / 65536)
        [] -> assertFailure "no caption glyph",
    testCase "naming the body role and size changes nothing" $ do
      img <- tinyImage
      a <- miniPdf fakeProvider True (horizontal24 <> fakeBody) (figureWith 30) (img <> fakeFontFiles)
      b <- miniPdf fakeProvider True (captionStyle "font = \"body\"\nsize = \"10pt\"\n" <> fakeBody) (figureWith 30) (img <> fakeFontFiles)
      c1 <- BS.concat <$> inflateAll a
      c2 <- BS.concat <$> inflateAll b
      drawnGlyphs c1 @?= drawnGlyphs c2,
    testCase "a caption based on another style takes its size" $ do
      img <- tinyImage
      (_, pl) <- layoutOk (horizontal24 <> "\n[paragraph-styles.note]\nsize = \"8pt\"\n\n[paragraph-styles.caption]\nbased-on = \"note\"\n") (figureWith 10) img
      (_, pf, _, _) <- theFigure pl
      pfCaptionSize pf @?= 8 * pt,
    testCase "the indents of body do not move the caption (golem-driver ADR 0043)" $ do
      img <- tinyImage
      a <- miniPdf fakeProvider True horizontal24 (figureWith 30) img >>= fmap BS.concat . inflateAll
      b <- miniPdf fakeProvider True (horizontal24 <> "\n[paragraph-styles.body]\nindent = \"2zw\"\nfirst-line-indent = \"1zw\"\n") (figureWith 30) img >>= fmap BS.concat . inflateAll
      [d | d <- drawnGlyphs a, dGlyph d == fromEnum '甲'] @?= [d | d <- drawnGlyphs b, dGlyph d == fromEnum '甲'],
    testCase "small captions: parallel and sequential, and two builds, give the same bytes" $ do
      img <- tinyImage
      let style = captionStyle "size = \"7pt\"\n"
          source = wrapped "start" "4zw" <> longPara 20 <> figureWith 60
      a <- miniPdf fakeProvider True style source img
      b <- miniPdf fakeProvider False style source img
      c <- miniPdf fakeProvider True style source img
      a @?= b
      a @?= c
      qpdfCheck a,
    testCase "with real fonts the caption font holds the caption's glyphs only" $ do
      (sans, serif) <- realLatinFonts
      img <- tinyImage
      let style = horizontal24 <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.caption]\nlatin = \"fonts/serif.ttf\"\n\n[paragraph-styles.caption]\nfont = \"caption\"\n"
      pdf <- miniPdf realProvider True style "@figure images/tiny.jpg alt=\"t\"\n  Zebra\n\nquick\n" (img <> [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)])
      cmaps <- filter ("beginbfchar" `BS.isInfixOf`) <$> inflateAll pdf
      length cmaps @?= 2
      assertBool "caption glyphs only in one font" (any (\c -> "<005a>" `BS.isInfixOf` c && not ("<0071>" `BS.isInfixOf` c)) cmaps)
      assertBool "body glyphs only in the other" (any (\c -> "<0071>" `BS.isInfixOf` c && not ("<005a>" `BS.isInfixOf` c)) cmaps)
      qpdfCheck pdf,
    testCase "HTML: figcaption takes the caption's font and size relative to the grid" $ do
      let css keys = withSystemTempDirectory "golem-mini" $ \tmp -> do
            BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "[targets.html]\n")
            BS.writeFile (tmp </> "style.toml") (horizontalStyle <> "\n[fonts.caption]\nlatin = \"fonts/c.otf\"\n\n[paragraph-styles.caption]\n" <> keys)
            BS.writeFile (tmp </> "a.gm") "x\n"
            createDirectoryIfMissing True (tmp </> "fonts")
            BS.writeFile (tmp </> "fonts/c.otf") "fake"
            r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
            assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
            TIO.readFile (tmp </> "build/html/style.css")
      a <- css "font = \"caption\"\nsize = \"8pt\"\n"
      assertBool (T.unpack a) ("figcaption { font-family: \"golem-caption-latin\", serif; font-size: 0.8em; }" `T.isInfixOf` a)
      b <- css "size = \"0.85zw\"\n"
      assertBool (T.unpack b) ("figcaption { font-size: 0.85em; }" `T.isInfixOf` b),
    testCase "a font size in CSS is relative to the grid's size, or in pt without a page" $ do
      let styleOf src = either (\ds -> assertFailure (show ds) >> error "unreachable") pure (parseStyle (FileId 0) src)
          dim t = fromMaybe (Abs 0) (parseDim t)
      s13 <- styleOf "[page]\nsize = \"B6\"\n\n[page.grid]\nfont-size = \"13Q\"\ncharacters = 30\nlines = 20\nline-pitch = \"22H\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n"
      cssFontSize s13 (dim "11Q") @?= "0.8462em"
      cssFontSize s13 (dim "0.85zw") @?= "0.85em"
      none <- styleOf ""
      cssFontSize none (dim "9pt") @?= "9pt"
  ]

sidenoteTests :: [TestTree]
sidenoteTests =
  [ testCase "a sidenote sits on the page of its marker, level with the marker line" $ do
      (_, pl) <- layoutOk sidenoteStyle (fillers 3 <> "本文[sidenote: 注]。\n") []
      case sidenotesOf pl of
        [(page, ps)] -> do
          page @?= 1
          Just (psTop ps) @?= fmap (\k -> fromIntegral k * 15 * pt) (slotOfMarker pl 1 0)
        other -> assertFailure (show (length other)),
    testCase "notes on neighbouring lines are pushed down in order, half a pitch apart" $ do
      (_, pl) <- layoutOk sidenoteStyle ("一" <> twoLineNote <> "\n\n二" <> twoLineNote <> "\n") []
      case map snd (sidenotesOf pl) of
        [a, b] -> do
          length (psLines a) @?= 2
          psTop b @?= psTop a + 20 * pt + Sp (unSp (15 * pt) `div` 2)
        other -> assertFailure (show (length other)),
    testCase "notes at the foot of the page pull earlier ones up" $ do
      (_, pl) <- layoutOk sidenoteStyle (fillers 28 <> "一" <> twoLineNote <> "\n\n二" <> twoLineNote <> "\n") []
      case [ps | (1, ps) <- sidenotesOf pl] of
        [a, b] -> do
          psTop b + 20 * pt @?= 445 * pt
          assertBool "pulled up" (psTop a < 28 * 15 * pt)
        other -> assertFailure (show (length other)),
    testCase "sidenotes that do not fit, or one taller than the column, are G07033" $ do
      let crowded = T.concat (replicate 30 ("一[sidenote: " <> T.replicate 3 "あいうえおかき" <> "]\n\n"))
      r <- layoutMini sidenoteStyle crowded []
      case r of
        Left [d] -> do
          diagCode d @?= DiagnosticCode "G07033"
          diagMessage d @?= "このページの傍注が傍注の領域に収まりません"
          assertBool "at a sidenote" (spanStart (diagSpan d) `elem` offsetsIn "[sidenote" crowded)
        other -> assertFailure (show (either (map diagCode) (const []) other))
      r' <- layoutMini sidenoteStyle ("一[sidenote: " <> T.replicate 60 "あいうえおかき" <> "]\n") []
      either (map (\d -> (diagCode d, diagMessage d))) (const []) r' @?= [(DiagnosticCode "G07033", "傍注が傍注の領域より高く、収まりません")],
    testCase "the length of a sidenote does not change the pages" $ do
      let source body = fillers 20 <> "本文[sidenote: " <> body <> "]。" <> longPara 20
      (_, a) <- layoutOk sidenoteStyle (source "短い。") []
      (_, b) <- layoutOk sidenoteStyle (source (T.replicate 4 "長い傍注の本文。")) []
      plPages a @?= plPages b,
    testCase "a sidenote follows its line to the next page" $ do
      (_, pl) <- layoutOk sidenoteStyle (fillers 28 <> T.replicate 3 "あいうえおかきくけこさし" <> "あいう[sidenote: 注]え\n") []
      map fst (sidenotesOf pl) @?= [2],
    testCase "markers: a symbol in the text and the note; none leaves no box and no prefix" $ do
      content <- miniPdf fakeProvider True (sidenoteStyle <> "marker = \"symbol\"\n") "本文[sidenote: 注]。\n" [] >>= fmap BS.concat . inflateAll
      length (filter ((== 0x203B) . dGlyph) (drawnGlyphs content)) @?= 2
      (_, none) <- layoutOk (sidenoteStyle <> "marker = \"none\"\n") "本文[sidenote: 注]。\n" []
      (_, plain) <- layoutOk sidenoteStyle "本文。\n" []
      let boxes pl = length [() | sl <- Map.elems (plLines pl), Box {} <- lineItems (slLine sl)]
      boxes none @?= boxes plain
      case map snd (sidenotesOf none) of
        [ps] -> [bcText c | l <- take 1 (psLines ps), Box _ c <- take 1 (lineItems l)] @?= ["注"]
        other -> assertFailure (show (length other)),
    testCase "sidenotes need a horizontal page with a sidenote column, and the text flow" $ do
      a <- layoutMini horizontalStyle "本文[sidenote: 注]。\n" []
      either (map (\d -> (diagCode d, diagMessage d))) (const []) a @?= [(DiagnosticCode "G07034", "傍注の領域（style.toml の [sidenotes]）のない版面では傍注を使えません")]
      b <- layoutMini pdfStyle "本文[sidenote: 注]。\n" []
      either (map diagCode) (const []) b @?= [DiagnosticCode "G07032"]
      c <- layoutMini sidenoteStyle "本文[note: 注の[sidenote: 傍注]本文]。\n" []
      layoutErrors c @?= [("G07035", "PDF では、脚注の本文と図版のキャプションの中に傍注を置けません", FileId 1, 19, 37)]
      img <- tinyImage
      d <- layoutMini (figStyle sidenoteStyle) "@figure images/tiny.jpg alt=\"t\"\n  キャプション[sidenote: 傍注]。\n" img
      layoutErrors d @?= [("G07035", "PDF では、脚注の本文と図版のキャプションの中に傍注を置けません", FileId 1, 52, 70)],
    testCase "sidenote text is drawn in the sidenote column at its size" $ do
      content <- miniPdf fakeProvider True sidenoteStyle "本文[sidenote: 注]。\n" [] >>= fmap BS.concat . inflateAll
      geom <- either (assertFailure . show) pure (parseStyle (FileId 0) (TE.decodeUtf8 sidenoteStyle) >>= pageGeometry (FileId 0) False)
      area <- maybe (assertFailure "no column") pure (sidenoteAreaFor geom 1)
      let small = [d | d <- drawnGlyphs content, dSize d == "8"]
      length small @?= 2
      assertBool (show (map dX small)) (TE.encodeUtf8 (spToPt (rectX area)) `elem` map dX small),
    testCase "the indents of body do not move the sidenote (golem-driver ADR 0043)" $ do
      let source = "本文[sidenote: 傍注の本文が二行にわたる長さです]。\n"
      a <- miniPdf fakeProvider True sidenoteStyle source [] >>= fmap BS.concat . inflateAll
      b <- miniPdf fakeProvider True (sidenoteStyle <> "\n[paragraph-styles.body]\nindent = \"2zw\"\nfirst-line-indent = \"1zw\"\n") source [] >>= fmap BS.concat . inflateAll
      let small c = [d | d <- drawnGlyphs c, dSize d == "8"]
      assertBool "sidenote glyphs" (length (small a) > 6)
      small a @?= small b,
    testCase "a page reference in a sidenote converges" $ do
      (_, pl) <- layoutOk sidenoteStyle ("本文[sidenote: [ref-page later]ページを参照。]。\n\n" <> longPara 60 <> "@label later\n後。\n") []
      length (sidenotesOf pl) @?= 1,
    testCase "sidenotes: parallel and sequential, and two builds, give the same bytes" $ do
      let source = fillers 5 <> "一" <> twoLineNote <> "\n\n二" <> twoLineNote <> "\n\n" <> longPara 20
      a <- miniPdf fakeProvider True sidenoteStyle source []
      b <- miniPdf fakeProvider False sidenoteStyle source []
      c <- miniPdf fakeProvider True sidenoteStyle source []
      a @?= b
      a @?= c
      qpdfCheck a,
    testCase "the roles the PDF uses include the sidenote's (golem-driver ADR 0011)" $ do
      s <- either (assertFailure . show) pure (parseStyle (FileId 0) "[fonts.body]\nja = \"b.otf\"\n\n[fonts.heading]\nja = \"h.otf\"\n\n[paragraph-styles.sidenote]\nfont = \"heading\"\n")
      usedRoles s [] @?= ["body", "heading"],
    testCase "a sidenote role sets the note and its number; the text and its marker stay in the body" $ do
      content <- miniPdf fakeProvider True (sidenoteStyleWith "font = \"heading\"\n" <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n") "本文[sidenote: 注]。\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          fontsOf c sz = nub [dFont d | d <- ds, dGlyph d == fromEnum c, dSize d == sz]
      fontsOf '注' "8" @?= fontsOf '1' "8"
      (fontsOf '注' "8", fontsOf '本' "10") @?= (["/F2"], ["/F1"])
      nub [dFont d | d <- ds, dGlyph d == fromEnum '1', dSize d /= "8"] @?= fontsOf '本' "10",
    testCase "a sidenote role measures the note in its own font" $ do
      let note = "本文[sidenote: abcdefghijklmnopqrstuvwxyz]。\n"
          linesOf style = do
            (_, pl) <- layoutOk style note fakeFontFiles
            pure (sum [length (psLines ps) | (_, ps) <- sidenotesOf pl])
      plain <- linesOf (sidenoteStyle <> fakeBody)
      wide <- linesOf (sidenoteStyleWith "font = \"wide\"\n" <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n")
      assertBool (show (plain, wide)) (wide > plain),
    testCase "naming the body role changes nothing" $ do
      let source = "本文[sidenote: 傍注の本文はここにある。]。\n"
      a <- miniPdf fakeProvider True (sidenoteStyle <> fakeBody) source fakeFontFiles
      b <- miniPdf fakeProvider True (sidenoteStyleWith "font = \"body\"\n" <> fakeBody) source fakeFontFiles
      -- style.toml is an input of the instance ID (golem-pdf ADR 0004), so the trailer differs
      let withoutId pdf = fst (BS.breakSubstring "/ID [" pdf)
      withoutId a @?= withoutId b,
    testCase "a character style inside a sidenote takes its own role" $ do
      content <- miniPdf fakeProvider True (sidenoteStyle <> fakeBody <> "\n[fonts.wide]\nja = \"fonts/w.otf\"\n\n[character-styles.bold]\nfont = \"wide\"\n") "本文[sidenote: 注の[bold: 語]。]。\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          fontsOf c = nub [dFont d | d <- ds, dGlyph d == fromEnum c]
      assertBool "the bold role" (fontsOf '語' /= fontsOf '注')
      fontsOf '注' @?= fontsOf '本',
    testCase "sidenote roles: parallel and sequential, and two builds, give the same bytes" $ do
      let style = sidenoteStyleWith "font = \"heading\"\n" <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n"
          files = fakeFontFiles
          source = fillers 5 <> "一" <> twoLineNote <> "\n\n二" <> twoLineNote <> "\n\n" <> longPara 20
      a <- miniPdf fakeProvider True style source files
      b <- miniPdf fakeProvider False style source files
      c <- miniPdf fakeProvider True style source files
      a @?= b
      a @?= c
      qpdfCheck a,
    testCase "with real fonts the sidenote font holds the sidenote's glyphs only" $ do
      (sans, serif) <- realLatinFonts
      let style = sidenoteStyleWith "font = \"note\"\n" <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.note]\nlatin = \"fonts/serif.ttf\"\n"
      pdf <- miniPdf realProvider True style "quick[sidenote: Zebra] quick\n" [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)]
      cmaps <- filter ("beginbfchar" `BS.isInfixOf`) <$> inflateAll pdf
      length cmaps @?= 2
      assertBool "sidenote glyphs only in one font" (any (\c -> "<005a>" `BS.isInfixOf` c && not ("<0071>" `BS.isInfixOf` c)) cmaps)
      assertBool "body glyphs only in the other" (any (\c -> "<0071>" `BS.isInfixOf` c && not ("<005a>" `BS.isInfixOf` c)) cmaps)
      qpdfCheck pdf,
    testCase "HTML: .sidenote takes the sidenote's font and size" $ do
      let css keys = withSystemTempDirectory "golem-mini" $ \tmp -> do
            BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "[targets.html]\n")
            BS.writeFile (tmp </> "style.toml") (horizontalStyle <> "\n[fonts.note]\nlatin = \"fonts/n.otf\"\n\n[paragraph-styles.sidenote]\n" <> keys)
            BS.writeFile (tmp </> "a.gm") "x\n"
            createDirectoryIfMissing True (tmp </> "fonts")
            BS.writeFile (tmp </> "fonts/n.otf") "fake"
            r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
            assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
            TIO.readFile (tmp </> "build/html/style.css")
      a <- css "font = \"note\"\nsize = \"8pt\"\n"
      assertBool (T.unpack a) (".sidenote { font-family: \"golem-note-latin\", serif; font-size: 0.8em; }" `T.isInfixOf` a)
      b <- css "size = \"8pt\"\n"
      assertBool (T.unpack b) (".sidenote { font-size: 0.8em; }" `T.isInfixOf` b)
      c <- css "font = \"note\"\n"
      assertBool (T.unpack c) (".sidenote { font-family: \"golem-note-latin\", serif; font-size: 0.85em; }" `T.isInfixOf` c)
  ]
