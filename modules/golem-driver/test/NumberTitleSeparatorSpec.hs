{- | The separator between a number and its title written in the styles
(Golem ADR 0372): number-title-separator of [headings.<l>] for headings,
the table of contents and the running heads, that of the paragraph style
caption for the captions of figures, tables and code blocks, in every
output.
-}
module NumberTitleSeparatorSpec (numberTitleSeparatorTests) where

import Codec.Archive.Zip (findEntryByPath, fromEntry, toArchive)
import Control.Monad (filterM, join)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isSuffixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Golem.Typeset (CodeCaption (..), CodeInfo (..), PartLine (..), PdfLayout (..), PlacedFigure (..), layoutPdf)
import Support
import System.Directory (doesFileExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | An SVG of 300 by 100 with an unpainted frame.
wideSvg :: [(FilePath, BS.ByteString)]
wideSvg = [("images/wide.svg", TE.encodeUtf8 "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"300\" height=\"100\"><rect width=\"300\" height=\"100\" fill=\"none\"/></svg>")]

{- | A style of 30 characters a line with numbered chapters, figures,
tables and code blocks, and the keys of [headings.1], of the paragraph
style body and of the paragraph style caption.
-}
sepStyle :: T.Text -> T.Text -> T.Text -> BS.ByteString
sepStyle heading body caption =
  horizontal30
    ( TE.encodeUtf8 . T.concat $
        [ "\n[headings.1]\nnumber = \"{n}\"\n",
          heading,
          "\n[figures]\nnumber = \"図{n}\"\n\n[tables]\nnumber = \"表{n}\"\n\n[code]\nnumber = \"L{n}\"\n",
          "\n[paragraph-styles.body]\n",
          body,
          "\n[paragraph-styles.caption]\n",
          caption
        ]
    )

-- | A table of contents, a chapter heading, a figure, a table and a code block, each with a caption.
captioned :: T.Text
captioned = "@toc\n\n# 海\n\n@figure images/wide.svg alt=\"t\"\n  空\n\n@caption 表題\n| a | b |\n|---|---|\n| 1 | 2 |\n\n@caption 例\n```\na\n```\n"

-- | The text of a line of a part.
partText :: PartLine -> T.Text
partText l = T.concat [bcText c | Box _ c <- lineItems (ptLine l)]

-- | Lays out one chapter with the fake fonts.
layoutOne :: BS.ByteString -> T.Text -> IO PdfLayout
layoutOne style source = do
  let manifest = TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["pdf"]})
  r <- withMiniInput fakeProvider manifest style source wideSvg layoutPdf
  either (assertFailure . show . map diagCode) pure (join r)

-- | The caption lines of the figures, the tables and the code blocks of a layout, as text.
captionTexts :: PdfLayout -> ([T.Text], [T.Text], [T.Text])
captionTexts pl =
  ( map partText (concatMap pfCaption (Map.elems (plFigures pl))),
    map partText (concatMap ccLines (Map.elems (plTableCaptions pl))),
    map partText (concat [ciCaption ci | ci <- Map.elems (plCodes pl)])
  )

-- | The outputs of one chapter: the HTML page, the EPUB navigation document and the plain text.
data Outputs = Outputs {oHtml :: T.Text, oNav :: T.Text, oText :: T.Text}

-- | Builds one chapter to HTML, EPUB and plain text.
buildOutputs :: BS.ByteString -> T.Text -> IO Outputs
buildOutputs style source = withSystemTempDirectory "golem-0372" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n\n[targets.text]\n")
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  writeFiles tmp wideSvg
  r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub, TargetText]}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  html <- TIO.readFile (tmp </> "build/html/a.xhtml")
  archive <- toArchive <$> BL.readFile (tmp </> "build/epub/book.epub")
  texts <- textFiles (tmp </> "build/text")
  text <- T.concat <$> mapM TIO.readFile texts
  pure (Outputs html (maybe "" (TE.decodeUtf8 . BL.toStrict . fromEntry) (findEntryByPath "OEBPS/nav.xhtml" archive)) text)

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

numberTitleSeparatorTests :: [TestTree]
numberTitleSeparatorTests = separatorKeyTests <> outputTests

