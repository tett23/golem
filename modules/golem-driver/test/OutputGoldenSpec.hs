{- | Goldens of whole PDF and EPUB outputs: several ADRs (0039, 0040,
0041, 0051) require the output of the existing fixtures to stay the same
bytes, and the determinism check of CI only compares two architectures of
one commit. The goldens are text dumps a reviewer can diff:

* PDF: the file as it is, with every Flate stream inflated; a stream that
  is not text (a font program, an image) is replaced by its length and
  SHA-256. Three values are normalised, because for these fixed inputs
  they change with VERSION and nothing else: the version in the Producer,
  the second element of the ID (the instance ID hashes the version) and
  the offset after startxref (the information dictionary, which holds the
  Producer, is the last object, so no offset in the xref table moves).
  The dates come from the manifest and are kept. The test checks the
  offsets of the xref table and of startxref against the bytes before it
  normalises them, and refuses a PDF with a .notdef glyph.
* EPUB: every entry of the zip, in the order of the archive, with its
  compression method, time and size, then its content; an entry that is
  not text is replaced by its length and SHA-256.

The compressed bytes themselves are not in the goldens: they come from
the bundled zlib at a fixed version (cabal.project), so the same inflated
content gives the same file.
-}
module OutputGoldenSpec (outputGoldenTests) where

import Codec.Archive.Zip (Archive (..), CompressionMethod (..), Entry (..), fromEntry, toArchive)
import Codec.Compression.Zlib qualified as Z
import Control.Monad (when)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Char (isDigit)
import Data.List (isSuffixOf)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Driver.Version (golemVersion)
import Golem.Pdf.Sha256 (sha256)
import Golem.Syntax
import Support
import System.Directory (copyFile, createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

outputGoldenTests :: TestTree
outputGoldenTests =
  testGroup
    "PDF and EPUB outputs against goldens"
    [ goldenVsString "pdf-sample.txt" "test/golden/pdf-sample.txt" (pdfDump <$> sampleOutput TargetPdf),
      goldenVsString "epub-sample.txt" "test/golden/epub-sample.txt" (epubDump <$> sampleOutput TargetEpub),
      goldenVsString "pdf-figures.txt" "test/golden/pdf-figures.txt" (pdfDump <$> figuresOutput TargetPdf),
      goldenVsString "epub-figures.txt" "test/golden/epub-figures.txt" (epubDump <$> figuresOutput TargetEpub)
    ]

{- | The fonts as fonts/ja.otf and fonts/latin.otf: Noto Serif JP of the
kanikosen fixture, which has every character of both fixtures (the
subset of Source Han Sans that scripts/determinism.sh uses lacks some,
such as 一 and …, which come out as .notdef), and Source Sans Pro of
golem-font.
-}
copyFonts :: FilePath -> IO ()
copyFonts tmp = do
  createDirectoryIfMissing True (tmp </> "fonts")
  copyFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "fonts/ja.otf")
  copyFile "../golem-font/test/fonts/SourceSansPro-Regular.otf" (tmp </> "fonts/latin.otf")

{- | The sample fixture to one target. The EPUB is built as it is. The PDF
takes the page of scripts/determinism/pdf-style.toml (B6, vertical), with
the fonts of 'copyFonts' for the roles body and code.
-}
sampleOutput :: Target -> IO BS.ByteString
sampleOutput target = withSystemTempDirectory "golem-golden" $ \tmp -> do
  copyTree fixture tmp
  when (target == TargetPdf) $ do
    copyFonts tmp
    style <- BS.readFile "../../scripts/determinism/pdf-style.toml"
    BS.writeFile (tmp </> "style.toml") (style <> "\n[fonts.code]\nja = \"fonts/ja.otf\"\nlatin = \"fonts/latin.otf\"\n")
  buildOne tmp target []

{- | The figures fixture (SVG, PDF and JPEG figures) to one target. The
JPEG, fitted to the line length, is too tall for the column and shrinks
(the notice G07039).
-}
figuresOutput :: Target -> IO BS.ByteString
figuresOutput target = withSystemTempDirectory "golem-golden" $ \tmp -> do
  copyTree "test/fixtures/figures" tmp
  copyFonts tmp
  buildOne tmp target ["G07039" | target == TargetPdf]

-- | Builds one target, with exactly the diagnostics given (by code).
buildOne :: FilePath -> Target -> [T.Text] -> IO BS.ByteString
buildOne tmp target codes = do
  r <- build (defaultOptions tmp) {optTargets = Just [target], optProfile = Dev}
  assertEqual "diagnostics" (map DiagnosticCode codes) (map diagCode (brDiagnostics r))
  case filter (\p -> any (`isSuffixOf` p) [".pdf", ".epub"]) (brWritten r) of
    [path] -> BS.readFile path
    other -> assertFailure (show other)

-- | Text: UTF-8 without control characters other than tabs and line ends.
isText :: BS.ByteString -> Bool
isText b = case TE.decodeUtf8' b of
  Left _ -> False
  Right t -> T.all (\c -> c >= ' ' && c /= '\DEL' || c `elem` ['\n', '\r', '\t']) t

-- | A non-text content as its length and SHA-256.
binary :: BS.ByteString -> B.Builder
binary b = "[binary: " <> B.intDec (BS.length b) <> " bytes, SHA-256 " <> mconcat (map B.word8HexFixed (BS.unpack (sha256 b))) <> "]"

-- | Text as it is, with a line end; anything else by 'binary'.
content :: BS.ByteString -> B.Builder
content b
  | isText b = B.byteString b <> (if "\n" `BS.isSuffixOf` b || BS.null b then "" else "\n")
  | otherwise = binary b <> "\n"

