{- | The title formats of numbered headings and captions (root ADR 0463):
title-format of [headings.<l>] and of the paragraph style caption, with
the slots of the number, the title, the separator and the variables, in
every output; the diagnostics of the values the formats refer to.
-}
module TitleFormatSpec (titleFormatTests) where

import Codec.Archive.Zip (findEntryByPath, fromEntry, toArchive)
import Control.Monad (filterM, join)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isSuffixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Assemble (Book (..))
import Golem.Driver
import Golem.Evaluate.Lint (lintProject)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Golem.Typeset (CodeCaption (..), CodeInfo (..), PartLine (..), PdfInput (..), PdfLayout (..), PlacedFigure (..), layoutPdf)
import Support
import System.Directory (doesFileExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | An SVG of 300 by 100 with an unpainted frame.
wideSvg :: [(FilePath, BS.ByteString)]
wideSvg = [("images/wide.svg", TE.encodeUtf8 "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"300\" height=\"100\"><rect width=\"300\" height=\"100\" fill=\"none\"/></svg>")]

{- | A style of 30 characters a line with chapters numbered 第{n}章,
numbered figures, tables and code blocks, and the keys of [headings.1]
and of the paragraph style caption.
-}
fmtStyle :: T.Text -> T.Text -> BS.ByteString
fmtStyle heading caption =
  horizontal30
    ( TE.encodeUtf8 . T.concat $
        [ "\n[headings.1]\nnumber = \"第{n}章\"\n",
          heading,
          "\n[figures]\nnumber = \"図{n}\"\n\n[tables]\nnumber = \"表{n}\"\n\n[code]\nnumber = \"L{n}\"\n",
          "\n[paragraph-styles.caption]\n",
          caption
        ]
    )

-- | A format of [headings.1] alone.
headingFormat :: T.Text -> BS.ByteString
headingFormat f = fmtStyle ("title-format = \"" <> f <> "\"\n") ""

-- | A table of contents and a chapter heading 序論.
chapter :: T.Text
chapter = "@toc\n\n# 序論\n"

-- | A chapter heading, a figure, a table and a code block, each with a caption.
captioned :: T.Text
captioned = "# 海\n\n@figure images/wide.svg alt=\"t\"\n  空\n\n@caption 表題\n| a | b |\n|---|---|\n| 1 | 2 |\n\n@caption 例\n```\na\n```\n"

-- | The text of a line of a part.
partText :: PartLine -> T.Text
partText l = T.concat [bcText c | Box _ c <- lineItems (ptLine l)]

-- | Lays out one chapter with the fake fonts.
layoutOne :: BS.ByteString -> T.Text -> IO PdfLayout
layoutOne style source = do
  let manifest = TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["pdf"]})
  r <- withMiniInput fakeProvider manifest style source wideSvg layoutPdf
  either (assertFailure . show . map diagCode) pure (join r)

-- | The book the PDF of one chapter is laid out from.
bookOf :: BS.ByteString -> T.Text -> IO Book
bookOf style source = do
  let manifest = TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["pdf"]})
  r <- withMiniInput fakeProvider manifest style source wideSvg (\inp _ _ -> pure (piBook inp))
  either (assertFailure . show . map diagCode) pure r

-- | The caption lines of the figures, the tables and the code blocks of a layout, as text.
captionTexts :: PdfLayout -> ([T.Text], [T.Text], [T.Text])
captionTexts pl =
  ( map partText (concatMap pfCaption (Map.elems (plFigures pl))),
    map partText (concatMap ccLines (Map.elems (plTableCaptions pl))),
    map partText (concat [ciCaption ci | ci <- Map.elems (plCodes pl)])
  )

-- | The outputs of one chapter: the HTML page, the HTML table of contents, the EPUB navigation document and the plain text.
data Outputs = Outputs {oHtml :: T.Text, oIndex :: T.Text, oNav :: T.Text, oText :: T.Text}

