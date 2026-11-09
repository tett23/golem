{- | Front matter folios and page labels (docs/adr/0260) through the
layout and the build: the table of contents, the index, [ref-page] and
the folios written by one rule (I5), the books without page-numbering
(I4), the sections with no page (I8, G07109), a number a section cannot
write (G07110), and the hidden folios (I9).
-}
module PageLabelsSpec (pageLabelsTests) where

import Data.ByteString qualified as BS
import Data.List (isSuffixOf, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.PageLabel (PageLabel (..), pageLabelText)
import Golem.Layout.Paginate (PageOut (..), labelPages, markPages)
import Golem.LayoutSpec (PageGeometry, pageGeometry)
import Golem.Pdf qualified as P
import Golem.Project
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.TestSupport.Manifest
import Golem.Typeset (PdfInput (..), PdfLayout (..), SetLine (..), TocPage (..), bookSections, folioTexts, hiddenFolios, layoutLabels, layoutPdf, pdfPageLabels)
import Support
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A manifest of the chapter entries given, written as TOML, for the targets.
manifestOf :: [Text] -> [Text] -> BS.ByteString
manifestOf entries targets =
  TE.encodeUtf8 ("chapters = [" <> T.intercalate ", " entries <> "]\n" <> T.dropWhile (/= '\n') (manifestToml testManifest {tmTargets = targets}))

-- | An entry of a file with page-numbering.
numbered :: Text -> Text -> Text
numbered file pn = "{ file = \"" <> file <> "\", page-numbering = " <> pn <> " }"

-- | Five lines a page, a folio of {n} on every page.
folioStyle :: BS.ByteString
folioStyle = fiveLines <> "\n[masters.body]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n"

{- | Lays out a project with the fake fonts, with crop marks or none: the
input, the geometry and the layout.
-}
layoutBook :: Maybe P.MarkStyle -> BS.ByteString -> BS.ByteString -> [(FilePath, Text)] -> IO (PdfInput, PageGeometry, PdfLayout)
layoutBook marks manifest style sources = withSystemTempDirectory "golem-labels" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") style
  writeTexts tmp sources
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> case (evBook e, pageGeometry (FileId 0) (isJust marks) (evStyle e)) of
      _ | errs@(_ : _) <- filter isError (evDiagnostics e) -> assertFailure (show errs)
      (Just book, Right geom) -> do
        let inp = PdfInput (diskFiles tmp) (evProject e) (evStyle e) book False [] Map.empty marks (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) Map.empty (projectVarTexts (manifestVars (projectManifest (evProject e)))) (evStyleText e)
        r <- layoutPdf inp geom fakeFonts
        case r of
          Left ds -> assertFailure (show ds)
          Right layout -> pure (inp, geom, layout)
      (_, Left ds) -> assertFailure (show ds)
      (Nothing, _) -> assertFailure "no book"

-- | Builds a project to PDF with the fake fonts: its diagnostics, its sources and the PDF, if written.
buildLabelled :: BS.ByteString -> BS.ByteString -> [(FilePath, Text)] -> IO ([Diagnostic], Map.Map FileId SourceInfo, Maybe BS.ByteString)
buildLabelled manifest style sources = withSystemTempDirectory "golem-labels" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  writeFiles tmp (bodyFontFiles style)
  writeTexts tmp sources
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFiles = diskFiles tmp, optFonts = fakeProvider}
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> Just <$> BS.readFile p
    _ -> pure Nothing
  pure (brDiagnostics r, brSources r, pdf)

-- | The paths of the fonts that a style.toml names: the strings that start with fonts/.
fontPaths :: Text -> [FilePath]
fontPaths t = [T.unpack (T.takeWhile (/= '"') rest) | (_, rest) <- T.breakOnAll "\"fonts/" t >>= \(a, b) -> [(a, T.drop 1 b)]]

-- | The text of the boxes of a line.
boxText :: Line -> Text
boxText l = T.concat [bcText c | Box _ c <- lineItems l]

-- | The text of every line of the body that starts with a prefix.
linesStarting :: Text -> PdfLayout -> [Text]
linesStarting prefix pl = [t | sl <- Map.elems (plLines pl), let t = boxText (slLine sl), prefix `T.isPrefixOf` t]

