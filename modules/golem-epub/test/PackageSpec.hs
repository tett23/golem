{- | Tests of the EPUB packaging (golem-epub ADR 0001): the package
document and the navigation document over hand-built values (Small), and
the zip container written to a temporary directory (Medium).
-}
module PackageSpec (packageTests) where

import Codec.Archive.Zip
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (fromGregorian)
import Golem.Doc.Assemble (Book (..), TocEntry (..))
import Golem.Doc.IR
import Golem.Epub
import Golem.Html
import Golem.Syntax.Span
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | a.gm and b.gm, in that order.
fidA, fidB :: FileId
ft :: FileTable
(fidA, fidB, ft) =
  let (a, t1) = registerFile "a.gm" emptyFileTable
      (b, t2) = registerFile "b.gm" t1
   in (a, b, t2)

-- | A horizontal Japanese book with an ISBN, a title reading and one author.
cfg0 :: EpubConfig
cfg0 =
  EpubConfig
    { epIdentifier = "urn:isbn:9784000000000",
      epTitle = "書名",
      epTitleReading = Just "しょめい",
      epLanguage = "ja",
      epDate = fromGregorian 2026 10 11,
      epPublisher = Just "出版社",
      epCreators = [EpubCreator "著者" (Just "ちょしゃ") "aut"],
      epVertical = False
    }

-- | The lines of a document that start with a prefix.
linesWith :: Text -> Text -> [Text]
linesWith prefix = filter (T.isPrefixOf prefix) . T.lines

opf :: EpubConfig -> Text
opf cfg = packageDocument cfg ["a.xhtml", "b.xhtml"] ["style.css"]

emptyBook :: Book
emptyBook =
  Book
    { bookDocs = [Document fidA [], Document fidB []],
      bookHeadings = Map.empty,
      bookFigures = Map.empty,
      bookListings = Map.empty,
      bookToc = [],
      bookTocDepth = Nothing,
      bookIndex = [],
      bookCitations = [],
      bookLabels = Map.empty,
      bookReferenced = Set.empty
    }

entry :: Int -> FileId -> Text -> Text -> TocEntry
entry l fid anchor title = TocEntry l Nothing [Text (mkSpan fid 0 1) title] anchor fid (mkSpan fid 0 1)

htmlConfig :: HtmlConfig
htmlConfig =
  HtmlConfig "書名" "ja" False "kanji" Map.empty Map.empty Map.empty Map.empty Map.empty noFace noFace Map.empty False "center" "space-between" "center" Set.empty Nothing (HtmlCode Nothing Nothing Nothing "0.5em" Nothing "0.25pt" False Nothing Nothing Nothing Nothing Map.empty)

-- | The archive writeEpub writes for a book of two empty files.
written :: IO Archive
written = withSystemTempDirectory "golem-epub" $ \tmp -> do
  let out = tmp </> "book.epub"
  writeEpub tmp out cfg0 ft emptyBook (renderXhtml htmlConfig ft emptyBook)
  -- read strictly: the directory is removed on return
  toArchive . BL.fromStrict <$> BS.readFile out