-- | Builds one chapter to HTML, EPUB and plain text.
buildOutputs :: BS.ByteString -> T.Text -> IO Outputs
buildOutputs style source = withSystemTempDirectory "golem-0463" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n\n[targets.text]\n")
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  writeFiles tmp wideSvg
  r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub, TargetText]}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  html <- TIO.readFile (tmp </> "build/html/a.html")
  index <- TIO.readFile (tmp </> "build/html/index.html")
  archive <- toArchive <$> BL.readFile (tmp </> "build/epub/book.epub")
  texts <- textFiles (tmp </> "build/text")
  text <- T.concat <$> mapM TIO.readFile texts
  pure (Outputs html index (maybe "" (TE.decodeUtf8 . BL.toStrict . fromEntry) (findEntryByPath "OEBPS/nav.xhtml" archive)) text)

-- | Every .txt file under a directory, in order.
textFiles :: FilePath -> IO [FilePath]
textFiles dir = do
  names <- sort <$> listDirectory dir
  let paths = map (dir </>) names
  files <- filterM doesFileExist paths
  dirs <- filterM (fmap not . doesFileExist) paths
  rest <- concat <$> mapM textFiles dirs
  pure (filter (".txt" `isSuffixOf`) files <> rest)

-- | Asserts that the text has the part.
has :: T.Text -> T.Text -> Assertion
has text part = assertBool (T.unpack part <> " in\n" <> T.unpack text) (part `T.isInfixOf` text)

-- | The lines of a layout that start with a text.
startingWith :: T.Text -> PdfLayout -> Int
startingWith t pl = length (filter (t `T.isPrefixOf`) (lineTexts pl))

-- | A style of six lines a page whose master page body shows heading.1.numbered in its running head.
headsStyle :: T.Text -> BS.ByteString
headsStyle f =
  BS.concat
    [ replaceIn "lines = 30\n" "lines = 6\n" horizontalStyle,
      TE.encodeUtf8 ("\n[headings.1]\nnumber = \"第{n}章\"\ntitle-format = \"" <> f <> "\"\n\n"),
      "[masters.body]\nrunning-head = { position = \"top-outside\", content = \"heading.1.numbered\" }\n"
    ]

-- | Builds a project of files with the targets: the diagnostics and the sources.
buildTitled :: BuildOptions -> BS.ByteString -> BS.ByteString -> [(FilePath, T.Text)] -> IO ([Diagnostic], Map.Map FileId SourceInfo)
buildTitled opts manifest style files = withSystemTempDirectory "golem-0463" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  writeFiles tmp (bodyFontFiles style <> wideSvg)
  writeTexts tmp files
  r <- build opts {optRoot = tmp, optFiles = diskFiles tmp, optFonts = fakeProvider}
  pure (brDiagnostics r, brSources r)

-- | The PDF and the HTML targets.
bothManifest :: BS.ByteString
bothManifest = miniManifest <> "\n[targets.html]\n"

-- | The PDF and the HTML targets, and golem check.
pdfHtml, checkOnly :: BuildOptions
pdfHtml = (defaultOptions ".") {optTargets = Just [TargetPdf, TargetHtml]}
checkOnly = pdfHtml {optCheckOnly = True}

-- | The code, the path of the file and the start of each error.
errorSites :: Map.Map FileId SourceInfo -> [Diagnostic] -> [(T.Text, Maybe FilePath, Int)]
errorSites srcs ds =
  [ (c, siPath <$> Map.lookup (spanFile (diagSpan d)) srcs, spanStart (diagSpan d))
  | d <- ds,
    isError d,
    let DiagnosticCode c = diagCode d
  ]

-- | The codes of the errors.
errorCodes :: [Diagnostic] -> [T.Text]
errorCodes ds = [c | d <- ds, isError d, let DiagnosticCode c = diagCode d]

-- | The byte offset of a text in a text.
offsetOf :: T.Text -> T.Text -> Int
offsetOf whole part = BS.length (TE.encodeUtf8 (fst (T.breakOn part whole)))

