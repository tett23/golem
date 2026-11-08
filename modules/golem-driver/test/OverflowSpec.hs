{- | Lines that stick out past their measure (docs/adr ADR 0210): G07105
of golem build, one for each line drawn whose 'lineOverflow' is positive,
at the first character of the first box that crosses the measure, and
G09013 of golem preflight beside it, at the same place, with the same
message and facts. The lines past the measure are of code of a long
identifier: code of Japanese text breaks between its characters since
golem-layout ADR 0034.
-}
module OverflowSpec (overflowTests) where

import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Driver.Version (golemVersion)
import Golem.Layout.KnuthPlass (lineOverflow)
import Golem.Length (Sp, mmCeilText)
import Golem.Pdf.Sha256 (sha256)
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

overflowTests :: TestTree
overflowTests =
  testGroup
    "lines past the measure (docs/adr ADR 0210)"
    [ testCase "O5: horizontal, code of a long identifier past the measure: one G07105 at its first character, the overflow rounded up" $ do
        let source = "[code: " <> T.replicate 40 "a" <> "]\n"
        (r, _) <- built horizontalStyle source False
        amounts <- overflowsOf horizontalStyle source
        assertBool "the layout has an overfull line" (not (null amounts))
        [(c, sev, f, s, l) | (c, sev, f, s, l, _) <- g07105 r] @?= [("G07105", Warning, "a.gm", 7, 0)]
        [m | (_, _, _, _, _, m) <- g07105 r] @?= ["行が行長から " <> mmCeilText a <> " はみ出しています（PDF の 1 ページ目）" | a <- amounts]
        [diagFacts d | d <- diagnosticsOf "G07105" (brDiagnostics r)]
          @?= [[("overfull", FactText (mmCeilText a)), ("pdf-pages", FactInts [1])] | a <- amounts]
        assertBool "the PDF is written" (any (".pdf" `isSuffixOf`) (brWritten r)),
      testCase "O5: vertical, the same in a B6 line of 42 characters" $ do
        let source = "[code: " <> T.replicate 120 "a" <> "]\n"
        (r, _) <- built pdfStyle source False
        amounts <- overflowsOf pdfStyle source
        [(c, sev, f, s, l) | (c, sev, f, s, l, _) <- g07105 r] @?= [("G07105", Warning, "a.gm", 7, 0)]
        [m | (_, _, _, _, _, m) <- g07105 r] @?= ["行が行長から " <> mmCeilText a <> " はみ出しています（PDF の 1 ページ目）" | a <- amounts],
      testCase "O5: code that fits the measure exactly gives no G07105" $ do
        let source = "[code: " <> T.replicate fitting "a" <> "]\n"
        amounts <- overflowsOf horizontalStyle source
        amounts @?= []
        (r, _) <- built horizontalStyle source False
        g07105 r @?= []
        -- one more character is past the measure
        over <- overflowsOf horizontalStyle ("[code: " <> T.replicate (fitting + 1) "a" <> "]\n")
        length over @?= 1,
      testCase "O5: two paragraphs with such code give two G07105" $ do
        let para = "[code: " <> T.replicate 40 "a" <> "]\n"
            source = para <> "\n" <> para
        (r, _) <- built horizontalStyle source False
        [s | (_, _, _, s, _, _) <- g07105 r] @?= [7, byteLength (para <> "\n") + 7],
      testCase "O5: such code in the body of a note: one G07105 at the code in the note" $ do
        let source = "本文[note: [code: " <> T.replicate 40 "a" <> "]]。\n"
        (r, _) <- built horizontalStyle source False
        [(f, s) | (_, _, f, s, _, _) <- g07105 r] @?= [("a.gm", byteLength "本文[note: [code: ")],
      -- the ADR asks for one G07105 in a cell too; a cell cannot be narrower than what it cannot break, so the table stops at G07041 instead
      testCase "O5: such code in a cell of a table is wider than the table may be: G07041, and no G07105" $ do
        let source = "| a |\n|:---|\n| [code: " <> T.replicate 40 "a" <> "] |\n"
        (r, _) <- built horizontalStyle source False
        codesOf (filter isError (brDiagnostics r)) @?= ["G07041"]
        g07105 r @?= [],
      testCase "O5: the number of a heading, which the source does not have, past the measure: G07105 at the heading" $ do
        let style = horizontalStyle <> "\n[headings.1]\nnumber = \"" <> BC.replicate 30 '0' <> "{n}\"\n"
        (r, _) <- built style "# 見出し\n\n本文。\n" False
        [(f, s) | (_, _, f, s, _, _) <- g07105 r] @?= [("a.gm", 0)],
      testCase "O6: the same diagnostics in the same order with and without optParallel" $ do
        let style = horizontalStyle <> "\n[headings.1]\nnumber = \"" <> BC.replicate 30 '0' <> "{n}\"\n"
            source = "# 見出し\n\n[code: " <> T.replicate 40 "a" <> "]\n\n本文[note: [code: " <> T.replicate 40 "b" <> "]]。\n\n[code: " <> T.replicate 60 "c" <> "]\n"
        (serial, _) <- built style source False
        (parallel, _) <- built style source True
        length (g07105 serial) @?= 4
        brDiagnostics parallel @?= brDiagnostics serial,
      testCase "O7: the PDF of a book with an overfull line is the bytes it was before G07105" $ do
        let source = "[code: " <> T.replicate 40 "a" <> "]\n"
        (_, pdf) <- built horizontalStyle source False
        fmap (hex . sha256 . normalised) pdf @?= Just overfullPdfDigest,
      testCase "O8: golem preflight gives G07105 and G09013 for the line, at the same place, with the same message and facts" $ do
        let source = "[code: " <> T.replicate 40 "a" <> "]\n"
        ds <- preflighted [] source
        let of' c = [(diagSpan d, diagMessage d, diagFacts d) | d <- ds, diagCode d == DiagnosticCode c]
        length (of' "G07105") @?= 1
        of' "G09013" @?= of' "G07105"
        [diagSeverity d | d <- ds, diagCode d == DiagnosticCode "G07105"] @?= [Warning],
      testCase "O8: with overfull-lines off, golem preflight gives G07105 alone" $ do
        let source = "[code: " <> T.replicate 40 "a" <> "]\n"
        ds <- preflighted [("preflight.toml", "[overfull-lines]\nseverity = \"off\"\n")] source
        [c | d <- ds, let { DiagnosticCode c = diagCode d }, c `elem` ["G07105", "G09013"]] @?= ["G07105"]
    ]
  where
    -- the number of characters of 'a' in code that fill the line of 'horizontalStyle'
    fitting = 23

-- | Builds the one-chapter project to PDF with the fake fonts: the result and the PDF.
built :: BS.ByteString -> T.Text -> Bool -> IO (BuildResult, Maybe BS.ByteString)
built style source parallel = withSystemTempDirectory "golem-overflow" $ \tmp -> do
  writeProject tmp miniManifest style source []
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optParallel = parallel}
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> Just <$> BS.readFile p
    _ -> pure Nothing
  pure (r, pdf)

