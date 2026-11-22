-- | Notes numbered per page, after the marks reserve their width (docs/adr/0383).
module PageNoteNumbersSpec (pageNoteNumbersTests) where

import Control.Monad (forM_, unless)
import Data.ByteString qualified as BS
import Data.List (isSuffixOf, nub, sortOn)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Layout.Japanese (BoxKind (..), boxKind)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Paginate (PageOutAt (..), Slotted (..))
import Golem.Project.Style (Sp (..))
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..), Severity (..), SrcSpan (..))
import Golem.Typeset (PdfLayout (..), SetLine (..), layoutPdf, layoutPdfUnnumbered)
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | sidenoteStyle (12 characters a line, 30 lines a page, a sidenote column) with the notes numbered per page.
pageStyle :: BS.ByteString
pageStyle = sidenoteStyleWith "" <> "\n[notes]\nnumbering = \"page\"\n"

-- | What a paragraph of a test source holds: one character of text, a note or a sidenote after one.
data Para = Filler | WithNote | WithSidenote
  deriving stock (Eq, Show)

-- | The source of paragraphs: the notes and the sidenotes have bodies of their own.
sourceOf :: [Para] -> T.Text
sourceOf ps = T.concat (zipWith para [1 :: Int ..] ps)
  where
    para k = \case
      Filler -> "あ\n\n"
      WithNote -> "本[note: 注" <> T.pack (show k) <> "。]\n\n"
      WithSidenote -> "本[sidenote: 傍]\n\n"

-- | The marks of notes in a line: its boxes of the kind of a mark, with their widths and texts.
marksIn :: Line -> [(Integer, T.Text)]
marksIn l = [(unSp w, bcText c) | Box w c <- lineItems l, boxKind c == KindNoteMark]

{- | The marks in the text of each page, in the order of the slots: whether
each is a note (its format is *{n}) or a sidenote (its number alone), and
its number.
-}
callsByPage :: PdfLayout -> [(Int, [(Bool, Int)])]
callsByPage pl =
  [ (poNumber p, [(T.isPrefixOf "*" t, read (T.unpack (T.dropWhile (== '*') t))) | (_, SLine lid) <- sortOn fst (poSlots p), Just sl <- [Map.lookup lid (plLines pl)], (_, t) <- marksIn (slLine sl)])
  | p <- gridPages pl
  ]

-- | The number of each footnote at the start of its body, on the page that shows the start.
bodyMarksByPage :: PdfLayout -> [(Int, [Int])]
bodyMarksByPage pl =
  [ (poNumber p, [read (T.unpack (T.dropWhile (== '*') t)) | (nid, 0, _) <- poFootnotes p, Just (l : _) <- [Map.lookup nid bodies], (_, t) <- take 1 (marksIn l)])
  | p <- gridPages pl
  ]
  where
    bodies = Map.fromList [(k, ls) | sl <- Map.elems (plLines pl), (k, ls) <- slNotes sl]

layoutOf :: T.Text -> IO PdfLayout
layoutOf src = layoutMini pageStyle src [] >>= either (assertFailure . show) (pure . snd)

-- | Each page numbers the marks of each channel 1, 2, … in the order of the text.
consecutive :: PdfLayout -> Assertion
consecutive pl = forM_ (callsByPage pl) $ \(n, calls) ->
  forM_ [True, False] $ \isNote ->
    let ks = [k | (c, k) <- calls, c == isNote]
     in assertEqual ("page " <> show n <> (if isNote then " notes" else " sidenotes")) [1 .. length ks] ks

-- | The test sources: runs of fillers between notes and sidenotes, over several pages.
sources :: [[Para]]
sources =
  [ concat (replicate k (replicate gap Filler <> [kind]))
  | gap <- [0, 3, 7, 12],
    k <- [1, 4, 9],
    kind <- [WithNote, WithSidenote]
  ]
    <> [concat (replicate 6 (replicate gap Filler <> [WithNote, WithSidenote, WithNote])) | gap <- [1, 5, 11]]

