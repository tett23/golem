{- | The figures block commands of .emet return with an SVG in a data:
source, and the benchmark of the drawing of paths that uses them (root
ADR 0439).
-}
module PathDrawingSpec (pathDrawingTests) where

import Codec.Archive.Zip (findEntryByPath, fromEntry, toArchive)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isSuffixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Assemble (Book (..))
import Golem.Doc.IR (Block (..), BlockBody (..), Document (..), Figure (..), pluginImagePrefix)
import Golem.Driver
import Golem.Eval.File (EvalResult (..))
import Golem.Project (Project (..), ProjectFailure (..), SourceFile (..))
import Golem.Syntax
import Golem.Syntax.Sha256 (sha256)
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Support
import System.Directory (listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

{- | A one-chapter project, a.gm, for PDF, HTML and EPUB with the fake
fonts, with more files and lines added to the manifest.
-}
withArt :: Text -> [(FilePath, BS.ByteString)] -> Text -> (FilePath -> IO a) -> IO a
withArt source files extra k = withSystemTempDirectory "golem-art" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["pdf", "html", "epub"]} <> extra))
  BS.writeFile (tmp </> "style.toml") (withBodyFont horizontalStyle)
  TIO.writeFile (tmp </> "a.gm") source
  writeFiles tmp (files <> fakeFontFiles)
  k tmp

-- | A .emet whose block command fig returns a figure of the source.
figureEmet :: Text -> Text -> BS.ByteString
figureEmet name src = TE.encodeUtf8 ("pub block " <> name <> " :: Blocks\n" <> name <> " = [" <> figureOf src <> "]\n")

-- | A figure of Emet of the source, without a number.
figureOf :: Text -> Text
figureOf src = "Block.FigureBlock (Block.Figure " <> emetString src <> " Nothing \"x\" Nothing Nothing [] Nothing False True)"

emetString :: Text -> Text
emetString s = "\"" <> T.replace "\"" "\\\"" s <> "\""

-- | Where HTML and EPUB put the image of these bytes, as for a plugin (docs/adr/0123).
imagePath :: BS.ByteString -> FilePath
imagePath bytes = "images/golem-plugin/" <> hexOf bytes <> ".svg"

hexOf :: BS.ByteString -> String
hexOf = concatMap (printf "%02x") . BS.unpack . sha256

triangle :: Text
triangle = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" width=\"100\" height=\"100\"><path d=\"M 10 10 L 90 10 L 50 90 Z\" fill=\"#336699\" stroke=\"#000000\"/></svg>"

emptySvg :: Text
emptySvg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" width=\"100\" height=\"100\"></svg>"

-- | An SVG with an element out of golem-pdf ADR 0009.
outOfRange :: Text
outOfRange = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" width=\"100\" height=\"100\"><foreignObject width=\"10\" height=\"10\"></foreignObject></svg>"

-- | The streams of a PDF that draw an SVG ('Golem.Pdf.Drawing.drawingContent').
drawingStreams :: BS.ByteString -> IO [BS.ByteString]
drawingStreams pdf = filter ("/GolemSRGB cs /GolemSRGB CS" `BS.isInfixOf`) <$> inflateAll pdf

-- | The PDF of a build of the project and its diagnostics.
pdfBuild :: FilePath -> IO (Maybe BS.ByteString, [Diagnostic])
pdfBuild tmp = do
  r <- build (defaultOptions tmp) {optFonts = fakeProvider, optTargets = Just [TargetPdf]}
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> Just <$> BS.readFile p
    _ -> pure Nothing
  pure (pdf, brDiagnostics r)

-- | The PDF and diagnostics of an SVG returned by a block command, and of it as a file of @figure.
bothWays :: Text -> IO ((Maybe BS.ByteString, [Diagnostic]), (Maybe BS.ByteString, [Diagnostic]))
bothWays svg = do
  fromData <- withArt "@import f.emet * as f\n\n@f.fig\n" [("f.emet", figureEmet "fig" ("data:image/svg+xml," <> svg))] "" pdfBuild
  fromFile <- withArt "@nonumber\n@figure ./images/a.svg alt=x\n" [("images/a.svg", TE.encodeUtf8 svg)] "" pdfBuild
  pure (fromData, fromFile)