-- | The byte offset of the first occurrence of a text in another.
offsetOf :: Text -> Text -> Int
offsetOf needle hay = BS.length (TE.encodeUtf8 (fst (T.breakOn needle hay)))

-- | The front matter of two pages and the body of two, with a table of contents, an index and references.
frontSources :: [(FilePath, Text)]
frontSources =
  [ ("preface.gm", "# はじめに\n\n前付けの本文[index reading=まえ: 前付け]。\n\n@label pre\n前付けの二つ目。\n\n@page-break\n\n二ページ目。\n"),
    ("toc.gm", "@toc\n"),
    ("one.gm", "# 第一章\n\n参照は[ref-page pre]と[ref-page body]。\n\n@label body\n本文[index reading=ほん: 本文]。\n\n@page-break\n\n[index reading=まえ: 前付け]二ページ目。\n\n@index\n")
  ]

frontEntries :: [Text]
frontEntries = [numbered "preface.gm" "{ style = \"lower-roman\" }", "\"toc.gm\"", numbered "one.gm" "{ style = \"arabic\", start = 1 }"]

pageLabelsTests :: TestTree
pageLabelsTests =
  testGroup
    "front matter folios and page labels (docs/adr/0260)"
    [ testCase "I5: the table of contents, the index, [ref-page] and the folios write the labels of the pages" $ do
        (inp, geom, pl) <- layoutBook Nothing (manifestOf frontEntries ["pdf"]) folioStyle frontSources
        let labels = layoutLabels inp pl
            texts = Map.map pageLabelText labels
            lastFront = maximum [p | (p, l) <- Map.toList labels, isJust (plNotation l)]
        -- the front matter in lower-roman from i, the body from 1 on an odd page
        [t | (p, t) <- Map.toList texts, p <= lastFront] @?= take lastFront ["i", "ii", "iii", "iv", "v", "vi"]
        -- the folios: {n} in the notation of the section
        Map.elems (folioTexts inp geom pl) @?= [t | (p, t) <- Map.toList texts, Map.member p (folioTexts inp geom pl)]
        -- the table of contents: i for the preface, 1 for chapter 1
        map (boxText . tpNumber) (Map.elems (plTocPages pl)) @?= ["i", "1"]
        -- [ref-page]: the front page in lower-roman, the body page in Arabic numerals
        let refs = labelPages (bookSections inp) (plPages pl)
            textOf l = maybe "?" pageLabelText (Map.lookup l refs)
        (textOf "pre", textOf "body") @?= ("ii", "2")
        linesStarting "参照は" pl @?= ["参照は" <> textOf "pre" <> "と" <> textOf "body" <> "。"]
        -- the index: the pages of the marks of 前付け in the order of the book, the front page in lower-roman (the space after the comma is glue)
        let marks = map pageLabelText (sortOn plIndex (Map.elems (markPages (bookSections inp) (plPages pl))))
        marks @?= ["ii", "2", "3"]
        [t | t <- linesStarting "前付け" pl, "　" `T.isInfixOf` t] @?= ["前付け　ii,3"],
      testCase "I5: in vertical text a label of no notation is in the notation of [numbers], one of lower-roman its letters" $ do
        let style = pdfStyle
        (inp, _, pl) <- layoutBook Nothing (manifestOf frontEntries ["pdf"]) style frontSources
        let texts = Map.map pageLabelText (layoutLabels inp pl)
        assertBool "front matter" (Map.lookup 1 texts == Just "i")
        -- ref-page of [numbers]: kanji by default in vertical text (docs/adr/0118)
        linesStarting "参照は" pl @?= ["参照はiと一。"],
      testCase "I4: a book without page-numbering labels each page its place, writes no /PageLabels and the folios of before" $ do
        (inp, geom, pl) <- layoutBook Nothing (manifestOf ["\"preface.gm\"", "\"toc.gm\"", "\"one.gm\""] ["pdf"]) folioStyle frontSources
        [(plIndex l, plNumber l, plNotation l) | l <- Map.elems (layoutLabels inp pl)] @?= [(p, toInteger p, Nothing) | p <- [1 .. length (Map.keys (layoutLabels inp pl))]]
        pdfPageLabels inp pl @?= []
        Map.toList (folioTexts inp geom pl) @?= [(p, T.pack (show p)) | (p, _) <- Map.toList (folioTexts inp geom pl)],
      testCase "I6: the PDF of the front matter has the ranges /r from i and /D from 1" $ do
        (inp, _, pl) <- layoutBook Nothing (manifestOf frontEntries ["pdf"]) folioStyle frontSources
        let labels = layoutLabels inp pl
            bodyFirst = minimum [p | (p, l) <- Map.toList labels, isNothing (plNotation l)]
        pdfPageLabels inp pl @?= [P.PageLabelRange 0 (Just P.LabelLowerRoman) "" 1, P.PageLabelRange (bodyFirst - 1) (Just P.LabelDecimal) "" 1]
        (ds, _, pdf) <- buildLabelled (manifestOf frontEntries ["pdf"]) folioStyle frontSources
        filter isError ds @?= []
        bytes <- maybe (assertFailure "no PDF") pure pdf
        assertBool "/PageLabels" (TE.encodeUtf8 ("/PageLabels << /Nums [0 << /S /r >> " <> T.pack (show (bodyFirst - 1)) <> " << /S /D >>] >>") `BS.isInfixOf` bytes),
      testCase "I8: a section whose page a later section starts on is one G07109 at its page-numbering" $ do
        let entries = ["\"a.gm\"", numbered "b.gm" "{ start = 1 }", numbered "c.gm" "{}"]
            manifest = manifestOf entries ["pdf"]
        (ds, sources, pdf) <- buildLabelled manifest fiveLines [("a.gm", "一。\n"), ("b.gm", ""), ("c.gm", "三。\n")]
        let mfid = [fid | (fid, si) <- Map.toList sources, siPath si == "manifest.toml"]
        [(diagCode d, diagSeverity d, spanFile (diagSpan d), spanStart (diagSpan d)) | d <- ds, diagCode d == DiagnosticCode "G07109"]
          @?= [(DiagnosticCode "G07109", Warning, f, offsetOf "{ start = 1 }" (TE.decodeUtf8 manifest)) | f <- mfid]
        assertBool "the PDF is written" (isJust pdf),
      testCase "I8: a section at the end of the book with nothing after its break is one G07109; a section with pages is none" $ do
        let manifest = manifestOf [numbered "a.gm" "{ style = \"lower-roman\" }", numbered "b.gm" "{ start = 1 }"] ["pdf"]
        (ds, _, _) <- buildLabelled manifest fiveLines [("a.gm", "一。\n"), ("b.gm", "")]
        [spanStart (diagSpan d) | d <- ds, diagCode d == DiagnosticCode "G07109"] @?= [offsetOf "{ start = 1 }" (TE.decodeUtf8 manifest)],
      testCase "G07109 is for the PDF alone" $ do
        withSystemTempDirectory "golem-labels" $ \tmp -> do
          BS.writeFile (tmp </> "manifest.toml") (manifestOf [numbered "a.gm" "{ style = \"lower-roman\" }", numbered "b.gm" "{ start = 1 }"] ["pdf", "html"])
          BS.writeFile (tmp </> "style.toml") fiveLines
          writeTexts tmp [("a.gm", "一。\n"), ("b.gm", "")]
          r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml], optFiles = diskFiles tmp, optFonts = fakeProvider}
          [diagCode d | d <- brDiagnostics r, diagCode d == DiagnosticCode "G07109"] @?= [],
      testCase "G07110: a section of circled on its 51st page is one G07110 at its style, no G07106, and no PDF; 50 pages are none" $ do
        let manifest = manifestOf [numbered "a.gm" "{ style = \"circled\" }"] ["pdf"]
            pagesSource n = T.intercalate "\n\n@page-break\n\n" (replicate n "あ") <> "\n"
        (ds, _, pdf) <- buildLabelled manifest folioStyle [("a.gm", pagesSource 52)]
        [(c, m, spanStart (diagSpan d)) | d <- filter isError ds, let DiagnosticCode c = diagCode d, let m = diagMessage d]
          @?= [("G07110", "page-numbering の style circled では、ノンブル 51 を表せません（51 ページ）", offsetOf "\"circled\"" (TE.decodeUtf8 manifest))]
        pdf @?= Nothing
        (ok, _, okPdf) <- buildLabelled manifest folioStyle [("a.gm", pagesSource 50)]
        filter isError ok @?= []
        assertBool "the PDF of 50 pages" (isJust okPdf),
      testCase "G07110 for a page without a folio too" $ do
        let manifest = manifestOf [numbered "a.gm" "{ style = \"circled\" }"] ["pdf"]
            pagesSource n = T.intercalate "\n\n@page-break\n\n" (replicate n "あ") <> "\n"
        (ds, _, pdf) <- buildLabelled manifest fiveLines [("a.gm", pagesSource 51)]
        [c | d <- filter isError ds, let { DiagnosticCode c = diagCode d }] @?= ["G07110"]
        pdf @?= Nothing,
      testCase "the user manual of 「マニュアルで試すこと」 builds with no error, its /PageLabels /r for the front matter and /D from chapter 1" $
        withSystemTempDirectory "golem-manual" $ \tmp -> do
          copyTree "../../manual" tmp
          -- the colophon reads build-info.gm, which scripts/manual/build-info.sh writes and git does not track
          -- the fonts are not in the repository: the fake fonts are used, and the files only have to be there
          style <- TIO.readFile (tmp </> "style.toml")
          createDirectoryIfMissing True (tmp </> "fonts")
          mapM_ (\f -> doesFileExist (tmp </> f) >>= \there -> if there then pure () else BS.writeFile (tmp </> f) "") (fontPaths style)
          TIO.writeFile (tmp </> "common" </> "build-info.gm") "@set edition = \"0.0.0\"\n@set commit = \"0000000\"\n@set uncommitted = \"\"\n"
          manifest <- TE.decodeUtf8 <$> BS.readFile (tmp </> "manifest.toml")
          assertBool "the preface in lower-roman" ("{ file = \"preface.gm\", page-numbering = { style = \"lower-roman\" } }" `T.isInfixOf` manifest)
          assertBool "chapter 1 from 1" ("{ file = \"chapters/01-first-book.gm\", page-numbering = { style = \"arabic\", start = 1 } }" `T.isInfixOf` manifest)
          r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFiles = diskFiles tmp, optFonts = fakeProvider}
          [(diagCode d, diagMessage d) | d <- brDiagnostics r, isError d] @?= []
          pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
            [p] -> BS.readFile p
            other -> assertFailure (show other)
          let tree = BS.takeWhile (/= 93) (snd (BS.breakSubstring "/PageLabels << /Nums [" pdf))
          case BS.split 32 (BS.drop (BS.length "/PageLabels << /Nums [") tree) of
            ["0", "<<", "/S", "/r", ">>", first, "<<", "/S", "/D", ">>"] -> assertBool "chapter 1 after the front matter" (first > "0")
            other -> assertFailure (show other),
      testCase "I9: the hidden folios are the places of the pages: the last page of the front matter, the blank page of the break and the first of the body" $ do
        let style = folioStyle <> "\n[hidden-folio]\npages = \"all\"\n"
        (inp, _, pl) <- layoutBook (Just P.Western) (manifestOf [numbered "preface.gm" "{ style = \"lower-roman\" }", numbered "one.gm" "{ start = 1 }"] ["pdf"]) style [("preface.gm", "前付け。\n"), ("one.gm", "本文。\n")]
        let labels = layoutLabels inp pl
            hidden = hiddenFoliosOf inp pl
        -- the front matter of one page, the blank page 2, chapter 1 on page 3
        [(plIndex l, pageLabelText l) | l <- Map.elems labels] @?= [(1, "i"), (2, "ii"), (3, "1")]
        [poBlank p | p <- sortOn poNumber (plPages pl)] @?= [False, True, False]
        Map.toList (Map.map (map fst) hidden) @?= [(1, "1"), (2, "2"), (3, "3")]
    ]
  where
    hiddenFoliosOf inp pl = case pageGeometry (FileId 0) True (piStyle inp) of
      Right geom -> hiddenFolios inp geom pl
      Left _ -> Map.empty