-- | The byte offset of a text in the style.toml the build writes.
styleOffset :: BS.ByteString -> BS.ByteString -> Int
styleOffset style needle = BS.length (fst (BS.breakSubstring needle (withBodyFont style)))

titleFormatTests :: [TestTree]
titleFormatTests = [testGroup "title-format (root ADR 0463)" (outputTests <> diagnosticTests <> lintTests)]

outputTests :: [TestTree]
outputTests =
  [ testCase "root ADR 0463 I1: a book without title-format has no formats" $ do
      book <- bookOf (fmtStyle "number-title-separator = \"：\"\n" "") (chapter <> captioned)
      bookTitleFormats book @?= Map.empty,
    testCase "root ADR 0463 I2: {number}{separator}{title} in ja gives the strings of the book without a format" $ do
      let plain = fmtStyle "" ""
          formatted = headingFormat "{number}{separator}{title}"
      a <- layoutOne plain chapter
      b <- layoutOne formatted chapter
      lineTexts b @?= lineTexts a
      startingWith "第1章\x3000序論" b @?= 2
      o <- buildOutputs formatted chapter
      has (oHtml o) "<span class=\"number\">第1章</span>\x3000序論</h1>"
      has (oText o) "第1章\x3000序論",
    testCase "root ADR 0463 I2: {title}（{number}） puts the number after the title, in the heading and @toc" $ do
      pl <- layoutOne (headingFormat "{title}（{number}）") chapter
      startingWith "序論（第1章）" pl @?= 2
      startingWith "第1章" pl @?= 0,
    testCase "root ADR 0463 I2: HTML: the number in its span at {number}, the title's inlines at {title}" $ do
      o <- buildOutputs (headingFormat "{title}（{number}）") "@toc\n\n# 序[ruby: 論|ろん]\n"
      has (oHtml o) "序<ruby class=\"mono\">論<rp>（</rp><rt>ろん</rt><rp>）</rp></ruby>（<span class=\"number\">第1章</span>）</h1>"
      has (oText o) "序論（ろん）（第1章）",
    testCase "root ADR 0463 I2: {separator} is the separator written, or that of the language" $ do
      a <- layoutOne (fmtStyle "number-title-separator = \"：\"\ntitle-format = \"[{number}{separator}]{title}\"\n" "") chapter
      startingWith "[第1章：]序論" a @?= 2
      b <- layoutOne (headingFormat "{title}{separator}{number}") chapter
      startingWith "序論\x3000第1章" b @?= 2,
    testCase "root ADR 0463 I2: {set.part} is the variable of the file of the heading" $ do
      pl <- layoutOne (headingFormat "{number}　{set.part}　{title}") ("@set part = \"上\"\n\n" <> chapter)
      startingWith "第1章　上　序論" pl @?= 2,
    testCase "root ADR 0463 I2: {meta.title} and {vars.series} are those of the manifest" $ do
      let manifest = miniManifest <> TE.encodeUtf8 "\n[vars]\nseries = \"叢書\"\n"
      (ds, _) <- buildTitled ((defaultOptions ".") {optTargets = Just [TargetPdf]}) manifest (headingFormat "{vars.series}{number}{title}") [("a.gm", chapter)]
      errorCodes ds @?= []
      (heads, _) <- layoutHeads manifest (headsStyle "{vars.series}{meta.title}・{number}{title}") [("a.gm", "# 序論\n\n" <> T.replicate (12 * 11) "あ" <> "\n")]
      Map.lookup 2 heads @?= Just ["叢書T・第1章序論"],
    testCase "root ADR 0463 I2: {set.part?} without the variable is empty, without diagnostics" $ do
      pl <- layoutOne (headingFormat "{number}{set.part?}{title}") chapter
      startingWith "第1章序論" pl @?= 2,
    testCase "root ADR 0463 I2: a value with braces is text, never a slot" $ do
      pl <- layoutOne (headingFormat "{set.part}：{title}") ("@set part = \"{title}\"\n\n" <> chapter)
      startingWith "{title}：序論" pl @?= 2,
    testCase "root ADR 0463 I3: a heading excluded from the numbers is its title alone, with a format or not" $ do
      pl <- layoutOne (headingFormat "{title}（{number}）") "@toc\n\n@nonumber\n# 序論\n"
      startingWith "序論" pl @?= 2
      startingWith "序論（" pl @?= 0
      o <- buildOutputs (headingFormat "{title}（{number}）") "@nonumber\n# 序論\n"
      has (oHtml o) ">序論</h1>",
    testCase "root ADR 0463 I3: a figure excluded from the numbers is its caption alone" $ do
      pl <- layoutOne (fmtStyle "" "title-format = \"{title}（{number}）\"\n") "# 海\n\n@nonumber\n@figure images/wide.svg alt=\"t\"\n  空\n"
      captionTexts pl @?= (["空"], [], []),
    testCase "root ADR 0463 I4: @toc, the running head and the HTML and EPUB tables of contents use the short title" $ do
      let style = headingFormat "{title}（{number}）"
          source = "@toc\n\n@toc-title 序\n# 序論\n"
      pl <- layoutOne style source
      startingWith "序（第1章）" pl @?= 1
      startingWith "序論（第1章）" pl @?= 1
      (heads, _) <- layoutHeads miniManifest (headsStyle "{title}（{number}）") [("a.gm", "@toc-title 序\n# 序論\n\n" <> T.replicate (12 * 11) "あ" <> "\n")]
      Map.lookup 2 heads @?= Just ["序（第1章）"]
      o <- buildOutputs style source
      has (oHtml o) ">序（<span class=\"number\">第1章</span>）</a>"
      has (oIndex o) ">序（<span class=\"number\">第1章</span>）</a>"
      has (oNav o) ">序（第1章）</a>"
      has (oText o) "序（第1章）",
    testCase "root ADR 0463 I4: the running head takes {set.*} of the file of the heading" $ do
      (heads, _) <- layoutHeads miniManifest (headsStyle "{set.part}{number}") [("a.gm", "@set part = \"上\"\n\n# 序論\n\n" <> T.replicate (12 * 11) "あ" <> "\n")]
      Map.lookup 2 heads @?= Just ["上第1章"],
    testCase "root ADR 0463 I2: the captions of figures, tables and code blocks take the format of caption" $ do
      let style = fmtStyle "" "title-format = \"{title}（{number}）\"\n"
      pl <- layoutOne style captioned
      captionTexts pl @?= (["空（図1）"], ["表題（表1）"], ["例（L1）"])
      o <- buildOutputs style captioned
      has (oHtml o) "<figcaption>空（<span class=\"number\">図1</span>）</figcaption>"
      has (oHtml o) "<caption>表題（<span class=\"number\">表1</span>）</caption>"
      has (oHtml o) "<figcaption>例（<span class=\"number\">L1</span>）</figcaption>"
      mapM_ (has (oText o)) ["［空（図1）］", "表題（表1）", "例（L1）"],
    testCase "root ADR 0463 I2: caption takes the format of body through based-on, and @style-def caption that of its file" $ do
      pl <- layoutOne (horizontal30 (TE.encodeUtf8 "\n[figures]\nnumber = \"図{n}\"\n\n[paragraph-styles.body]\ntitle-format = \"<{number}>{title}\"\n")) "@figure images/wide.svg alt=\"t\"\n  空\n"
      captionTexts pl @?= (["<図1>空"], [], [])
      o <- buildOutputs (fmtStyle "" "title-format = \"{title}（{number}）\"\n") ("@style-def paragraph caption title-format=\"{number}/{title}\"\n\n" <> captioned)
      has (oHtml o) "<figcaption><span class=\"number\">図1</span>/空</figcaption>",
    testCase "root ADR 0463 I2: a heading format does not reach the captions, nor a caption format the headings" $ do
      pl <- layoutOne (fmtStyle "title-format = \"{title}（{number}）\"\n" "") captioned
      captionTexts pl @?= (["図1\x3000空"], ["表1\x3000表題"], ["L1\x3000例"])
      pl' <- layoutOne (fmtStyle "" "title-format = \"{title}（{number}）\"\n") chapter
      startingWith "第1章\x3000序論" pl' @?= 2
  ]