evaluated :: FilePath -> IO Evaluated
evaluated tmp = evaluateProject Dev tmp >>= either (\f -> assertFailure (show (pfDiagnostics f)) >> fail "unreachable") pure

-- | The codes of the evaluation, without the notice of no style.toml.
codesIn :: Evaluated -> [Text]
codesIn e = [c | d <- evDiagnostics e, let DiagnosticCode c = diagCode d, c /= "G03023"]

-- | The figures of a file of the project.
figuresOf :: Evaluated -> FilePath -> [Figure]
figuresOf e path = [f | (fid, sf) <- Map.toList (projectSources (evProject e)), sfPath sf == path, Just r <- [Map.lookup fid (evResults e)], Block _ _ _ (FigureBlock f) <- docBlocks (erDocument r)]

-- | The benchmark book of scripts/bench/path-drawing with fake fonts, this seed and this many shapes a page.
withBench :: Int -> Int -> (FilePath -> IO a) -> IO a
withBench seed count k = withSystemTempDirectory "golem-bench" $ \tmp -> do
  let bench = "../../scripts/bench/path-drawing"
  forM_ ["book.gm", "art.emet"] $ \f -> BS.readFile (bench </> f) >>= BS.writeFile (tmp </> f)
  manifest <- TIO.readFile (bench </> "manifest.toml")
  TIO.writeFile (tmp </> "manifest.toml") (T.replace "seed = 1\n" ("seed = " <> T.pack (show seed) <> "\n") (T.replace "shapes = 1000\n" ("shapes = " <> T.pack (show count) <> "\n") manifest))
  BS.writeFile (tmp </> "style.toml") (withBodyFont horizontalStyle)
  writeFiles tmp fakeFontFiles
  k tmp

