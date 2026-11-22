module NestedFiguresSpec (tests) where

import Codec.Archive.Zip (findEntryByPath, fromEntry, toArchive)
import Control.Monad (forM_, when)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver (BuildOptions (..), BuildResult (..), Target (..), build, defaultOptions)
import Golem.Layout.Paginate (PageOut (..), Slotted (..))
import Golem.Project.Files (Files (..))
import Golem.Syntax
import Golem.Typeset (PdfInput (..), PdfLayout (..), layoutPdf, renderPdfLeafTexts, renderPdfStructure)
import Support (fakeProvider, horizontalStyle, layoutMini, miniManifest, withMiniInput, writeProject)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "root ADR 0377: nested figures"
    [ testCase "root ADR 0377: repeated nested figures load their shared source once" $ do
        let files = sharedFigureFiles
            manuscript = sharedFigureSource
            sharedStyle = sharedFiguresStyle
        result <- withMiniInput fakeProvider miniManifest sharedStyle manuscript files $ \inp geometry fonts -> do
          assetReads <- newIORef (0 :: Int)
          let sourceFiles = piFiles inp
              counted path = do
                when (path == "images/shared.svg") (modifyIORef' assetReads (+ 1))
                filesRead sourceFiles path
          actual <- layoutPdf inp {piFiles = sourceFiles {filesRead = counted}} geometry fonts
          readIORef assetReads >>= (@?= 1)
          case actual of
            Left diagnostics -> assertFailure (show diagnostics)
            Right layout -> length [() | page <- plPages layout, (_, SFigure _) <- poSlots page] @?= 3
          tree <- renderPdfStructure "test" fakeProvider inp
          case tree of
            Left diagnostics -> assertFailure (show diagnostics)
            Right value -> do
              let roles = map (T.takeWhile (/= ' ') . T.strip) (T.lines value)
              length (filter (== "Figure") roles) @?= 3
              length (filter (== "Caption") roles) @?= 3
          leaves <- renderPdfLeafTexts "test" fakeProvider inp
          case leaves of
            Left diagnostics -> assertFailure (show diagnostics)
            Right values -> forM_ ["Fig1", "Fig2", "Fig3", "one", "two", "three"] $ \text ->
              assertBool (show values) (text `T.isInfixOf` T.concat [value | (_, _, value) <- values])
        either (assertFailure . show) pure result,
      testCase "root ADR 0377: nested figure errors retain each original position" $ do
        let broken = [("images/shared.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><linearGradient id=\"g\"/></svg>")]
            starts = positionsOf "  @figure" sharedFigureSource
        result <- layoutMini sharedFiguresStyle sharedFigureSource broken
        case result of
          Left diagnostics -> do
            let errors = filter ((== DiagnosticCode "G08011") . diagCode) diagnostics
            map (spanStart . diagSpan) errors @?= starts
          Right _ -> assertFailure "unsupported nested SVG was silently omitted",
      testCase "root ADR 0377: an invalid figure inside a caption stays rejected" $ do
        let manuscript = "@nonumber\n@figure images/shared.svg alt=\"outer\"\n  @figure images/shared.svg alt=\"inner\"\n"
        result <- layoutMini sharedFiguresStyle manuscript sharedFigureFiles
        case result of
          Left diagnostics -> assertBool (show diagnostics) (DiagnosticCode "G02118" `elem` map diagCode diagnostics)
          Right _ -> assertFailure "a figure inside a caption was accepted",
      testCase "root ADR 0377: HTML and EPUB retain nested figure numbers and captions" $
        withSystemTempDirectory "golem-nested-figure" $ \tmp -> do
          writeProject tmp (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n") sharedFiguresStyle sharedFigureSource sharedFigureFiles
          result <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub], optFonts = fakeProvider}
          map diagCode (filter isError (brDiagnostics result)) @?= []
          html <- TE.decodeUtf8 <$> BS.readFile (tmp </> "build/html/a.xhtml")
          archive <- toArchive <$> BL.readFile (tmp </> "build/epub/book.epub")
          epub <- maybe (assertFailure "missing EPUB chapter") (pure . TE.decodeUtf8 . BL.toStrict . fromEntry) (findEntryByPath "OEBPS/a.xhtml" archive)
          forM_ [html, epub] $ \document -> do
            T.count "<figure" document @?= 3
            forM_ ["Fig1", "Fig2", "Fig3", "caption one", "caption two", "caption three"] $ \text ->
              assertBool (T.unpack document) (text `T.isInfixOf` document)
    ]

sharedFigureFiles :: [(FilePath, BS.ByteString)]
sharedFigureFiles = [("images/shared.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\"/></svg>")]

sharedFiguresStyle :: BS.ByteString
sharedFiguresStyle = horizontalStyle <> "\n[figures]\nnumber = \"Fig{n}\"\n"

sharedFigureSource :: T.Text
sharedFigureSource = "- first\n\n  @figure images/shared.svg width=1zw alt=\"first\"\n    caption one\n\n+ second\n\n  @figure images/shared.svg width=1zw alt=\"second\"\n    caption two\n\n= term\n  @figure images/shared.svg width=1zw alt=\"third\"\n    caption three\n"

positionsOf :: T.Text -> T.Text -> [Int]
positionsOf needle = go 0
  where
    go offset sourceText = case T.breakOn needle sourceText of
      (_, rest) | T.null rest -> []
      (before, rest) -> let start = offset + BS.length (TE.encodeUtf8 before) in start : go (start + BS.length (TE.encodeUtf8 needle)) (T.drop (T.length needle) rest)