pageNoteNumbersTests :: [TestTree]
pageNoteNumbersTests =
  [ testCase "root ADR 0402 I3: chapter-end page numbering warns once at the first repeated number" $ do
      let prefix = "甲[note: 一。]\n\n@page-break\n\n乙"
          src = prefix <> "[note: 二。]\n\n@page-break\n\n丙[note: 三。]\n"
      (ds, files) <- buildFor [TargetPdf] (pageStyle <> "placement = \"chapter-end\"\n") src
      let warnings = [d | d <- ds, diagCode d == DiagnosticCode "G07132"]
      map diagSeverity warnings @?= [Warning]
      map (spanStart . diagSpan) warnings @?= [BS.length (TE.encodeUtf8 prefix)]
      assertBool "PDF is still written" (any ((".pdf" `isSuffixOf`) . fst) files),
    testCase "root ADR 0402 I3: chapter-end notes on one page have no duplicate warning" $ do
      (ds, _) <- buildFor [TargetPdf] (pageStyle <> "placement = \"chapter-end\"\n") "甲[note: 一。]乙[note: 二。]\n"
      [d | d <- ds, diagCode d == DiagnosticCode "G07132"] @?= [],
    testCase "root ADR 0402 I3: repeated numbers warn independently for each chapter" $ do
      let manifest = replaceIn "chapters = [\"a.gm\"]" "chapters = [\"a.gm\", \"b.gm\"]" miniManifest
          src = "甲[note: 一。]\n\n@page-break\n\n乙[note: 二。]\n"
      (ds, _) <- buildForFiles [TargetPdf] manifest (pageStyle <> "placement = \"chapter-end\"\n") [("a.gm", src), ("b.gm", "@page-break\n\n" <> src)]
      let warnings = [d | d <- ds, diagCode d == DiagnosticCode "G07132"]
      map diagSeverity warnings @?= [Warning, Warning]
      length (nub (map (spanFile . diagSpan) warnings)) @?= 2,
    testCase "root ADR 0402 I1: outputs without fixed pages use book numbering and warn once" $ do
      let src = "甲[note: 一。]\n\n@page-break\n\n乙[note: 二。]\n"
      (ds, files) <- buildFor [TargetHtml, TargetEpub, TargetText] pageStyle src
      (_, reference) <- buildFor [TargetText] (replaceIn "numbering = \"page\"" "numbering = \"book\"" pageStyle) src
      [diagSeverity d | d <- ds, diagCode d == DiagnosticCode "G03259"] @?= [Warning]
      [d | d <- ds, diagCode d == DiagnosticCode "G07132"] @?= []
      [b | (p, b) <- files, ".txt" `isSuffixOf` p] @?= [b | (p, b) <- reference, ".txt" `isSuffixOf` p],
    testCase "root ADR 0402 I2: adding HTML leaves the generated PDF unchanged" $ do
      let src = "甲[note: 一。]\n\n@page-break\n\n乙[note: 二。]\n"
      (_, alone) <- buildFor [TargetPdf] pageStyle src
      (ds, combined) <- buildFor [TargetPdf, TargetHtml] pageStyle src
      [diagSeverity d | d <- ds, diagCode d == DiagnosticCode "G03259"] @?= [Warning]
      [b | (p, b) <- alone, ".pdf" `isSuffixOf` p] @?= [b | (p, b) <- combined, ".pdf" `isSuffixOf` p],
    testCase "ADR 0383 I1: inv1_page_local_note_numbers_property" $ do
      -- the sources put two marks of a channel or more on one page, and marks on several pages
      pls <- mapM (layoutOf . sourceOf) sources
      assertBool "two on a page" (or [length [() | (c, _) <- calls, c] >= 2 | pl <- pls, (_, calls) <- callsByPage pl])
      assertBool "several pages" (or [length [() | (_, cs) <- callsByPage pl, not (null cs)] >= 3 | pl <- pls])
      forM_ sources $ \ps -> do
        pl <- layoutOf (sourceOf ps)
        -- every mark is on a page: as many as the notes and the sidenotes of the source
        length (concatMap snd (callsByPage pl)) @?= length (filter (/= Filler) ps)
        consecutive pl
        -- the body of each footnote starts with the number of its mark in the text
        forM_ (zip (callsByPage pl) (bodyMarksByPage pl)) $ \((n, calls), (_, bodies)) ->
          assertEqual ("bodies on page " <> show n) [k | (True, k) <- calls] bodies,
    testCase "ADR 0383 I1: inv1_page_local_note_numbers_case_1: no note reserves nothing" $ do
      let src = sourceOf (replicate 40 Filler)
      pl <- layoutOf src
      ref <- layoutMini (sidenoteStyleWith "" <> "\n[notes]\nnumbering = \"book\"\n") src [] >>= either (assertFailure . show) (pure . snd)
      -- no mark, and the lines as wide as without the numbering per page
      concatMap (marksIn . slLine) (Map.elems (plLines pl)) @?= []
      map (lineWidths . slLine) (Map.elems (plLines pl)) @?= map (lineWidths . slLine) (Map.elems (plLines ref))
      gridPages pl @?= gridPages ref,
    testCase "ADR 0383 I1: inv1_page_local_note_numbers_case_2: two notes on one page are 1 and 2" $ do
      pl <- layoutOf (sourceOf [WithNote, Filler, WithNote])
      callsByPage pl @?= [(1, [(True, 1), (True, 2)])]
      bodyMarksByPage pl @?= [(1, [1, 2])],
    testCase "ADR 0383 I1: inv1_page_local_note_numbers_case_3: the first note of the next page is 1" $ do
      pl <- layoutOf (sourceOf ([WithNote, WithNote] <> replicate 40 Filler <> [WithNote]))
      let pages = [(n, calls) | (n, calls) <- callsByPage pl, not (null calls)]
      case pages of
        [(1, first), (_, second)] -> do
          first @?= [(True, 1), (True, 2)]
          second @?= [(True, 1)]
        _ -> assertFailure (show pages),
    testCase "ADR 0383 I1: inv1_page_local_note_numbers_case_4: numbering the pages breaks no page again" $ do
      -- 12 notes: the marks before the numbering run to *12, those of the pages are short
      let src = sourceOf (concat (replicate 12 [WithNote, Filler, Filler, Filler, Filler, Filler]))
      r <- withMiniInput fakeProvider miniManifest pageStyle src [] $ \inp geom fonts -> do
        unnumbered <- layoutPdfUnnumbered inp geom fonts
        numbered <- layoutPdf inp geom fonts
        pure (unnumbered, numbered)
      case r of
        Right (Right unnumbered, Right numbered) -> do
          -- the pages, the lines and every width are those before the numbers
          gridPages numbered @?= gridPages unnumbered
          map (lineWidths . slLine) (Map.elems (plLines numbered)) @?= map (lineWidths . slLine) (Map.elems (plLines unnumbered))
          [map lineWidths ls | sl <- Map.elems (plLines numbered), (_, ls) <- slNotes sl] @?= [map lineWidths ls | sl <- Map.elems (plLines unnumbered), (_, ls) <- slNotes sl]
          -- only the numbers change: the marks before run to 12, those after start again on each page
          let numbersOf pl = [t | sl <- Map.elems (plLines pl), (_, t) <- marksIn (slLine sl)]
          numbersOf unnumbered @?= ["*" <> T.pack (show k) | k <- [1 .. 12 :: Int]]
          unless (length [() | (_, cs) <- callsByPage numbered, not (null cs)] >= 2) (assertFailure "the notes are on one page")
          consecutive numbered
          -- every mark in the text keeps the width of the widest number
          length (nub [w | sl <- Map.elems (plLines numbered), (w, _) <- marksIn (slLine sl)]) @?= 1
        other -> assertFailure (show (either show (const "layout failed") other)),
    testCase "ADR 0383: the list at the end of the chapter takes the numbers of the pages of the marks" $ do
      let src = sourceOf ([WithNote, WithNote] <> replicate 40 Filler <> [WithNote])
      pl <- layoutMini (pageStyle <> "placement = \"chapter-end\"\n") src [] >>= either (assertFailure . show) (pure . snd)
      -- the marks in the text, then those of the list, in the order of the lines
      [k | (_, cs) <- callsByPage pl, (True, k) <- cs] @?= [1, 2, 1, 1, 2, 1],
    testGroup
      "G03259"
      [ testCase "the outputs without fixed pages warn and number in the order of the book; the PDF alone does not" $ do
          let src = "甲[note: 甲注。]乙[note: 乙注。]\n"
          (pdf, _) <- buildFor [TargetPdf] pageStyle src
          [c | c <- codesOf pdf, c == "G03259"] @?= []
          forM_ [TargetHtml, TargetEpub, TargetText] $ \t -> do
            (ds, files) <- buildFor [t] pageStyle src
            [(diagSeverity d, spanStart (diagSpan d)) | d <- ds, diagCode d == DiagnosticCode "G03259"] @?= [(Warning, 3)]
            -- the output is written
            assertBool (show t) (any (\(p, _) -> any (`isSuffixOf` p) [".xhtml", ".epub", ".txt"]) files),
        testCase "a book without notes, or of another numbering, gives none" $ do
          (none, _) <- buildFor [TargetHtml] pageStyle "本文。\n"
          [c | c <- codesOf none, c == "G03259"] @?= []
          (book, _) <- buildFor [TargetHtml] (sidenoteStyleWith "" <> "\n[notes]\nnumbering = \"book\"\n") "甲[note: 甲注。]\n"
          [c | c <- codesOf book, c == "G03259"] @?= []
      ]
  ]
  where
    lineWidths l = [unSp w | Box w _ <- lineItems l]

-- | Builds a one-file book for targets: the diagnostics and the files written.
buildFor :: [Target] -> BS.ByteString -> T.Text -> IO ([Diagnostic], [(FilePath, BS.ByteString)])
buildFor targets style source = buildForFiles targets miniManifest style [("a.gm", source)]

buildForFiles :: [Target] -> BS.ByteString -> BS.ByteString -> [(FilePath, T.Text)] -> IO ([Diagnostic], [(FilePath, BS.ByteString)])
buildForFiles targets manifest style sourceFiles = withSystemTempDirectory "golem-page-notes" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (manifest <> "\n[targets.html]\n\n[targets.epub]\n\n[targets.text]\nvariants = [\"horizontal\"]\n")
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  writeFiles tmp (bodyFontFiles style)
  writeTexts tmp sourceFiles
  r <- build (defaultOptions tmp) {optTargets = Just targets, optFonts = fakeProvider}
  files <- mapM (\p -> (drop (length tmp + 1) p,) <$> BS.readFile p) (brWritten r)
  pure (brDiagnostics r, files)