pathDrawingTests :: TestTree
pathDrawingTests =
  testGroup
    "the figures of block commands of .emet and the benchmark of path drawing (root ADR 0439)"
    [ testCase "root ADR 0439 I1: the same seed gives the same PDF, twice" $ do
        a <- withBench 1 4 pdfBuild
        b <- withBench 1 4 pdfBuild
        [d | d <- snd a, isError d] @?= []
        assertBool "a PDF" (isJust (fst a))
        fst a @?= fst b,
      testCase "root ADR 0439 I2: seeds 1 and 2 give different PDFs" $ do
        a <- withBench 1 4 pdfBuild
        b <- withBench 2 4 pdfBuild
        [d | d <- snd a <> snd b, isError d] @?= []
        assertBool "PDFs" (isJust (fst a) && isJust (fst b))
        assertBool "different PDFs" (fst a /= fst b),
      testCase "root ADR 0439 I1: the benchmark book has ten figures of the shapes" $
        withBench 1 4 $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= []
          let figures = figuresOf e "book.gm"
          length figures @?= 10
          assertBool "plugin images" (all ((pluginImagePrefix `T.isPrefixOf`) . figSource) figures)
          case evBook e of
            Just b -> do
              Map.size (bookImages b) @?= 10
              map (length . occurrences "<path ") (Map.elems (bookImages b)) @?= replicate 10 4
            Nothing -> assertFailure "no book",
      testCase "root ADR 0439 I3: a triangle of a data: source draws as the same SVG as a file" $ do
        ((dataPdf, dataDiags), (filePdf, fileDiags)) <- bothWays triangle
        [d | d <- dataDiags <> fileDiags, isError d] @?= []
        a <- maybe (assertFailure "no PDF of data:") drawingStreams dataPdf
        b <- maybe (assertFailure "no PDF of the file") drawingStreams filePdf
        assertBool "a drawing" (not (null a))
        a @?= b,
      testCase "root ADR 0439 I3: an empty SVG of a data: source draws as the same SVG as a file" $ do
        ((dataPdf, _), (filePdf, _)) <- bothWays emptySvg
        a <- maybe (assertFailure "no PDF of data:") drawingStreams dataPdf
        b <- maybe (assertFailure "no PDF of the file") drawingStreams filePdf
        assertBool "a drawing" (not (null a))
        a @?= b,
      testCase "root ADR 0439 I3: an SVG out of golem-pdf ADR 0009 has the diagnostic of the file" $ do
        ((_, dataDiags), (_, fileDiags)) <- bothWays outOfRange
        let codes ds = sort [diagCode d | d <- ds, isError d]
        assertBool "an error" (not (null (codes fileDiags)))
        codes dataDiags @?= codes fileDiags,
      testCase "root ADR 0439 I4: two figures of the same SVG point at one image" $
        withArt "@import f.emet * as f\n\n@f.fig\n\n@f.fig\n" [("f.emet", figureEmet "fig" ("data:image/svg+xml," <> triangle))] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= []
          let figures = figuresOf e "a.gm"
              expected = pluginImagePrefix <> T.pack (hexOf (TE.encodeUtf8 triangle)) <> ".svg"
          map figSource figures @?= [expected, expected]
          fmap (Map.toList . bookImages) (evBook e) @?= Just [(expected, TE.encodeUtf8 triangle)],
      testCase "root ADR 0439 I6: HTML and EPUB have the image of a plugin's name and an <img> of it" $
        withArt "# 章\n\n@import f.emet * as f\n\n@f.fig\n" [("f.emet", figureEmet "fig" ("data:image/svg+xml," <> triangle))] "" $ \tmp -> do
          r <- build (defaultOptions tmp) {optFonts = fakeProvider}
          filter isError (brDiagnostics r) @?= []
          let svg = TE.encodeUtf8 triangle
              path = imagePath svg
          BS.readFile (tmp </> "build/html" </> path) >>= (@?= svg)
          page <- TIO.readFile (tmp </> "build/html/a.html")
          assertBool (T.unpack page) (("<img src=\"" <> T.pack path <> "\"") `T.isInfixOf` page)
          epubs <- filter (".epub" `isSuffixOf`) <$> listDirectory (tmp </> "build/epub")
          case epubs of
            [f] -> do
              a <- toArchive . BL.fromStrict <$> BS.readFile (tmp </> "build/epub" </> f)
              fmap (BL.toStrict . fromEntry) (findEntryByPath ("OEBPS/" <> path) a) @?= Just svg
              let pages = [BL.toStrict (fromEntry en) | Just en <- [findEntryByPath "OEBPS/a.xhtml" a]]
              assertBool (show pages) (any (TE.encodeUtf8 ("src=\"" <> T.pack path <> "\"") `BS.isInfixOf`) pages)
            other -> assertFailure (show other),
      testCase "root ADR 0439 I7: the figures a block command may not return are E06104"
        $ forM_
          [ ("a file of the project", figureEmet "fig" "images/a.svg"),
            ("a data: source of PNG", figureEmet "fig" "data:image/png,x"),
            ("a web image", TE.encodeUtf8 ("pub block fig :: Blocks\nfig = [Block.FigureBlock (Block.Figure " <> emetString ("data:image/svg+xml," <> triangle) <> " (Just \"images/a.png\") \"x\" Nothing Nothing [] Nothing False True)]\n")),
            ("a figure in a bulleted list", TE.encodeUtf8 ("pub block fig :: Blocks\nfig = [Block.BulletList [Block.ListItem Nothing [" <> figureOf ("data:image/svg+xml," <> triangle) <> "]]]\n"))
          ]
        $ \(what, emet) ->
          withArt "@import f.emet * as f\n\n@f.fig\n" [("f.emet", emet), ("images/a.svg", TE.encodeUtf8 triangle), ("images/a.png", "\x89PNG\r\n\x1a\n")] "" $ \tmp -> do
            e <- evaluated tmp
            assertEqual what ["E06104"] (codesIn e)
            assertEqual what [] (figuresOf e "a.gm"),
      testCase "root ADR 0439 I7: a filter that makes a figure of a data: source is E06104"
        $ withArt
          "本文。\n"
          [("f.emet", TE.encodeUtf8 ("pub filter add :: Blocks -> Blocks\nadd bs = bs ++ [" <> figureOf ("data:image/svg+xml," <> triangle) <> "]\n"))]
          "\n[[filters]]\nfunction = \"f.emet\"\nfilter = \"add\"\nfiles = [\"a.gm\"]\n"
        $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["E06104"],
      testCase "root ADR 0439 I7: a data: source of @figure in the manuscript is a URL, G02060" $
        withArt "@figure \"data:image/svg+xml,<svg></svg>\" alt=x\n" [] "" $ \tmp -> do
          e <- evaluated tmp
          assertBool (show (codesIn e)) ("G02060" `elem` codesIn e && "G02033" `notElem` codesIn e)
          figuresOf e "a.gm" @?= []
    ]
