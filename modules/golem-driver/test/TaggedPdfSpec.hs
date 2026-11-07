{- | Tagged PDF, and PDF/A-2a and PDF/UA-1 for the books that declare them
(docs/adr ADR 0183): the checks of a declared book, and the catalog and
XMP of the PDF.
-}
module TaggedPdfSpec (taggedPdfTests) where

import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A manifest with [targets.pdf] of the keys given, and HTML and plain text.
declaredManifest :: T.Text -> T.Text -> T.Text
declaredManifest language keys = manifestToml testManifest {tmLanguage = language, tmTargets = ["html", "text"]} <> "\n[targets.pdf]\n" <> keys

-- | The style with an output intent, and its profile.
intentStyle :: BS.ByteString
intentStyle = horizontalStyle <> "\n[color]\nintent = \"x.icc\"\n"

intentFiles :: [(FilePath, BS.ByteString)]
intentFiles = [("x.icc", "fake profile")]

-- | What a build of a one-chapter project wrote, and its diagnostics.
data Declared = Declared
  { dDiagnostics :: [Diagnostic],
    dWritten :: [FilePath],
    dManifest :: T.Text
  }

buildDeclared :: Profile -> T.Text -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO Declared
buildDeclared profile manifest style source files = withSystemTempDirectory "golem-tagged" $ \tmp -> do
  writeProject tmp (TE.encodeUtf8 manifest) style source files
  r <- build (defaultOptions tmp) {optFonts = fakeProvider, optProfile = profile}
  pure (Declared (brDiagnostics r) [drop (length tmp + 1) p | p <- brWritten r] manifest)

errorsOf :: Declared -> [T.Text]
errorsOf = codesOf . filter isError . dDiagnostics

hasPdf :: Declared -> Bool
hasPdf = any (".pdf" `isSuffixOf`) . dWritten

-- | The byte offset of the first occurrence of a text in another.
offsetOf :: T.Text -> T.Text -> Int
offsetOf needle hay = BS.length (TE.encodeUtf8 (fst (T.breakOn needle hay)))

taggedPdfTests :: TestTree
taggedPdfTests =
  testGroup
    "tagged PDF, PDF/A-2a and PDF/UA-1 (docs/adr ADR 0183)"
    [ testCase "pdfa = \"2a\" without [color] intent is G03113 at the value, with no PDF but HTML and plain text, in dev and prod" $
        mapM_
          ( \profile -> do
              d <- buildDeclared profile (declaredManifest "ja" "pdfa = \"2a\"\n") horizontalStyle "本文。\n" []
              errorsOf d @?= ["G03113"]
              [(diagMessage x, spanStart (diagSpan x)) | x <- dDiagnostics d, diagCode x == DiagnosticCode "G03113"]
                @?= [("PDF/A には [color] の intent が要ります", offsetOf "\"2a\"" (dManifest d))]
              hasPdf d @?= False
              assertBool (show (dWritten d)) (any (".xhtml" `isSuffixOf`) (dWritten d))
              assertBool (show (dWritten d)) (any (".txt" `isSuffixOf`) (dWritten d))
          )
          [Dev, Prod],
      testCase "pdfua = \"1\" alone needs no output intent" $ do
        d <- buildDeclared Dev (declaredManifest "ja" "pdfua = \"1\"\n") horizontalStyle "本文。\n" []
        errorsOf d @?= []
        hasPdf d @?= True,
      testCase "a language not of the form of a tag is G03119 at the value with pdfua, and with pdfa" $ do
        d <- buildDeclared Dev (declaredManifest "日本 語!" "pdfua = \"1\"\n") horizontalStyle "本文。\n" []
        errorsOf d @?= ["G03119"]
        [(diagMessage x, spanStart (diagSpan x)) | x <- dDiagnostics d, diagCode x == DiagnosticCode "G03119"]
          @?= [("PDF/A と PDF/UA には、language を言語のタグの形で書きます: 日本 語!", offsetOf "\"日本 語!\"" (dManifest d))]
        hasPdf d @?= False
        e <- buildDeclared Dev (declaredManifest "日本 語!" "pdfa = \"2a\"\n") intentStyle "本文。\n" intentFiles
        errorsOf e @?= ["G03119"],
      testCase "without pdfa and pdfua a language of any form is no error" $ do
        d <- buildDeclared Dev (declaredManifest "日本 語!" "") horizontalStyle "# 一\n\n### 二\n" []
        errorsOf d @?= []
        hasPdf d @?= True,
      testCase "with pdfua a heading two levels deeper, and a first heading not of level 1, are G07103 at the heading" $ do
        let source = "# 一\n\n本文。\n\n### 三\n"
        d <- buildDeclared Dev (declaredManifest "ja" "pdfua = \"1\"\n") horizontalStyle source []
        errorsOf d @?= ["G07103"]
        [(diagMessage x, spanStart (diagSpan x)) | x <- dDiagnostics d, diagCode x == DiagnosticCode "G07103"]
          @?= [("PDF/UA では見出しの段を飛ばせません: 1 から 3", offsetOf "### 三" source)]
        hasPdf d @?= False
        e <- buildDeclared Dev (declaredManifest "ja" "pdfua = \"1\"\n") horizontalStyle "## 二\n" []
        [(diagMessage x, spanStart (diagSpan x)) | x <- dDiagnostics e, diagCode x == DiagnosticCode "G07103"]
          @?= [("PDF/UA では見出しの段を飛ばせません: 0 から 2", 0)],
      testCase "with pdfua a heading may go back any number of levels" $ do
        d <- buildDeclared Dev (declaredManifest "ja" "pdfua = \"1\"\n") horizontalStyle "# 一\n\n## 二\n\n### 三\n\n# 四\n" []
        errorsOf d @?= [],
      testCase "with pdfa a character of the private use area is G07104 at its text" $ do
        let source = "本文\xE000。\n"
        d <- buildDeclared Dev (declaredManifest "ja" "pdfa = \"2a\"\n") intentStyle source intentFiles
        errorsOf d @?= ["G07104"]
        [(diagMessage x, spanFile (diagSpan x) /= FileId 0) | x <- dDiagnostics d, diagCode x == DiagnosticCode "G07104"]
          @?= [("PDF/A-2a の PDF に私用領域の字は書けません: U+E000", True)]
        hasPdf d @?= False
        e <- buildDeclared Dev (declaredManifest "ja" "pdfua = \"1\"\n") horizontalStyle source []
        errorsOf e @?= [],
      testCase "pdfa and an output intent: golem preflight finds nothing against PDF/X-4" $
        withSystemTempDirectory "golem-tagged" $ \tmp -> do
          writeProject tmp (TE.encodeUtf8 (declaredManifest "ja" "pdfa = \"2a\"\npdfua = \"1\"\n")) intentStyle "# 一\n\n本文。\n" intentFiles
          p <- preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider}
          [c | c <- codesOf (prDiagnostics p), c == "G09014"] @?= []
    ]
