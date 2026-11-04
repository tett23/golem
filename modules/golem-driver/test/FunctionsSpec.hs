-- | [functions] of manifest.toml and the handlers of the requirements (docs/adr/0149).
module FunctionsSpec (functionsTests) where

import Data.ByteString qualified as BS
import Data.List (isSuffixOf, sort)
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
import System.IO.Temp (withSystemTempDirectory)
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

-- | The codes of a project whose .gmx is the given and whose chapter is a.gm.
callingCodes :: Text -> Text -> IO [Text]
callingCodes gmx gm =
  withChapters "" [("a.gm", gm)] [("fn.gmx", gmx)] $ \tmp -> do
    TIO.appendFile (tmp </> "manifest.toml") "\n[functions]\nfiles = [\"fn.gmx\"]\n"
    projectCodes tmp

-- | The outputs of a copy of the fixture of functions built to HTML, EPUB and text.
buildFixture :: Bool -> IO ([Diagnostic], [(FilePath, BS.ByteString)])
buildFixture parallel = withSystemTempDirectory "golem-functions" $ \tmp -> do
  copyTree fixtureDir tmp
  r <- build (defaultOptions tmp) {optParallel = parallel, optTargets = Just [TargetHtml, TargetEpub, TargetText]}
  outs <- mapM (\p -> (drop (length tmp) p,) <$> BS.readFile p) (sort (brWritten r))
  pure (brDiagnostics r, outs)
  where
    fixtureDir = "test" </> "fixtures" </> "functions"

functionsTests :: TestTree
functionsTests =
  testGroup
    "[functions] (docs/adr/0149)"
    [ testCase "G03105: a function named as a built-in command" $
        callingCodes "pub inline strong :: Inlines -> Inlines;\nstrong s = s;\n" "一。\n" >>= (@?= ["G03105"]),
      testCase "G03107: two .gmx give the same command" $
        withChapters "" [("a.gm", "一。\n")] [("a.gmx", "pub inline taxIncluded :: Inlines;\ntaxIncluded = Inline.text \"\";\n"), ("b.gmx", "pub inline taxIncluded :: Inlines;\ntaxIncluded = Inline.text \"\";\n")] $ \tmp -> do
          TIO.appendFile (tmp </> "manifest.toml") "\n[functions]\nfiles = [\"a.gmx\", \"b.gmx\"]\n"
          projectCodes tmp >>= (@?= ["G03107"]),
      testCase "G03106: a function named as a command of a plugin" $
        withChapters "" [("a.gm", "一。\n")] [("lookup.gmx", "pub inline lookup :: Inlines;\nlookup = Inline.text \"\";\n")] $ \tmp -> do
          BS.readFile (".." </> ".." </> "plugins" </> "wasm" </> "lookup.wasm") >>= BS.writeFile (tmp </> "lookup.wasm")
          TIO.appendFile (tmp </> "manifest.toml") "\n[plugins.lookup]\npath = \"lookup.wasm\"\n\n[functions]\nfiles = [\"lookup.gmx\"]\n"
          projectCodes tmp >>= (@?= ["G03106"]),
      testCase "a type error of a .gmx gives no G02022 at the calls" $
        callingCodes "pub inline taxIncluded :: Nat -> Inlines;\ntaxIncluded n = n;\n" "[tax-included 1000]\n" >>= (@?= ["G10201"]),
      testCase "[tax-included 1000] in a chapter is the text the function makes" $
        withChapters "" [("a.gm", "[tax-included 1000]\n")] [("fn.gmx", "pub inline taxIncluded :: Nat -> Inlines;\ntaxIncluded n = Inline.text (String.fromNat (div (n * 11) 10));\n")] $ \tmp -> do
          TIO.appendFile (tmp </> "manifest.toml") "\n[functions]\nfiles = [\"fn.gmx\"]\n"
          r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
          map diagCode (brDiagnostics r) @?= []
          texts <- mapM BS.readFile (filter (".txt" `isSuffixOf`) (brWritten r))
          assertBool (show texts) (all ("1100" `BS.isInfixOf`) texts && not (null texts)),
      testCase "the fixture of functions builds twice to the same bytes and diagnostics, in parallel and in sequence" $ do
        a <- buildFixture False
        b <- buildFixture False
        c <- buildFixture True
        fst a @?= []
        assertBool "outputs" (not (null (snd a)))
        b @?= a
        c @?= a,
      testCase "=> file without requires is G10505, in a book that calls no function" $
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
