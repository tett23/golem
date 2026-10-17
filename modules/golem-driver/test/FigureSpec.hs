-- | PDF figures and figures that cannot be placed (golem-pdf ADR 0008).
module FigureSpec (pdfFigureTests) where

import Control.Monad (forM_)
import Data.Bits (shiftR)
import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Driver.Pdf (PlacedFigure (..))
import Golem.Pdf (FigureContent (..), ImportedPage (..))
import Golem.Syntax
import Support
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A PDF that Golem built: one A5 page.
golemPdf :: IO BS.ByteString
golemPdf = miniPdf fakeProvider False horizontalStyle "図の本文。\n" []

-- | A PNG of one pixel, interlaced or not (readImage refuses interlaced PNGs).
png :: Bool -> BS.ByteString
png interlaced =
  BS.pack [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    <> chunk "IHDR" (be32 1 <> be32 1 <> BS.pack [8, 0, 0, 0, if interlaced then 1 else 0])
    <> chunk "IDAT" (BS.pack [0x78, 0x9C, 0x63, 0x60, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01])
    <> chunk "IEND" ""
  where
    be32 :: Int -> BS.ByteString
    be32 n = BS.pack [fromIntegral (n `shiftR` s) | s <- [24, 16, 8, 0 :: Int]]
    chunk name d = be32 (BS.length d) <> name <> d <> be32 0

-- | A build of the one-chapter project to the targets, in a profile: the error codes and whether a PDF was written.
buildIn :: Profile -> [Target] -> T.Text -> [(FilePath, BS.ByteString)] -> IO ([DiagnosticCode], Bool)
buildIn profile targets source files = withSystemTempDirectory "golem-figure" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n")
  BS.writeFile (tmp </> "style.toml") (withBodyFont (figStyle horizontalStyle))
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ (bodyFontFiles horizontalStyle <> files) $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  r <- build (defaultOptions tmp) {optTargets = Just targets, optFonts = fakeProvider, optProfile = profile}
  pdf <- doesFileExist (tmp </> "build/a.pdf")
  pure (map diagCode (filter isError (brDiagnostics r)), pdf || any (".pdf" `isSuffixOf`) (brWritten r))

count :: BS.ByteString -> BS.ByteString -> Int
count needle hay = case BS.breakSubstring needle hay of
  (_, rest) | BS.null rest -> 0
  (_, rest) -> 1 + count needle (BS.drop (BS.length needle) rest)

pdfFigureTests :: [TestTree]
pdfFigureTests =
  [ testCase "a PDF figure fills the measure, its height in the proportion of its crop box" $ do
      fig <- golemPdf
      (_, pl) <- layoutOk horizontal24 "@figure images/f.pdf web=images/f.png alt=\"t\"\n  キャプション。\n" [("images/f.pdf", fig), ("images/f.png", png False)]
      (_, pf, _, _) <- theFigure pl
      case pfContent pf of
        VectorFigure ip -> do
          let (w, h) = ipSize ip
          pfAlong pf @?= 240 * pt
          pfAcross pf @?= floor (fromInteger (240 * pt) * h / w)
        other -> assertFailure (show other),
    testCase "the book's PDF has one Form XObject for a PDF figure placed twice" $ do
      fig <- golemPdf
      let one = "@figure images/f.pdf web=images/f.png alt=\"t\"\n  キャプション。\n\n"
      pdf <- miniPdf fakeProvider False (figStyle horizontalStyle) (one <> "本文。\n\n" <> one) [("images/f.pdf", fig), ("images/f.png", png False)]
      count "/Subtype /Form" pdf @?= 1,
    testCase "a broken PNG and an interlaced PNG are G0810, and no PDF is written, in dev and prod" $
      forM_ [Dev, Prod] $ \profile -> do
        let src = "@figure images/a.png alt=\"t\"\n\n@figure images/b.png alt=\"t\"\n"
        (codes, written) <- buildIn profile [TargetPdf] src [("images/a.png", BS.take 20 (png False)), ("images/b.png", png True)]
        codes @?= [DiagnosticCode "G0810", DiagnosticCode "G0810"]
        written @?= False,
    testCase "the message of G0810 has the path and the reason" $ withSystemTempDirectory "golem-figure" $ \tmp -> do
      BS.writeFile (tmp </> "manifest.toml") miniManifest
      BS.writeFile (tmp </> "style.toml") (withBodyFont (figStyle horizontalStyle))
      BS.writeFile (tmp </> "a.gm") "@figure images/b.png alt=\"t\"\n"
      forM_ (bodyFontFiles horizontalStyle <> [("images/b.png", png True)]) $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
      r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
      map diagMessage (filter isError (brDiagnostics r)) @?= ["図版を PDF に置けません: images/b.png（インターレースの PNG は使えません）"],
    testCase "an encrypted PDF figure is G0810" $ do
      fig <- golemPdf
      let (before, after) = BS.breakSubstring "trailer\n<<" fig
          encrypted = before <> "trailer\n<< /Encrypt 1 0 R" <> BS.drop 10 after
      (codes, written) <- buildIn Dev [TargetPdf] "@figure images/f.pdf web=images/f.png alt=\"t\"\n" [("images/f.pdf", encrypted), ("images/f.png", png False)]
      codes @?= [DiagnosticCode "G0810"]
      written @?= False,
    testCase "HTML does not read the images: a broken PNG is not G0810" $ do
      (codes, _) <- buildIn Dev [TargetHtml] "@figure images/a.png alt=\"t\"\n" [("images/a.png", BS.take 20 (png False))]
      codes @?= []
  ]
