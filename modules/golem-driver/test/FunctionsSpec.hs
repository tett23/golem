-- | [functions.requires] of manifest.toml and the handler of file (docs/adr/0161).
module FunctionsSpec (functionsTests) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (evaluate)
import Control.Monad (forM)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Driver.Functions
import Golem.Emet (Result (..), callFunction)
import Golem.Eval.Value (Value (..))
import Golem.Project (Project (..), ProjectFailure (..), loadProjectWith)
import Golem.Syntax
import Support
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO (IOMode (..), hSetFileSize, withFile)
import Test.Tasty
import Test.Tasty.HUnit

-- | A project of one chapter that calls no function, with a table after the manifest and more files.
withFunctions :: Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withFunctions table files k =
  withChapters "" [("a.gm", "一。\n")] [] $ \tmp -> do
    TIO.appendFile (tmp </> "manifest.toml") ("\n" <> table)
    mapM_ (\(p, b) -> createDirectoryIfMissing True (takeDirectory (tmp </> p)) >> BS.writeFile (tmp </> p) b) files
    k tmp

-- | The codes of the evaluation of the project, or of its failure, but the notice of no style.toml.
projectCodes :: FilePath -> IO [Text]
projectCodes tmp = do
  ds <-
    evaluateProject Dev tmp >>= \case
      Left f -> pure (pfDiagnostics f)
      Right e -> pure (evDiagnostics e)
  pure [c | d <- ds, let DiagnosticCode c = diagCode d, c /= "G03023"]

-- | The files of [functions.requires] of the project, read.
required :: FilePath -> IO RequiredFiles
required tmp =
  loadProjectWith Map.empty tmp >>= \case
    Left f -> assertFailure (show (pfDiagnostics f)) >> fail "unreachable"
    Right p -> loadRequiredFiles tmp Map.empty (projectManifestFile p) (projectManifest p)

-- | The functions of these .emet, with the requirements checked against the manifest.
functionsOf :: FilePath -> [FilePath] -> IO LoadedFunctions
functionsOf tmp roots =
  loadProjectWith Map.empty tmp >>= \case
    Left f -> assertFailure (show (pfDiagnostics f)) >> fail "unreachable"
    Right p -> loadFunctions tmp Map.empty (FileId 1000000) (projectManifest p) roots

codesOf :: [Diagnostic] -> [Text]
codesOf ds = [c | d <- ds, let DiagnosticCode c = diagCode d]

readA :: BS.ByteString
readA = "pub f :: Nat -> <file \"data/a.tsv\"> String\nf _ = File.read \"data/a.tsv\"\n"

