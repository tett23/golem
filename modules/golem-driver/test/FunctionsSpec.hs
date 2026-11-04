-- | [functions] of manifest.toml and the handlers of the requirements (docs/adr/0149).
module FunctionsSpec (functionsTests) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Driver.Functions
import Golem.Eval.Value (Value (..))
import Golem.Project (ProjectFailure (..))
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO (IOMode (..), hSetFileSize, withFile)
import Test.Tasty
import Test.Tasty.HUnit

-- | A project of one chapter that calls no function, with [functions] and more files.
withFunctions :: Text -> [(FilePath, Text)] -> (FilePath -> IO a) -> IO a
withFunctions table files k =
  withChapters "" [("a.gm", "一。\n")] files $ \tmp -> do
    TIO.appendFile (tmp </> "manifest.toml") ("\n" <> table)
    k tmp

-- | The codes of the evaluation of the project, or of its failure.
projectCodes :: FilePath -> IO [Text]
projectCodes tmp =
  evaluateProject Dev tmp >>= \case
    Left f -> pure [c | DiagnosticCode c <- map diagCode (pfDiagnostics f)]
    Right e -> pure [c | DiagnosticCode c <- map diagCode (evDiagnostics e)]

readFile' :: Text
readFile' = "pub f :: String -> String => file;\nf n = File.read n;\n"

callRead :: FilePath -> Text -> IO (Either Diagnostic Result)
callRead tmp name = do
  lf <- loadFunctionsAt tmp
  case lfProgramCall lf of
    Nothing -> assertFailure (show (lfDiagnostics lf)) >> fail "unreachable"
    Just callIt -> pure (callIt (mkSpan (FileId 0) 0 0) "fn.gmx" "f" [RPrim (VString name)])

functionsTests :: TestTree
functionsTests =
  testGroup
    "[functions] (docs/adr/0149)"
    [ testCase "=> file without requires is G10505, in a book that calls no function" $
        withFunctions "[functions]\nfiles = [\"fn.gmx\"]\n" [("fn.gmx", readFile')] $ \tmp ->
          projectCodes tmp >>= (@?= ["G10505"]),
      testCase "requires = [\"net\"] is G03101" $
        withFunctions "[functions]\nrequires = [\"net\"]\n" [] $ \tmp ->
          projectCodes tmp >>= (@?= ["G03101"]),
      testCase "a missing file of [functions.data] is G03102, in a book that calls no function" $
        withFunctions "[functions]\nrequires = [\"file\"]\n\n[functions.data]\nwords = \"data/words.tsv\"\n" [] $ \tmp ->
          projectCodes tmp >>= (@?= ["G03102"]),
      testCase "a missing file of files is G03102" $
        withFunctions "[functions]\nfiles = [\"nope.gmx\"]\n" [] $ \tmp ->
          projectCodes tmp >>= (@?= ["G03102"]),
      testCase "a path outside the root is G03003" $
        withFunctions "[functions]\nrequires = [\"file\"]\n\n[functions.data]\nwords = \"../words.tsv\"\n" [] $ \tmp ->
          projectCodes tmp >>= (@?= ["G03003"]),
      testCase "data over the limit together is G03103" $
        withFunctions "[functions]\nrequires = [\"file\"]\n\n[functions.data]\nbig = \"big.tsv\"\n" [] $ \tmp -> do
          withFile (tmp </> "big.tsv") WriteMode (\h -> hSetFileSize h (64 * 1024 * 1024 + 1))
          projectCodes tmp >>= (@?= ["G03103"]),
      testCase "[functions.data] without file in requires is G03104" $
        withFunctions "[functions]\n\n[functions.data]\nwords = \"words.tsv\"\n" [("words.tsv", "a\n")] $ \tmp ->
          projectCodes tmp >>= (@?= ["G03104"]),
      testCase "an error of a .gmx is reported at the .gmx" $
        withFunctions "[functions]\nfiles = [\"fn.gmx\"]\n" [("fn.gmx", "f :: Nat;\nf = \"a\";\n")] $ \tmp ->
          projectCodes tmp >>= (@?= ["G10201"]),
      testCase "File.read of a name not in [functions.data] is G10503" $
        withFunctions "[functions]\nfiles = [\"fn.gmx\"]\nrequires = [\"file\"]\n" [("fn.gmx", readFile')] $ \tmp -> do
          r <- callRead tmp "missing"
          either (Just . diagCode) (const Nothing) r @?= Just (DiagnosticCode "G10503"),
      testCase "a file that is no UTF-8 is G10504" $
        withFunctions "[functions]\nfiles = [\"fn.gmx\"]\nrequires = [\"file\"]\n\n[functions.data]\nbad = \"bad.tsv\"\n" [("fn.gmx", readFile')] $ \tmp -> do
          BS.writeFile (tmp </> "bad.tsv") "a\xff\n"
          r <- callRead tmp "bad"
          either (Just . diagCode) (const Nothing) r @?= Just (DiagnosticCode "G10504"),
      testCase "a file with a BOM and CRLF is read" $
        withFunctions "[functions]\nfiles = [\"fn.gmx\"]\nrequires = [\"file\"]\n\n[functions.data]\nwords = \"words.tsv\"\n" [("fn.gmx", readFile')] $ \tmp -> do
          BS.writeFile (tmp </> "words.tsv") "\xEF\xBB\xBF\&a\tb\r\nc\td\r\n"
          r <- callRead tmp "words"
          r @?= Right (RPrim (VString "a\tb\nc\td\n")),
      testCase "two reads of the same data have the same value, though the file changes between them" $
        withFunctions "[functions]\nfiles = [\"fn.gmx\"]\nrequires = [\"file\"]\n\n[functions.data]\nwords = \"words.tsv\"\n" [("fn.gmx", readFile'), ("words.tsv", "one\n")] $ \tmp -> do
          lf <- loadFunctionsAt tmp
          case lfProgramCall lf of
            Nothing -> assertFailure (show (lfDiagnostics lf))
            Just callIt -> do
              let at = mkSpan (FileId 0) 0 0
                  r1 = callIt at "fn.gmx" "f" [RPrim (VString "words")]
              _ <- either (assertFailure . show) pure r1
              TIO.writeFile (tmp </> "words.tsv") "two\n"
              callIt at "fn.gmx" "f" [RPrim (VString "words")] @?= r1
              r1 @?= Right (RPrim (VString "one\n"))
    ]