-- | The separators in the outputs.
outputTests :: [TestTree]
outputTests =
  [ testCase "ADR 0372 I1: PDF: the heading and @toc take the separator of [headings.1], the captions that of caption" $ do
      pl <- layoutOne (sepStyle "number-title-separator = \"：\"\n" "" "number-title-separator = \"／\"\n") captioned
      length (filter ("1：海" `T.isPrefixOf`) (lineTexts pl)) @?= 2
      captionTexts pl @?= (["図1／空"], ["表1／表題"], ["L1／例"]),
    testCase "ADR 0372 I1: PDF: the running head heading.1.numbered takes the separator of the heading" $ do
      let style =
            BS.concat
              [ replaceIn "lines = 30\n" "lines = 6\n" horizontalStyle,
                TE.encodeUtf8 "\n[headings.1]\nnumber = \"{n}\"\nnumber-title-separator = \"：\"\n\n",
                "[masters.body]\nrunning-head = { position = \"top-outside\", content = \"heading.1.numbered\" }\n"
              ]
      (heads, _) <- layoutHeads miniManifest style [("a.gm", "# 海\n\n" <> T.replicate (12 * 11) "あ" <> "\n")]
      Map.lookup 2 heads @?= Just ["1：海"],
    testCase "ADR 0372 I1: HTML, EPUB and plain text: the heading, the tables of contents and the captions" $ do
      o <- buildOutputs (sepStyle "number-title-separator = \"：\"\n" "" "number-title-separator = \"／\"\n") captioned
      has (oHtml o) "<span class=\"number\">1</span>：海</h1>"
      has (oHtml o) ">1：海</a>"
      has (oHtml o) "<span class=\"number\">図1</span>／空"
      has (oHtml o) "<caption><span class=\"number\">表1</span>／表題"
      has (oHtml o) "<figcaption>L1／例</figcaption>"
      has (oNav o) ">1：海</a>"
      mapM_ (has (oText o)) ["1：海", "図1／空", "表1／表題", "L1／例"],
    testCase "ADR 0372 I1: an empty string joins the number and the title with nothing" $ do
      pl <- layoutOne (sepStyle "number-title-separator = \"\"\n" "" "number-title-separator = \"\"\n") captioned
      length (filter ("1海" `T.isPrefixOf`) (lineTexts pl)) @?= 2
      captionTexts pl @?= (["図1空"], ["表1表題"], ["L1例"])
      o <- buildOutputs (sepStyle "number-title-separator = \"\"\n" "" "number-title-separator = \"\"\n") captioned
      has (oHtml o) "<span class=\"number\">1</span>海</h1>"
      has (oHtml o) "<figcaption>L1例</figcaption>",
    testCase "ADR 0372 I1: a number without a title has no separator" $ do
      let style = sepStyle "" "" "number-title-separator = \"／\"\n"
          source = "# 海\n\n@figure images/wide.svg alt=\"t\"\n"
      pl <- layoutOne style source
      captionTexts pl @?= (["図1"], [], [])
      o <- buildOutputs style source
      has (oHtml o) "<span class=\"number\">図1</span></figcaption>"
      has (oText o) "［図1］",
    testCase "ADR 0372: caption takes the separator of body through based-on; headings keep that of the language" $ do
      let style = sepStyle "" "number-title-separator = \"＊\"\n" ""
      pl <- layoutOne style captioned
      length (filter ("1\x3000海" `T.isPrefixOf`) (lineTexts pl)) @?= 2
      captionTexts pl @?= (["図1＊空"], ["表1＊表題"], ["L1＊例"]),
    testCase "ADR 0372: @style-def of caption in a file sets the separator of the captions of that file" $ do
      o <- buildOutputs (sepStyle "" "" "number-title-separator = \"／\"\n") ("@style-def paragraph caption number-title-separator=\"＋\"\n\n" <> captioned)
      has (oHtml o) "<span class=\"number\">図1</span>＋空"
      has (oHtml o) "<figcaption>L1＋例</figcaption>",
    testCase "ADR 0372: without number-title-separator, the separator of the language" $ do
      pl <- layoutOne (sepStyle "" "" "") captioned
      length (filter ("1\x3000海" `T.isPrefixOf`) (lineTexts pl)) @?= 2
      captionTexts pl @?= (["図1\x3000空"], ["表1\x3000表題"], ["L1\x3000例"])
  ]

-- | The codes of the errors of building one chapter to HTML.
errorCodes :: BS.ByteString -> IO [DiagnosticCode]
errorCodes style = withSystemTempDirectory "golem-0372" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n")
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") "# 海\n"
  r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
  pure (map diagCode (filter isError (brDiagnostics r)))

-- | The keys are read where they are written, and rejected where they cannot be.
separatorKeyTests :: [TestTree]
separatorKeyTests =
  [ testCase "ADR 0372: a separator that is not a string is G03006, in [headings.1] and in a paragraph style" $ do
      errorCodes (sepStyle "number-title-separator = 1\n" "" "") >>= (@?= [DiagnosticCode "G03006"])
      errorCodes (sepStyle "" "" "number-title-separator = true\n") >>= (@?= [DiagnosticCode "G03006"]),
    testCase "ADR 0372: the paragraph style code cannot have a separator (G03006)" $
      errorCodes (horizontalStyle <> TE.encodeUtf8 "\n[paragraph-styles.code]\nnumber-title-separator = \"：\"\n") >>= (@?= [DiagnosticCode "G03006"])
  ]
