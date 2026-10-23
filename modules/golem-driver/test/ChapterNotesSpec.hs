-- | Notes at the end of the chapter (golem-driver ADR 0026).
module ChapterNotesSpec (chapterNoteTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (findIndex, isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Driver.Pdf (PdfInput (..), PdfLayout (..), SetLine (..), layoutPages)
import Golem.Project (ProjectFailure (..))
import Golem.Syntax
import Support
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The manifest of the files, each in the chapters given as TOML.
manifestOf :: T.Text -> BS.ByteString
manifestOf chapters = replaceIn "chapters = [\"a.gm\"]" ("chapters = " <> chapters) miniManifest

oneFile, twoChapters, oneChapter :: BS.ByteString
oneFile = miniManifest
twoChapters = manifestOf "[\"a.gm\", \"b.gm\"]"
oneChapter = manifestOf "[[\"a.gm\", \"b.gm\"]]"

-- | Headings on the body grid, notes at the end of the chapter.
chapterEnd :: BS.ByteString
chapterEnd = horizontalStyle <> flatHeadings <> "\n[notes]\nplacement = \"chapter-end\"\n"

-- | The lines of each page, as text.
pagesOf :: BS.ByteString -> BS.ByteString -> [(FilePath, T.Text)] -> IO [[T.Text]]
pagesOf manifest style sources = withSystemTempDirectory "golem-chapter-notes" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") style
  forM_ sources $ \(to, src) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) (TE.encodeUtf8 src)
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> case (evBook e, filter isError (evDiagnostics e)) of
      (Just book, []) -> layoutPages fakeProvider (PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty Nothing Map.empty (chapterMasters (evProject e)) (evStyleFile e) Map.empty) >>= either (assertFailure . show) pure
      (_, ds) -> assertFailure (show ds)

{- | Builds the project for the targets: its diagnostics and the contents
of the files it wrote, by their names under the output folder.
-}
buildFor :: [Target] -> BS.ByteString -> BS.ByteString -> [(FilePath, T.Text)] -> IO ([Diagnostic], [(FilePath, BS.ByteString)])
buildFor targets manifest style sources = withSystemTempDirectory "golem-chapter-notes" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (manifest <> "\n[targets.html]\n\n[targets.epub]\n\n[targets.text]\nvariants = [\"horizontal\"]\n")
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  forM_ (bodyFontFiles style) $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  forM_ sources $ \(to, src) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) (TE.encodeUtf8 src)
  r <- build (defaultOptions tmp) {optTargets = Just targets, optFonts = fakeProvider}
  files <- mapM (\p -> (drop (length tmp + 1) p,) <$> BS.readFile p) (brWritten r)
  pure (brDiagnostics r, files)

codesOf :: [Diagnostic] -> [DiagnosticCode]
codesOf = map diagCode

-- | Where a line that starts with a text is, in the lines of all pages.
lineIndex :: T.Text -> [[T.Text]] -> Maybe Int
lineIndex t = findIndex (t `T.isPrefixOf`) . concat

-- | The page (from 1) of the first line that starts with a text.
pageWith :: T.Text -> [[T.Text]] -> Maybe Int
pageWith t pages = fmap (+ 1) (findIndex (any (t `T.isPrefixOf`)) pages)