-- | A chapter with two headings that refer to {set.part}, a table of contents and a running head.
twoHeadings :: T.Text
twoHeadings = "@toc\n\n# 序論\n\n" <> T.replicate (12 * 7) "あ" <> "\n\n# 本論\n\n" <> T.replicate (12 * 7) "い" <> "\n"

diagnosticTests :: [TestTree]
diagnosticTests =
  [ testCase "root ADR 0463 I5: G02283 once for each heading, whatever the outputs, the targets, the table of contents and the running heads" $ do
      let style = headsStyle "{number}{set.part}{title}"
      (ds, srcs) <- buildTitled pdfHtml bothManifest style [("a.gm", twoHeadings)]
      errorSites srcs ds @?= [("G02283", Just "a.gm", offsetOf twoHeadings "# 序論"), ("G02283", Just "a.gm", offsetOf twoHeadings "# 本論")]
      (cs, _) <- buildTitled checkOnly bothManifest style [("a.gm", twoHeadings)]
      errorCodes cs @?= ["G02283", "G02283"]
      (hs, _) <- buildTitled ((defaultOptions ".") {optTargets = Just [TargetHtml]}) bothManifest style [("a.gm", twoHeadings)]
      errorCodes hs @?= ["G02283", "G02283"],
    testCase "root ADR 0463 I5: the message of G02283 names the variable" $ do
      (ds, _) <- buildTitled checkOnly bothManifest (headingFormat "{set.ns.part}") [("a.gm", chapter)]
      [diagMessage d | d <- ds, isError d] @?= ["題の書式が参照する変数 ns.part が、このファイルにありません"],
    testCase "root ADR 0463 I5: G02283 for a caption, once for each caption and name" $ do
      (ds, srcs) <- buildTitled checkOnly bothManifest (fmtStyle "" "title-format = \"{set.a}{set.b}{set.a}{title}\"\n") [("a.gm", "@figure images/wide.svg alt=\"t\"\n  空\n")]
      errorSites srcs ds @?= [("G02283", Just "a.gm", 0), ("G02283", Just "a.gm", 0)],
    testCase "root ADR 0463 I5: no G02283 for a heading without a number, which the format does not set" $ do
      (ds, _) <- buildTitled checkOnly bothManifest (headingFormat "{set.part}{title}") [("a.gm", "@nonumber\n# 序論\n")]
      errorCodes ds @?= [],
    testCase "root ADR 0463 I5: G02284 once for an array, whatever the outputs" $ do
      let source = "@set part = [1, 2]\n\n" <> chapter
      (ds, srcs) <- buildTitled pdfHtml bothManifest (headingFormat "{number}{set.part}{title}") [("a.gm", source)]
      errorSites srcs ds @?= [("G02284", Just "a.gm", offsetOf source "# 序論")]
      [diagMessage d | d <- ds, isError d] @?= ["題の書式に出せるのは文字列と数です: part は 配列"],
    testCase "root ADR 0463 I6: an unreadable title-format of @style-def is one G03296 at the definition" $ do
      (ds, srcs) <- buildTitled checkOnly bothManifest (fmtStyle "" "") [("a.gm", "@style-def paragraph caption title-format=\"{nmber}{titel}\"\n\n# 海\n")]
      errorSites srcs ds @?= [("G03296", Just "a.gm", 0)],
    testCase "root ADR 0463 I7: a title-format of @style-def that is not a string is G03006" $ do
      (ds, _) <- buildTitled checkOnly bothManifest (fmtStyle "" "") [("a.gm", "@style-def paragraph caption title-format=1\n\n# 海\n")]
      errorCodes ds @?= ["G03006"],
    testCase "root ADR 0463 I7: {vars.series} without [vars] series is one G03297 at the value, for each slot" $ do
      let style = headingFormat "{vars.series}{number}{vars.series?}{title}"
      (ds, srcs) <- buildTitled checkOnly bothManifest style [("a.gm", chapter)]
      errorSites srcs ds @?= [("G03297", Just "style.toml", styleOffset style "\"{vars.series}")]
      [diagMessage d | d <- ds, isError d] @?= ["題の書式が参照する変数 series が [vars] にありません"]
      let twice = headingFormat "{vars.series}{vars.series}"
      (ds2, _) <- buildTitled pdfHtml bothManifest twice [("a.gm", chapter)]
      errorCodes ds2 @?= ["G03297", "G03297"],
    testCase "root ADR 0463 I7: {vars.list}, an array, is G03298" $ do
      let style = headingFormat "{vars.list}"
      (ds, srcs) <- buildTitled checkOnly (bothManifest <> "\n[vars]\nlist = [\"a\"]\n") style [("a.gm", chapter)]
      errorSites srcs ds @?= [("G03298", Just "style.toml", styleOffset style "\"{vars.list}")]
      [diagMessage d | d <- ds, isError d] @?= ["題の書式に出せるのは文字列と数です: vars.list は 配列"],
    testCase "root ADR 0463 I7: {meta.publisher} without the key is G03299; with ? it is empty" $ do
      let style = fmtStyle "" "title-format = \"{meta.publisher}{title}\"\n"
      (ds, srcs) <- buildTitled checkOnly bothManifest style [("a.gm", chapter)]
      errorSites srcs ds @?= [("G03299", Just "style.toml", styleOffset style "\"{meta.publisher}")]
      [diagMessage d | d <- ds, isError d] @?= ["題の書式が参照する [metadata] の publisher がありません"]
      (ok, _) <- buildTitled checkOnly bothManifest (fmtStyle "" "title-format = \"{meta.publisher?}{title}\"\n") [("a.gm", chapter)]
      errorCodes ok @?= [],
    testCase "root ADR 0463 I7: {vars.series} of @style-def without [vars] series is G03297 at the definition" $ do
      (ds, srcs) <- buildTitled checkOnly bothManifest (fmtStyle "" "") [("a.gm", "@style-def paragraph caption title-format=\"{vars.series}\"\n\n# 海\n")]
      errorSites srcs ds @?= [("G03297", Just "a.gm", 0)]
  ]

lintTests :: [TestTree]
lintTests =
  [ testCase "root ADR 0463: golem lint counts a variable title-format refers to as used (no G05002)" $ do
      let lintCodes style files = withSystemTempDirectory "golem-0463" $ \tmp -> do
            BS.writeFile (tmp </> "manifest.toml") bothManifest
            BS.writeFile (tmp </> "style.toml") style
            writeTexts tmp files
            (_, ds) <- lintProject Dev False False tmp
            pure [c | d <- ds, let DiagnosticCode c = diagCode d, c == "G05002"]
          source = "@set part = \"上\"\n\n# 序論\n"
      lintCodes (headingFormat "{set.part}{title}") [("a.gm", source)] >>= (@?= [])
      lintCodes (fmtStyle "" "") [("a.gm", source)] >>= (@?= ["G05002"])
      lintCodes (fmtStyle "" "") [("a.gm", "@style-def paragraph caption title-format=\"{set.part}\"\n\n" <> source)] >>= (@?= [])
      lintCodes (headingFormat "{set.ns.part}{title}") [("a.gm", "@import common/v.gm * as ns\n\n# 序論\n"), ("common/v.gm", "@set part = \"上\"\n")] >>= (@?= [])
  ]