{- | The PDF dump of the module header. Fails the test when the xref
offsets or startxref do not point where they should.
-}
pdfDump :: BS.ByteString -> BL.ByteString
pdfDump pdf = B.toLazyByteString (normalise (checked (streams pdf)))
  where
    checked out
      | badOffsets pdf /= [] = error ("xref offsets point elsewhere: " <> show (badOffsets pdf))
      -- glyph 0 is .notdef: a golden with it would fix a missing character
      | "<0000> Tj" `BS.isInfixOf` BL.toStrict (B.toLazyByteString out) = error "a glyph is .notdef"
      | otherwise = out
    normalise =
      B.byteString
        . replaceAll (TE.encodeUtf8 ("Golem " <> golemVersion)) "Golem <VERSION>"
        . normaliseId
        . normaliseStartxref
        . BL.toStrict
        . B.toLazyByteString

-- | The PDF with each stream's data replaced by its inflated content.
streams :: BS.ByteString -> B.Builder
streams b = case BS.breakSubstring marker b of
  (before, rest)
    | BS.null rest -> B.byteString before
    | otherwise ->
        let dict = afterLast " obj\n" before
            len = streamLength dict
            body = BS.take len (BS.drop (BS.length marker) rest)
            rest' = BS.drop (BS.length marker + len) rest
            decoded = if "/Filter /FlateDecode" `BS.isInfixOf` dict then BL.toStrict (Z.decompress (BL.fromStrict body)) else body
         in B.byteString before <> marker' <> content decoded <> streams (dropLineEnd rest')
  where
    marker = ">>\nstream\n"
    marker' = B.byteString marker
    dropLineEnd a = if "\n" `BS.isPrefixOf` a then BS.drop 1 a else a

-- | The /Length of a stream dictionary (always direct in Golem's output).
streamLength :: BS.ByteString -> Int
streamLength dict = case BS.breakSubstring " /Length " dict of
  (_, rest) | not (BS.null rest) -> maybe (error "no length") fst (BC.readInt (BS.drop 9 rest))
  _ -> error ("no /Length in " <> show dict)

{- | The entries of the xref table and startxref that do not point at their
object, and the size of the table against the trailer's /Size.
-}
badOffsets :: BS.ByteString -> [String]
badOffsets pdf =
  let startxref = fst <$> BC.readInt (afterLast "\nstartxref\n" pdf)
      table = maybe [] (\o -> BC.lines (BS.drop o pdf)) startxref
      -- xref, "0 size", the free entry 0, then the objects from 1
      entries = [(n, o) | (n, l) <- zip [1 :: Int ..] (takeWhile (/= "trailer") (drop 3 table)), Just (o, _) <- [BC.readInt l]]
      size = case table of
        (_ : l : _) -> fst <$> BC.readInt (BS.drop 2 l)
        _ -> Nothing
      objectAt n o = (BC.pack (show n) <> " 0 obj\n") `BS.isPrefixOf` BS.drop o pdf
   in ["startxref" | take 1 table /= ["xref"]]
        <> ["object " <> show n | (n, o) <- entries, not (objectAt n o)]
        <> ["the table has " <> show (length entries) <> " objects, not " <> show size | size /= Just (length entries + 1)]

-- | What follows the last occurrence of the needle; all of it without one.
afterLast :: BS.ByteString -> BS.ByteString -> BS.ByteString
afterLast needle hay = case BS.breakSubstring needle hay of
  (_, rest)
    | BS.null rest -> hay
    | otherwise -> afterLast needle (BS.drop (BS.length needle) rest)

replaceAll :: BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString
replaceAll from to hay = case BS.breakSubstring from hay of
  (before, rest)
    | BS.null rest -> before
    | otherwise -> before <> to <> replaceAll from to (BS.drop (BS.length from) rest)

-- | /ID [<document> <instance>]: the instance ID hashes the version.
normaliseId :: BS.ByteString -> BS.ByteString
normaliseId b = case BS.breakSubstring "/ID [<" b of
  (before, rest)
    | BS.null rest -> error "no /ID in the trailer"
    | otherwise ->
        let (first, afterFirst) = BS.breakSubstring "> <" rest
            (_, afterSecond) = BS.breakSubstring ">]" (BS.drop 3 afterFirst)
         in before <> first <> "> <INSTANCE-ID" <> afterSecond

normaliseStartxref :: BS.ByteString -> BS.ByteString
normaliseStartxref b = case BS.breakSubstring "\nstartxref\n" b of
  (before, rest)
    | BS.null rest -> error "no startxref"
    | otherwise -> before <> "\nstartxref\n<STARTXREF>" <> BS.dropWhile isDigitW (BS.drop (BS.length "\nstartxref\n") rest)
  where
    isDigitW = isDigit . toEnum . fromIntegral

-- | Every entry of the EPUB, in the order of the archive.
epubDump :: BS.ByteString -> BL.ByteString
epubDump epub =
  B.toLazyByteString
    ( mconcat
        [ "== "
            <> B.string8 (eRelativePath e)
            <> " ("
            <> (if eCompressionMethod e == Deflate then "deflate" else "stored")
            <> ", time "
            <> B.integerDec (eLastModified e)
            <> ", "
            <> B.intDec (fromIntegral (eUncompressedSize e))
            <> " bytes)\n"
            <> content (BL.toStrict (fromEntry e))
        | e <- zEntries (toArchive (BL.fromStrict epub))
        ]
    )