chapterNoteTests :: [TestTree]
chapterNoteTests =
  [ testCase "one file: no footnote on any page, the title and the notes after the last line" $ do
      let src = [("a.gm", "本文[note: 一つ目。]です。\n\n次[note: 二つ目。]。\n")]
      pages <- pagesOf oneFile chapterEnd src
      concat pages @?= ["本文*1です。", "次*2。", "注", "*1一つ目。", "*2二つ目。"]
      (_, pl) <- layoutHeads oneFile chapterEnd src
      [n | sl <- Map.elems (plLines pl), n <- slNotes sl] @?= [],
    testCase "page-foot gives the PDF it gave before" $ do
      a <- miniPdf fakeProvider True horizontalStyle "本文[note: 注。]\n" [] >>= inflateAll
      b <- miniPdf fakeProvider True (horizontalStyle <> "\n[notes]\nplacement = \"page-foot\"\n") "本文[note: 注。]\n" [] >>= inflateAll
      a @?= b,
    testCase "two chapters: the list of the first comes before the second, whose notes count from 1" $ do
      pages <- pagesOf twoChapters chapterEnd [("a.gm", "# 一\n\n甲[note: 甲注。]\n"), ("b.gm", "# 二\n\n乙[note: 乙注。]\n")]
      concat pages @?= ["1　一", "甲*1", "注", "*1甲注。", "2　二", "乙*1", "注", "*1乙注。"],
    testCase "a chapter of two files: one list, at the end of the second file" $ do
      pages <- pagesOf oneChapter chapterEnd [("a.gm", "甲[note: 甲注。]\n"), ("b.gm", "乙[note: 乙注。]\n")]
      concat pages @?= ["甲*1", "乙*2", "注", "*1甲注。", "*2乙注。"],
    testCase "a file that ends with a page break: the list before the break" $ do
      pages <- pagesOf twoChapters chapterEnd [("a.gm", "甲[note: 甲注。]\n\n@page-break\n"), ("b.gm", "乙\n")]
      pageWith "注" pages @?= Just 1
      pageWith "*1甲注。" pages @?= Just 1
      pageWith "乙" pages @?= Just 2,
    testCase "a chapter without notes has no list" $ do
      pages <- pagesOf twoChapters chapterEnd [("a.gm", "甲\n"), ("b.gm", "乙[note: 乙注。]\n")]
      concat pages @?= ["甲", "乙*1", "注", "*1乙注。"],
    testCase "the title is Notes in an English book" $ do
      pages <- pagesOf (replaceIn "language = \"ja\"" "language = \"en\"" oneFile) chapterEnd [("a.gm", "Text[note: A note.]\n")]
      lineIndex "Notes" pages @?= Just 1,
    testCase "the title is in neither the table of contents nor the running heads" $ do
      let style = chapterEnd <> "\n[masters.body]\nrunning-head = { position = \"top-outside\", content = \"heading.2.short\" }\n"
          src = [("a.gm", "@toc\n\n# 一\n\n甲[note: 甲注。]\n")]
      pages <- pagesOf oneFile style src
      length (concatMap (filter ("注" `T.isPrefixOf`)) pages) @?= 1
      (heads, _) <- layoutHeads oneFile style src
      assertBool (show heads) (all (notElem "注") (Map.elems heads)),
    testCase "the title is set in the size of headings of level 2" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> "\n[headings.2]\nsize = \"20pt\"\n\n[notes]\nplacement = \"chapter-end\"\n") "本文[note: 注。]\n" [] >>= fmap BS.concat . inflateAll
      -- the body in 10pt, the note mark in 5pt, the title of the list alone in 20pt
      tfSizes content @?= ["10", "10", "5", "10", "10", "10", "20"],
    testCase "a long list: the title is never alone at the foot of a page" $ do
      let src = [("a.gm", T.concat ["本文" <> T.pack (show i) <> "[note: " <> T.replicate 30 "注" <> "]\n\n" | i <- [1 :: Int .. 8]])]
      pages <- pagesOf oneFile (replaceIn "lines = 30" "lines = 5" horizontalStyle <> flatHeadings <> "\n[notes]\nplacement = \"chapter-end\"\n") src
      assertBool (show pages) (all (\p -> null p || last p /= "注") pages)
      lineIndex "注" pages @?= Just 8,
    testCase "an index mark in a note shows the page of the list" $ do
      let src = [("a.gm", "本文[note: 注の[index reading=くみはん: 組版]。]\n\n@page-break\n\n二ページ目。\n\n@page-break\n\n@index\n")]
      pages <- pagesOf oneFile (horizontalStyle <> flatHeadings <> "\n[notes]\nplacement = \"chapter-end\"\n") src
      let listPage = pageWith "*1" pages
      listPage @?= Just 3
      assertBool (show pages) (any ("組版　3" `elem`) pages),
    testCase "[notes.rule] draws no rule for notes at the end of the chapter" $ do
      a <- miniPdf fakeProvider True chapterEnd "本文[note: 注。]\n" [] >>= inflateAll
      b <- miniPdf fakeProvider True (chapterEnd <> "\n[notes.rule]\nlength = \"5zw\"\n") "本文[note: 注。]\n" [] >>= inflateAll
      a @?= b,
    testCase "two builds, parallel and sequential, give the same bytes" $ do
      let src = "本文[note: 一つ目。]です。\n\n次[note: 二つ目。]。\n"
      a <- miniPdf fakeProvider True chapterEnd src []
      b <- miniPdf fakeProvider False chapterEnd src []
      c <- miniPdf fakeProvider True chapterEnd src []
      a @?= b
      a @?= c,
    testGroup
      "G03027"
      [ testCase "numbering per file in a chapter of two files with notes is a warning; the PDF is written" $ do
          (ds, files) <- buildFor [TargetPdf] oneChapter (chapterEnd <> "numbering = \"file\"\n") [("a.gm", "甲[note: 甲注。]\n"), ("b.gm", "乙乙[note: 乙注。]\n")]
          [diagSeverity d | d <- ds, diagCode d == DiagnosticCode "G03027"] @?= [Warning]
          -- at the first note of the second file of the chapter; the message names the first
          [spanStart (diagSpan d) | d <- ds, diagCode d == DiagnosticCode "G03027"] @?= [6]
          assertBool "a.gm" (all (\d -> "a.gm" `T.isInfixOf` diagMessage d) [d | d <- ds, diagCode d == DiagnosticCode "G03027"])
          assertBool "a PDF" (any ((".pdf" `isSuffixOf`) . fst) files),
        testCase "numbering per chapter or per book gives none" $
          forM_ ["chapter", "book"] $ \n -> do
            (ds, _) <- buildFor [TargetPdf] oneChapter (chapterEnd <> "numbering = \"" <> n <> "\"\n") [("a.gm", "甲[note: 甲注。]\n"), ("b.gm", "乙[note: 乙注。]\n")]
            filter (== DiagnosticCode "G03027") (codesOf ds) @?= [],
        testCase "page-foot: none for the PDF alone, one with HTML or plain text" $ do
          let style = horizontalStyle <> "\n[notes]\nnumbering = \"file\"\n"
              src = [("a.gm", "甲[note: 甲注。]\n"), ("b.gm", "乙[note: 乙注。]\n")]
          (pdf, _) <- buildFor [TargetPdf] oneChapter style src
          filter (== DiagnosticCode "G03027") (codesOf pdf) @?= []
          (html, _) <- buildFor [TargetHtml] oneChapter style src
          filter (== DiagnosticCode "G03027") (codesOf html) @?= [DiagnosticCode "G03027"]
          (text, _) <- buildFor [TargetText] oneChapter style src
          filter (== DiagnosticCode "G03027") (codesOf text) @?= [DiagnosticCode "G03027"]
      ],
    testCase "HTML, EPUB and plain text do not depend on placement" $ do
      let src = [("a.gm", "甲[note: 甲注。]\n"), ("b.gm", "乙[note: 乙注。]\n")]
          notPdf = filter (not . (".pdf" `isSuffixOf`) . fst)
      (_, a) <- buildFor [TargetHtml, TargetText, TargetEpub] oneChapter (horizontalStyle <> "\n[notes]\nplacement = \"page-foot\"\n") src
      (_, b) <- buildFor [TargetHtml, TargetText, TargetEpub] oneChapter (horizontalStyle <> "\n[notes]\nplacement = \"chapter-end\"\n") src
      -- style.toml is not an input of the HTML, EPUB or plain text but its bytes; compare the pages and texts
      let pagesAndTexts = filter (\(p, _) -> any (`isSuffixOf` p) [".xhtml", ".txt"]) . notPdf
      pagesAndTexts a @?= pagesAndTexts b
      map fst (pagesAndTexts a) @?= ["build/html/a.xhtml", "build/html/b.xhtml", "build/html/index.xhtml", "build/text/horizontal/a.txt", "build/text/horizontal/b.txt"]
  ]
