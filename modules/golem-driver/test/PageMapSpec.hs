module PageMapSpec (pageMapTests) where

import Codec.Archive.Zip (findEntryByPath, fromEntry, toArchive)
import Codec.Picture.Jpg qualified as Jpeg
import Codec.Picture.Png qualified as Png
import Codec.Picture.Types qualified as J
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (isLeft)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Word (Word8)
import Golem.Assemble (Book (..))
import Golem.Doc.IR
import Golem.Driver
import Golem.Driver.PageMap
import Golem.Project.Files (Files (..), diskFiles)
import Golem.Syntax
import Golem.Syntax.Sha256 (sha256)
import Hedgehog (forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Numeric (showHex)
import Support (codesOf, withChapters)
import System.Directory (doesFileExist, listDirectory)
import System.FilePath ((</>))
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

pageMapTests :: TestTree
pageMapTests =
  testGroup
    "root ADR 0386 page map"
    [ testProperty "root ADR 0386 I1: inv1_page_list_and_page_colors_property" $ property $ do
        count <- forAll (Gen.int (Range.linear 0 4))
        let positions = take count [0 .. 3]
            mapping = PageMap hashes [FixedPage (offset + 1) (T.pack (show offset)) (Just ("a.gm", 0, offset)) | offset <- positions]
        case resolvePageMap sources files book mapping of
          Left _ -> False === True
          Right (anchors, links) -> do
            map (\(label, _, _) -> label) links === map (T.pack . show) positions
            [ident | (_, _, ident) <- links] === [ident | (_, ident, _) <- Map.findWithDefault [] spanA anchors],
      testCase "root ADR 0386 I1: missing mapping reports G03260" $ checkFailure Nothing False "G03260",
      testCase "root ADR 0386 I1: unreadable mapping reports G03261" $ checkFailure (Just "{}") True "G03261",
      testCase "root ADR 0386 I1: JSON syntax reports G03262" $ checkFailure (Just "{") False "G03262",
      testCase "root ADR 0386 I1: JSON schema reports G03263" $ checkFailure (Just "{}") False "G03263",
      testCase "root ADR 0386 I1: stale mapping reports G03264" $ checkFailure (Just "{\"sources\":{\"a.gm\":\"0000000000000000000000000000000000000000000000000000000000000000\"},\"pages\":[]}") False "G03264",
      testCase "root ADR 0386 I1: invalid position reports G03265" $ checkFailure (Just ("{\"sources\":{\"a.gm\":\"" <> hex (sha256 "abcd\n") <> "\"},\"pages\":[{\"page\":1,\"label\":\"1\",\"file\":\"a.gm\",\"line\":99,\"character\":0}]}")) False "G03265",
      testCase "root ADR 0386 I1: mapped pages preserve their physical order" $ do
        let mapping = PageMap hashes [FixedPage 1 "i" (Just ("a.gm", 0, 0)), FixedPage 2 "1" (Just ("a.gm", 0, 2))]
        case resolvePageMap sources files book mapping of
          Right (anchors, links) -> do
            links @?= [("i", "a.xhtml", "GolemFixedPage-1"), ("1", "a.xhtml", "GolemFixedPage-2")]
            Map.lookup spanA anchors @?= Just [(0, "GolemFixedPage-1", "i"), (2, "GolemFixedPage-2", "1")]
          Left problem -> assertFailure (show problem),
      testCase "root ADR 0386 I1: merged escapes and expression output retain their positions" $ do
        let raw = "a\\[b [= 1 + 1]"
            sp = mkSpan fid 0 (BS.length (TE.encodeUtf8 raw))
            merged = book {bookDocs = [Document fid [Block sp Nothing Nothing (Paragraph Nothing [Text sp "a[b 2"])]]}
            sourceMap = Map.singleton fid ("a.gm", raw)
            mapping = PageMap (Map.singleton "a.gm" (hex (sha256 (TE.encodeUtf8 raw)))) [FixedPage 1 "a" (Just ("a.gm", 0, 3)), FixedPage 2 "b" (Just ("a.gm", 0, 5))]
        case resolvePageMap sourceMap files merged mapping of
          Left problem -> assertFailure (show problem)
          Right (anchors, _) -> Map.lookup sp anchors @?= Just [(2, "GolemFixedPage-1", "a"), (4, "GolemFixedPage-2", "b")],
      testCase "root ADR 0386 I1: repeated source positions have no ambiguous anchor" $ do
        let duplicated = book {bookDocs = bookDocs book <> bookDocs book}
        resolvePageMap sources files duplicated (PageMap hashes [FixedPage 1 "1" (Just ("a.gm", 0, 0))]) @?= Right (Map.empty, []),
      testCase "root ADR 0386 I1: imported source positions link to their containing document" $ do
        let (imported, files') = registerFile "part.gm" files
            sp = mkSpan imported 0 4
            importedBook = book {bookDocs = [Document fid [Block sp Nothing Nothing (Paragraph Nothing [Text sp "abcd"])]]}
            sources' = Map.insert imported ("part.gm", "abcd") sources
            hashes' = Map.insert "part.gm" (hex (sha256 "abcd")) hashes
        case resolvePageMap sources' files' importedBook (PageMap hashes' [FixedPage 1 "1" (Just ("part.gm", 0, 0))]) of
          Left problem -> assertFailure (show problem)
          Right (_, links) -> links @?= [("1", "a.xhtml", "GolemFixedPage-1")],
      testCase "root ADR 0386 I1: pages without body positions are omitted" $
        resolvePageMap sources files book (PageMap hashes [FixedPage 1 "blank" Nothing]) @?= Right (Map.empty, []),
      testCase "root ADR 0386 I1: changed manuscript is rejected" $
        assertBool "stale hash" (isLeft (resolvePageMap (Map.singleton fid ("a.gm", "changed")) files book (PageMap hashes []))),
      testCase "root ADR 0386 I1: reversed physical pages are rejected" $
        assertBool "physical order" (isLeft (resolvePageMap sources files book (PageMap hashes [FixedPage 2 "2" Nothing, FixedPage 1 "1" Nothing]))),
      testCase "root ADR 0386 I1: invalid source coordinates are rejected" $
        assertBool "coordinate" (isLeft (resolvePageMap sources files book (PageMap hashes [FixedPage 1 "1" (Just ("a.gm", 9, 0))]))),
      testCase "root ADR 0386 I1: HTML and EPUB recolour only monochrome SVG assets" $
        withChapters "[figures]\ncolor = \"accent\"\n[color.swatches.accent]\ncmyk = [0, 100, 100, 0]\n" [("a.gm", "@nonumber\n@figure mono.svg alt=\"mono\"\n\n@nonumber\n@figure multi.svg alt=\"multi\"\n")] [("mono.svg", monoSvg), ("multi.svg", multiSvg)] $ \root -> do
          result <- build (defaultOptions root) {optTargets = Just [TargetHtml, TargetEpub]}
          codesOf (filter isError (brDiagnostics result)) @?= []
          mono <- BS.readFile (root </> "build/html/mono.svg")
          multi <- BS.readFile (root </> "build/html/multi.svg")
          assertBool "single colour uses swatch RGB" ("rgb(255,0,0)" `BS.isInfixOf` mono)
          multi @?= TE.encodeUtf8 multiSvg
          archive <- toArchive <$> BL.readFile (root </> "build/epub/book.epub")
          fmap (BL.toStrict . fromEntry) (findEntryByPath "OEBPS/mono.svg" archive) @?= Just mono
          fmap (BL.toStrict . fromEntry) (findEntryByPath "OEBPS/multi.svg" archive) @?= Just multi,
      testCase "root ADR 0403 I1: JPEG becomes linked PNG in HTML and EPUB while multi-colour bytes remain" $
        withChapters colorStyle [("a.gm", "@nonumber\n@figure gray.jpg alt=\"gray\"\n\n@nonumber\n@figure multi.jpg alt=\"multi\"\n")] [] $ \root -> do
          BS.writeFile (root </> "gray.jpg") grayJpeg
          BS.writeFile (root </> "multi.jpg") multiJpeg
          result <- build (defaultOptions root) {optTargets = Just [TargetHtml, TargetEpub]}
          codesOf (filter isError (brDiagnostics result)) @?= []
          names <- listDirectory (root </> "build/html/images/golem-color")
          name <- case names of
            [one] -> pure one
            _ -> assertFailure ("expected one generated PNG, got " <> show names) >> pure "missing"
          let path = "images/golem-color/" <> name
          png <- BS.readFile (root </> "build/html" </> path)
          assertBool "PNG signature" (BS.take 8 png == BS.pack [137, 80, 78, 71, 13, 10, 26, 10])
          html <- TIO.readFile (root </> "build/html/a.xhtml")
          assertBool "HTML links to generated PNG" (T.pack path `T.isInfixOf` html)
          BS.readFile (root </> "build/html/multi.jpg") >>= (@?= multiJpeg)
          archive <- toArchive <$> BL.readFile (root </> "build/epub/book.epub")
          fmap (BL.toStrict . fromEntry) (findEntryByPath ("OEBPS/" <> path) archive) @?= Just png
          fmap (BL.toStrict . fromEntry) (findEntryByPath "OEBPS/multi.jpg" archive) @?= Just multiJpeg,
      testCase "root ADR 0403 I2: malformed recolouring removes stale web outputs with G08113" $
        withChapters colorStyle [("a.gm", "@nonumber\n@figure gray.jpg alt=\"gray\"\n")] [] $ \root -> do
          BS.writeFile (root </> "gray.jpg") grayJpeg
          good <- build (defaultOptions root) {optTargets = Just [TargetHtml, TargetEpub]}
          codesOf (filter isError (brDiagnostics good)) @?= []
          BS.writeFile (root </> "gray.jpg") (BS.take 24 grayJpeg)
          bad <- build (defaultOptions root) {optTargets = Just [TargetHtml, TargetEpub]}
          codesOf (filter isError (brDiagnostics bad)) @?= ["G08113"]
          doesFileExist (root </> "build/html/a.xhtml") >>= (@?= False)
          doesFileExist (root </> "build/epub/book.epub") >>= (@?= False),
      testCase "root ADR 0403 I2: PNG opacity is preserved in copied web output" $
        withChapters colorStyle [("a.gm", "@nonumber\n@figure gray.png alt=\"gray\"\n")] [] $ \root -> do
          BS.writeFile (root </> "gray.png") alphaPng
          result <- build (defaultOptions root) {optTargets = Just [TargetHtml]}
          codesOf (filter isError (brDiagnostics result)) @?= []
          bytes <- BS.readFile (root </> "build/html/gray.png")
          case Png.decodePng bytes of
            Right (J.ImageRGBA8 pixels) -> J.pixelAt pixels 0 0 @?= J.PixelRGBA8 255 128 128 128
            other -> assertFailure (either id (const "unexpected pixels") other),
      testCase "root ADR 0386 I1: EPUB links resolve to actual body anchors" $
        withChapters "" [("a.gm", "abcd\n")] [] $ \root -> do
          manifest <- TIO.readFile (root </> "manifest.toml")
          TIO.writeFile (root </> "manifest.toml") (T.replace "[targets.epub]" "[targets.epub]\npage-map = \"pages.json\"" manifest)
          TIO.writeFile (root </> "pages.json") ("{\"sources\":{\"a.gm\":\"" <> hex (sha256 "abcd\n") <> "\"},\"pages\":[{\"page\":1,\"label\":\"i\",\"file\":\"a.gm\",\"line\":0,\"character\":0},{\"page\":2,\"label\":\"1\",\"file\":\"a.gm\",\"line\":0,\"character\":2}]}")
          result <- build (defaultOptions root) {optTargets = Just [TargetEpub]}
          codesOf (filter isError (brDiagnostics result)) @?= []
          archive <- toArchive <$> BL.readFile (root </> "build/epub/book.epub")
          let entry path = maybe "" (TE.decodeUtf8 . BL.toStrict . fromEntry) (findEntryByPath path archive)
              nav = entry "OEBPS/nav.xhtml"
              body = entry "OEBPS/a.xhtml"
          map (\ident -> T.count ("id=\"" <> ident <> "\"") body) ["GolemFixedPage-1", "GolemFixedPage-2"] @?= [1, 1]
          assertBool "ordered links" ("a.xhtml#GolemFixedPage-1\">i</a></li><li><a href=\"a.xhtml#GolemFixedPage-2\">1</a>" `T.isInfixOf` nav),
      testCase "root ADR 0386 I1: whitespace-only page labels are rejected" $
        assertBool "a navigation label needs visible text" (isLeft (decodePageMap "{\"sources\":{},\"pages\":[{\"page\":1,\"label\":\"   \"}]}")),
      testCase "root ADR 0386 I1: malformed JSON and schema have distinct causes" $ do
        case decodePageMap "{" of { Left (PageMapJson _) -> pure (); other -> assertFailure (show other) }
        assertBool "schema rejected" (isLeft (decodePageMap "{\"sources\":{},\"pages\":[{\"page\":0,\"label\":\"x\"}]}"))
    ]
  where
    colorStyle = "[figures]\ncolor = \"accent\"\n[color.swatches.accent]\ncmyk = [0, 100, 100, 0]\n"
    grayJpeg = BL.toStrict (Jpeg.encodeDirectJpegAtQualityWithMetadata 100 mempty (J.generateImage (\_ _ -> 0 :: Word8) 2 1))
    multiJpeg = BL.toStrict (Jpeg.encodeDirectJpegAtQualityWithMetadata 100 mempty (J.generateImage (\x _ -> if x < 8 then J.PixelRGB8 255 0 0 else J.PixelRGB8 0 0 255) 16 8))
    alphaPng = BL.toStrict (Png.encodePng (J.generateImage (\_ _ -> J.PixelRGBA8 128 128 128 128) 1 1))
    monoSvg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><path fill=\"black\" d=\"M 0 0 L 10 10\"/></svg>"
    multiSvg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><path fill=\"black\" d=\"M 0 0 L 10 10\"/><path fill=\"blue\" d=\"M 1 1 L 8 8\"/></svg>"
    checkFailure json unreadable expected = withChapters "" [("a.gm", "abcd\n")] [] $ \root -> do
      manifest <- TIO.readFile (root </> "manifest.toml")
      TIO.writeFile (root </> "manifest.toml") (T.replace "[targets.epub]" "[targets.epub]\npage-map = \"pages.json\"" manifest)
      maybe (pure ()) (TIO.writeFile (root </> "pages.json")) json
      let filesOnDisk = diskFiles root
          inputFiles = if unreadable then filesOnDisk {filesRead = \path -> if path == "pages.json" then ioError (userError "test read failure") else filesRead filesOnDisk path} else filesOnDisk
      result <- build (defaultOptions root) {optTargets = Just [TargetEpub], optFiles = inputFiles}
      codesOf (filter isError (brDiagnostics result)) @?= [expected]
      brWritten result @?= []
    (fid, files) = registerFile "a.gm" emptyFileTable
    source = "abcd"
    sources = Map.singleton fid ("a.gm", source)
    spanA = mkSpan fid 0 4
    hashes = Map.singleton "a.gm" (hex (sha256 (TE.encodeUtf8 source)))
    book =
      Book
        { bookDocs = [Document fid [Block spanA Nothing Nothing (Paragraph Nothing [Text spanA source])]],
          bookHeadings = Map.empty,
          bookFigures = Map.empty,
          bookListings = Map.empty,
          bookTables = Map.empty,
          bookToc = [],
          bookTocDepth = Nothing,
          bookIndexes = [],
          bookBibliographies = [],
          bookCiteMarks = Map.empty,
          bookLabels = Map.empty,
          bookReferenced = Set.empty,
          bookChapterOf = [],
          bookChannels = [],
          bookChannelDecls = Map.empty,
          bookTitleSeparators = Map.empty,
          bookImages = Map.empty
        }
    hex = T.pack . concatMap (\byte -> let h = showHex byte "" in replicate (2 - length h) '0' <> h) . BS.unpack