functionsTests :: TestTree
functionsTests =
  testGroup
    "[functions.requires] and the handler of file (docs/adr/0161)"
    [ testCase "a requirement of a signature not in [functions.requires] is E05104, with the line to add" $
        withFunctions "" [("fn.emet", readA)] $ \tmp -> do
          lf <- functionsOf tmp ["fn.emet"]
          codesOf (lfDiagnostics lf) @?= ["E05104"]
          let msg = T.concat (map diagMessage (lfDiagnostics lf))
          assertBool (T.unpack msg) ("file = [\"data/a.tsv\"]" `T.isInfixOf` msg)
          map (spanStart . diagSpan) (lfDiagnostics lf) @?= [T.length (fst (T.breakOn "file" (T.pack "pub f :: Nat -> <file \"data/a.tsv\"> String")))],
      testCase "a requirement of an imported .emet is checked too, and the line names the key" $
        withFunctions "[functions.requires]\nfile = [\"data/b.tsv\"]\n" [("fn.emet", "import \"lib/a.emet\"\ng :: Nat\ng = 1\n"), ("lib/a.emet", readA), ("data/b.tsv", "b\n")] $ \tmp -> do
          lf <- functionsOf tmp ["fn.emet"]
          codesOf (lfDiagnostics lf) @?= ["E05104"]
          let msg = T.concat (map diagMessage (lfDiagnostics lf))
          assertBool (T.unpack msg) ("file に \"data/a.tsv\" を足します" `T.isInfixOf` msg),
      testCase "a requirement in [functions.requires] is no error" $
        withFunctions "[functions.requires]\nfile = [\"data/./a.tsv\"]\n" [("fn.emet", readA), ("data/a.tsv", "a\n")] $ \tmp -> do
          lf <- functionsOf tmp ["fn.emet"]
          codesOf (lfDiagnostics lf) @?= [],
      testCase "a path of a signature that differs only in case from the manifest's is G03004" $
        withFunctions "[functions.requires]\nfile = [\"data/A.tsv\"]\n" [("fn.emet", readA), ("data/A.tsv", "a\n")] $ \tmp -> do
          lf <- functionsOf tmp ["fn.emet"]
          codesOf (lfDiagnostics lf) @?= ["G03004"],
      testCase "a key net of [functions.requires] is G03101" $
        withFunctions "[functions.requires]\nnet = [\"x\"]\n" [] $ \tmp ->
          projectCodes tmp >>= (@?= ["G03101"]),
      testCase "a missing file is G03102, in a book that calls no function" $
        withFunctions "[functions.requires]\nfile = [\"data/words.tsv\"]\n" [] $ \tmp ->
          projectCodes tmp >>= (@?= ["G03102"]),
      testCase "a path outside the root is G03003" $
        withFunctions "[functions.requires]\nfile = [\"../words.tsv\"]\n" [] $ \tmp ->
          projectCodes tmp >>= (@?= ["G03003"]),
      testCase "two paths that differ only in case are G03004" $
        withFunctions "[functions.requires]\nfile = [\"data/a.tsv\", \"data/A.tsv\"]\n" [("data/a.tsv", "a\n")] $ \tmp ->
          projectCodes tmp >>= (@?= ["G03004"]),
      testCase "a file that is no UTF-8 is E05103" $
        withFunctions "[functions.requires]\nfile = [\"bad.tsv\"]\n" [("bad.tsv", "a\xff\n")] $ \tmp ->
          projectCodes tmp >>= (@?= ["E05103"]),
      testCase "a file over 64 MiB is E05105" $
        withFunctions "[functions.requires]\nfile = [\"big.tsv\"]\n" [] $ \tmp -> do
          withFile (tmp </> "big.tsv") WriteMode (\h -> hSetFileSize h (64 * 1024 * 1024 + 1))
          projectCodes tmp >>= (@?= ["E05105"]),
      testCase "a file with a BOM and CRLF is read without them" $
        withFunctions "[functions.requires]\nfile = [\"data/a.tsv\"]\n" [("fn.emet", readA), ("data/a.tsv", "\xEF\xBB\xBF\&a\tb\r\nc\td\r\n")] $ \tmp -> do
          rf <- required tmp
          codesOf (rqDiagnostics rf) @?= []
          r <- callA tmp rf
          r @?= Right (RPrim (VString "a\tb\nc\td\n")),
      testCase "two calls read the same text, though the file changes between them, in parallel as in sequence" $
        withFunctions "[functions.requires]\nfile = [\"data/a.tsv\"]\n" [("fn.emet", readA), ("data/a.tsv", "one\n")] $ \tmp -> do
          rf <- required tmp
          first <- callA tmp rf
          TIO.writeFile (tmp </> "data/a.tsv") "two\n"
          second <- callA tmp rf
          vars <- forM [1 :: Int .. 4] $ \_ -> do
            var <- newEmptyMVar
            _ <- forkIO (callA tmp rf >>= evaluate . (\r -> length (show r) `seq` r) >>= putMVar var)
            pure var
          parallel <- mapM takeMVar vars
          first @?= Right (RPrim (VString "one\n"))
          second @?= first
          parallel @?= replicate 4 first,
      testCase "the files of [functions.requires] are watched with the files of @table" $
        withFunctions "[functions.requires]\nfile = [\"data/./a.tsv\"]\n" [("data/a.tsv", "a\n")] $ \tmp ->
          evaluateProject Dev tmp >>= \case
            Left f -> assertFailure (show (pfDiagnostics f))
            Right e -> assertBool (show (evTableFiles e)) ("data/a.tsv" `elem` evTableFiles e)
    ]
  where
    callA tmp rf = do
      lf <- functionsOf tmp ["fn.emet"]
      case lfProgram lf of
        Nothing -> assertFailure (show (lfDiagnostics lf)) >> fail "unreachable"
        Just p -> pure (callFunction (requirementHandlers rf) p (mkSpan (FileId 0) 0 0) "fn.emet" "f" [RPrim (VNat 0)])