-- | golem preflight of the one-chapter project with the fake fonts, with more files.
preflighted :: [(FilePath, BS.ByteString)] -> T.Text -> IO [Diagnostic]
preflighted files source = withSystemTempDirectory "golem-overflow" $ \tmp -> do
  writeProject tmp miniManifest horizontalStyle source []
  writeFiles tmp files
  prDiagnostics <$> preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider}

-- | The overflow of each overfull line of the body, from the layout.
overflowsOf :: BS.ByteString -> T.Text -> IO [Sp]
overflowsOf style source = do
  (_, pl) <- layoutOk style source []
  pure [a | sl <- Map.elems (plLines pl), let a = lineOverflow (slLine sl), a > 0]

-- | G07105 as code, severity, file, start, length and message.
g07105 :: BuildResult -> [(T.Text, Severity, FilePath, Int, Int, T.Text)]
g07105 r =
  [ (c, diagSeverity d, maybe "" siPath (Map.lookup (spanFile sp) (brSources r)), spanStart sp, spanLength sp, diagMessage d)
  | d <- diagnosticsOf "G07105" (brDiagnostics r),
    let DiagnosticCode c = diagCode d
        sp = diagSpan d
  ]

byteLength :: T.Text -> Int
byteLength = BS.length . TE.encodeUtf8

-- | The PDF without its instance ID and with the version of its Producer written as VERSION.
normalised :: BS.ByteString -> BS.ByteString
normalised pdf =
  let (before, rest) = BS.breakSubstring "/ID [" pdf
      b = before <> BS.drop 1 (BC.dropWhile (/= ']') rest)
      v = TE.encodeUtf8 golemVersion
      go s = case BS.breakSubstring v s of
        (before, rest)
          | BS.null rest -> before
          | otherwise -> before <> "VERSION" <> go (BS.drop (BS.length v) rest)
   in go b

hex :: BS.ByteString -> T.Text
hex = T.pack . concatMap (\w -> [digits !! fromIntegral (w `div` 16), digits !! fromIntegral (w `mod` 16)]) . BS.unpack
  where
    digits = "0123456789abcdef"

{- | The SHA-256 of 'normalised' of the PDF of the overfull book. The book
of Japanese code of docs/adr ADR 0210 breaks since golem-layout ADR 0034;
this is the digest of the book of a long identifier from the build before
golem-layout ADR 0034, which the build after it gives too.
-}
overfullPdfDigest :: T.Text
overfullPdfDigest = "3a869f3af3cba2e9f7af3b503b98adee74c8796ad7a729fd1f16267d689ea480"