tests :: [TestTree]
tests =
  [ testGroup
      "package document"
      [ testCase "the identifier is the given ISBN" $
          linesWith "<dc:identifier" (opf cfg0) @?= ["<dc:identifier id=\"bookid\">urn:isbn:9784000000000</dc:identifier>"],
        testCase "the identifier is the manifest id when there is no ISBN" $
          linesWith "<dc:identifier" (opf cfg0 {epIdentifier = "urn:uuid:11111111-2222-4333-8444-555555555555"})
            @?= ["<dc:identifier id=\"bookid\">urn:uuid:11111111-2222-4333-8444-555555555555</dc:identifier>"],
        testCase "the title reading refines the title as file-as" $
          linesWith "<meta refines=\"#title\"" (opf cfg0) @?= ["<meta refines=\"#title\" property=\"file-as\">しょめい</meta>"],
        testCase "a creator has its MARC role and its reading" $
          (linesWith "<dc:creator" (opf cfg0), linesWith "<meta refines=\"#creator1\"" (opf cfg0))
            @?= ( ["<dc:creator id=\"creator1\">著者</dc:creator>"],
                  [ "<meta refines=\"#creator1\" property=\"role\" scheme=\"marc:relators\">aut</meta>",
                    "<meta refines=\"#creator1\" property=\"file-as\">ちょしゃ</meta>"
                  ]
                ),
        testCase "the publisher and the language are written" $
          (linesWith "<dc:publisher" (opf cfg0), linesWith "<dc:language" (opf cfg0)) @?= (["<dc:publisher>出版社</dc:publisher>"], ["<dc:language>ja</dc:language>"]),
        testCase "dcterms:modified is the date at 00:00:00 UTC" $
          linesWith "<meta property=\"dcterms:modified\"" (opf cfg0) @?= ["<meta property=\"dcterms:modified\">2026-10-11T00:00:00Z</meta>"],
        testCase "a vertical book progresses right to left" $
          linesWith "<spine" (opf cfg0 {epVertical = True}) @?= ["<spine page-progression-direction=\"rtl\">"],
        testCase "a horizontal book has no page-progression-direction" $
          linesWith "<spine" (opf cfg0) @?= ["<spine>"],
        testCase "the spine lists the pages in the order of the book, not the other items" $
          linesWith "<itemref" (packageDocument cfg0 ["b.xhtml", "a.xhtml"] ["style.css", "images/a.png"])
            @?= ["<itemref idref=\"item1\"/>", "<itemref idref=\"item2\"/>"],
        testCase "the manifest has the navigation document and each item with its media type" $
          linesWith "<item " (packageDocument cfg0 ["b.xhtml"] ["style.css", "images/a.png", "images/b.JPG", "fonts/x.otf"])
            @?= [ "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>",
                  "<item id=\"item1\" href=\"b.xhtml\" media-type=\"application/xhtml+xml\"/>",
                  "<item id=\"item2\" href=\"style.css\" media-type=\"text/css\"/>",
                  "<item id=\"item3\" href=\"images/a.png\" media-type=\"image/png\"/>",
                  "<item id=\"item4\" href=\"images/b.JPG\" media-type=\"image/jpeg\"/>",
                  "<item id=\"item5\" href=\"fonts/x.otf\" media-type=\"font/otf\"/>"
                ],
        testCase "metadata is escaped for XML" $
          linesWith "<dc:title" (opf cfg0 {epTitle = "A & B <C>"}) @?= ["<dc:title id=\"title\">A &amp; B &lt;C&gt;</dc:title>"]
      ],
    testGroup
      "navigation document"
      [ testCase "the TOC channel is nested by level and links each page" $
          let book = emptyBook {bookToc = [entry 1 fidA "intro" "はじめに", entry 2 fidA "s1" "節", entry 1 fidB "second" "次の章"]}
           in linesWith "<ol>" (navDocument cfg0 ft book)
                @?= ["<ol><li><a href=\"a.xhtml#intro\">はじめに</a><ol><li><a href=\"a.xhtml#s1\">節</a></li></ol></li><li><a href=\"b.xhtml#second\">次の章</a></li></ol>"],
        testCase "the nav element is the toc" $
          linesWith "<nav" (navDocument cfg0 ft emptyBook) @?= ["<nav epub:type=\"toc\" id=\"toc\">"]
      ],
    testGroup
      "container"
      [ testCase "the first entry is mimetype, stored without compression" $ do
          archive <- written
          take 1 [(eRelativePath e, eCompressionMethod e, fromEntry e) | e <- zEntries archive] @?= [("mimetype", NoCompression, "application/epub+zip")],
        testCase "the container, the package, the navigation, the CSS and the pages are in the archive" $ do
          archive <- written
          sort (filesInArchive archive)
            @?= ["META-INF/container.xml", "OEBPS/a.xhtml", "OEBPS/b.xhtml", "OEBPS/nav.xhtml", "OEBPS/package.opf", "OEBPS/style.css", "mimetype"],
        testCase "container.xml points at OEBPS/package.opf" $
          linesWith "<rootfiles>" containerXml @?= ["<rootfiles><rootfile full-path=\"OEBPS/package.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles>"]
      ]
  ]

packageTests :: TestTree
packageTests = testGroup "EPUB packaging (golem-epub ADR 0001)" tests
