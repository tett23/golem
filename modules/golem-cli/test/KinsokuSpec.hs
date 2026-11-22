{- | golem kinsoku (root ADR 0417): the resolved kinsoku and hanging
punctuation of the nearest project, as one line of JSON. Each test makes a
project in a temporary directory and runs golem as a process; I1 compares
the output with 'stComposition' of the same project evaluated by
'evaluateProject'.
-}
module KinsokuSpec (kinsokuTests) where

import Control.Monad (forM_, when)
import Data.Aeson qualified as J
import Data.Aeson.Types (parseEither)
import Data.ByteString qualified as BS
import Data.List (isInfixOf, isPrefixOf)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver (Evaluated (..), evaluateProject)
import Golem.Project (ProjectFailure (..))
import Golem.Project.Style (Composition (..), Style (..), defaultStyle)
import Golem.Syntax (Diagnostic (..), Profile (..))
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import System.Directory (canonicalizePath, createDirectoryIfMissing, createDirectoryLink, removeFile)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

kinsokuTests :: TestTree
kinsokuTests =
  testGroup
    "golem kinsoku (root ADR 0417)"
    [ testCase "root ADR 0417 I1: no style.toml gives the defaults and no notice" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
        writeProject root Nothing
        expected <- evaluated root
        (code, out, err) <- golemAt tmp ["kinsoku", root]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Just root, expected)
        expected @?= ("strict", False),
      testCase "root ADR 0417 I1: a style.toml without [composition] gives the defaults" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
        writeProject root (Just "[character-styles.note]\n")
        expected <- evaluated root
        (code, out, err) <- golemAt tmp ["kinsoku", root]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Just root, expected)
        expected @?= ("strict", False),
      testCase "root ADR 0417 I1: kinsoku = \"loose\" alone" $
        resolves "[composition]\nkinsoku = \"loose\"\n" ("loose", False),
      testCase "root ADR 0417 I1: hanging-punctuation = true alone" $
        resolves "[composition]\nhanging-punctuation = true\n" ("strict", True),
      testCase "root ADR 0417 I1: both written" $
        resolves "[composition]\nkinsoku = \"loose\"\nhanging-punctuation = true\n" ("loose", True),
      testCase "root ADR 0417 I1: both written as the defaults" $
        resolves "[composition]\nkinsoku = \"strict\"\nhanging-punctuation = false\n" ("strict", False),
      testCase "root ADR 0417 I1: a style.toml with a notice only: the JSON, the notice at the absolute style.toml, 0" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
        writeProject root (Just "[composition]\nhanging-punctuation = true\n\n[paragraph-styles.table]\nindent = \"0zw\"\n")
        expected <- evaluated root
        (code, out, err) <- golemAt tmp ["kinsoku", root]
        code @?= ExitSuccess
        output out @?= Right (Just root, expected)
        expected @?= ("strict", True)
        assertBool err ((root </> "style.toml:") `isPrefixOf` err && "notice[G03100]" `isInfixOf` err),
      testCase "root ADR 0417 I1, I4: PATH is a chapter of the project" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
        writeProject root (Just "[composition]\nkinsoku = \"loose\"\n")
        expected <- evaluated root
        (code, out, err) <- golemAt tmp ["kinsoku", root </> "chapters/01.gm"]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Just root, expected),
      testCase "root ADR 0417 I1, I4: PATH is relative to the working directory" $ inTemp $ \tmp0 -> do
        -- the working directory of golem is the real path of the directory
        tmp <- canonicalizePath tmp0
        let root = tmp </> "book"
        writeProject root (Just "[composition]\nkinsoku = \"loose\"\n")
        expected <- evaluated root
        (code, out, err) <- golemAt tmp ["kinsoku", "book/chapters/01.gm"]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Just root, expected),
      testCase "root ADR 0417 I1, I4: no PATH, and the working directory is the root" $ inTemp $ \tmp0 -> do
        tmp <- canonicalizePath tmp0
        let root = tmp </> "book"
        writeProject root (Just "[composition]\nhanging-punctuation = true\n")
        expected <- evaluated root
        (code, out, err) <- golemAt root ["kinsoku"]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Just root, expected),
      testCase "root ADR 0417 I1, I4: PATH is a file of the project that does not exist" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
        writeProject root (Just "[composition]\nkinsoku = \"loose\"\nhanging-punctuation = true\n")
        expected <- evaluated root
        (code, out, err) <- golemAt tmp ["kinsoku", root </> "chapters/drafts/unsaved.gm"]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Just root, expected),
      testCase "root ADR 0417 I4: a file of a nested project gives the inner project" $ inTemp $ \tmp -> do
        let outer = tmp </> "book"
            inner = outer </> "parts" </> "inner"
        writeProject outer (Just "[composition]\nkinsoku = \"loose\"\n")
        writeProject inner (Just "[composition]\nhanging-punctuation = true\n")
        (code, out, err) <- golemAt tmp ["kinsoku", inner </> "chapters/01.gm"]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Just inner, ("strict", True))
        -- parts has no manifest.toml: the nearest one upwards is the outer project
        (code', out', err') <- golemAt tmp ["kinsoku", outer </> "parts" </> "notes.gm"]
        (code', err') @?= (ExitSuccess, "")
        output out' @?= Right (Just outer, ("loose", False)),
      testCase "root ADR 0417 I4: the root is not resolved through a symbolic link and has no trailing separator" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
            link = tmp </> "link"
        writeProject root (Just "[composition]\nkinsoku = \"loose\"\n")
        createDirectoryLink root link
        (code, out, err) <- golemAt tmp ["kinsoku", link </> "chapters/01.gm"]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Just link, ("loose", False))
        (_, slashed, _) <- golemAt tmp ["kinsoku", root <> "/"]
        output slashed @?= Right (Just root, ("loose", False)),
      testCase "root ADR 0417 I2: PATH is a directory without manifest.toml upwards" $ inTemp $ \tmp -> do
        createDirectoryIfMissing True (tmp </> "loose")
        (code, out, err) <- golemAt tmp ["kinsoku", tmp </> "loose"]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Nothing, fromComposition (stComposition defaultStyle))
        fromComposition (stComposition defaultStyle) @?= ("strict", False),
      testCase "root ADR 0417 I2: PATH is a file without manifest.toml upwards" $ inTemp $ \tmp -> do
        writeFiles tmp [("loose/memo.gm", "メモ。\n"), ("loose/style.toml", "[composition]\nkinsoku = \"loose\"\n")]
        (code, out, err) <- golemAt tmp ["kinsoku", tmp </> "loose/memo.gm"]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Nothing, fromComposition (stComposition defaultStyle)),
      testCase "root ADR 0417 I1: a project without its chapter files gives the same values" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
        writeProject root (Just "[composition]\nkinsoku = \"loose\"\nhanging-punctuation = true\n")
        expected <- evaluated root
        removeFile (root </> "chapters/01.gm")
        (code, out, err) <- golemAt tmp ["kinsoku", root]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Just root, expected),
      testCase "root ADR 0417 I1: an error of manifest.toml does not change the values" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
        writeProject root (Just "[composition]\nkinsoku = \"loose\"\n")
        expected <- evaluated root
        writeFiles root [("manifest.toml", "[book\n")]
        (code, out, err) <- golemAt tmp ["kinsoku", root]
        (code, err) @?= (ExitSuccess, "")
        output out @?= Right (Just root, expected),
      testCase "root ADR 0417 I3: kinsoku = \"medium\" is an error: nothing on stdout, 1" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
        writeProject root (Just "[composition]\nkinsoku = \"medium\"\n")
        (code, out, err) <- golemAt tmp ["kinsoku", root </> "chapters/01.gm"]
        (code, out) @?= (ExitFailure 1, "")
        assertBool err ((root </> "style.toml:") `isPrefixOf` err && "error[" `isInfixOf` err),
      testCase "root ADR 0417 I3: a style.toml that is not TOML: nothing on stdout, 1" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
        writeProject root (Just "[composition\n")
        (code, out, err) <- golemAt tmp ["kinsoku", root]
        (code, out) @?= (ExitFailure 1, "")
        assertBool err ((root </> "style.toml:") `isPrefixOf` err && "error[" `isInfixOf` err),
      testCase "root ADR 0417 I3: a style.toml that does not pass the reading stage: nothing on stdout, 1" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
        writeProject root Nothing
        BS.writeFile (root </> "style.toml") (BS.pack [0x5b, 0xff, 0x5d, 0x0a])
        (code, out, err) <- golemAt tmp ["kinsoku", root]
        (code, out) @?= (ExitFailure 1, "")
        assertBool err ((root </> "style.toml:") `isPrefixOf` err && "error[G01001]" `isInfixOf` err),
      testCase "root ADR 0417: two arguments are a usage error, 2 (golem-cli ADR 0004)" $ inTemp $ \tmp -> do
        (code, out, _) <- golemAt tmp ["kinsoku", "a", "b"]
        (code, out) @?= (ExitFailure 2, ""),
      testCase "root ADR 0417: --format is not an option of golem kinsoku, 2" $ inTemp $ \tmp -> do
        (code, out, _) <- golemAt tmp ["kinsoku", "--format", "json"]
        (code, out) @?= (ExitFailure 2, ""),
      testCase "root ADR 0417 I5: one line of JSON, a newline, and the keys in order" $ inTemp $ \tmp -> do
        let root = tmp </> "book"
        writeProject root (Just "[composition]\nkinsoku = \"loose\"\nhanging-punctuation = true\n")
        createDirectoryIfMissing True (tmp </> "elsewhere")
        writeProject (tmp </> "plain") Nothing
        (_, found, _) <- golemAt tmp ["kinsoku", root </> "chapters/01.gm"]
        found @?= "{\"schema\":1,\"project\":" <> jsonString root <> ",\"composition\":{\"kinsoku\":\"loose\",\"hangingPunctuation\":true}}\n"
        (_, plain, _) <- golemAt tmp ["kinsoku", tmp </> "plain"]
        plain @?= "{\"schema\":1,\"project\":" <> jsonString (tmp </> "plain") <> ",\"composition\":{\"kinsoku\":\"strict\",\"hangingPunctuation\":false}}\n"
        (_, none, _) <- golemAt tmp ["kinsoku", tmp </> "elsewhere"]
        none @?= "{\"schema\":1,\"project\":null,\"composition\":{\"kinsoku\":\"strict\",\"hangingPunctuation\":false}}\n",
      testCase "root ADR 0417 I5: a root with characters that JSON escapes" $ inTemp $ \tmp -> do
        let root = tmp </> "a \"quoted\" \\ book 本"
        writeProject root Nothing
        (code, out, err) <- golemAt tmp ["kinsoku", root]
        (code, err) @?= (ExitSuccess, "")
        out @?= "{\"schema\":1,\"project\":" <> jsonString root <> ",\"composition\":{\"kinsoku\":\"strict\",\"hangingPunctuation\":false}}\n"
        output out @?= Right (Just root, ("strict", False))
    ]
  where
    resolves style expected = inTemp $ \tmp -> do
      let root = tmp </> "book"
      writeProject root (Just style)
      evaluatedValue <- evaluated root
      evaluatedValue @?= expected
      (code, out, err) <- golemAt tmp ["kinsoku", root]
      (code, err) @?= (ExitSuccess, "")
      output out @?= Right (Just root, evaluatedValue)

inTemp :: (FilePath -> IO a) -> IO a
inTemp = withSystemTempDirectory "golem-kinsoku"

golemAt :: FilePath -> [String] -> IO (ExitCode, String, String)
golemAt dir args = readCreateProcessWithExitCode (proc "golem" args) {cwd = Just dir} ""

writeFiles :: FilePath -> [(FilePath, String)] -> IO ()
writeFiles dir = mapM_ $ \(p, c) -> do
  createDirectoryIfMissing True (takeDirectory (dir </> p))
  BS.writeFile (dir </> p) (TE.encodeUtf8 (T.pack c))

-- | A project of one chapter, with the given style.toml or none.
writeProject :: FilePath -> Maybe String -> IO ()
writeProject root style = do
  writeFiles root [("manifest.toml", T.unpack (manifestToml testManifest {tmChapters = ["chapters/01.gm"]})), ("chapters/01.gm", "本文。\n")]
  forM_ style $ \s -> writeFiles root [("style.toml", s)]

-- | The kinsoku and the hanging punctuation as golem kinsoku writes them (root ADR 0417 I1). The composition of defaultStyle is defaultComposition.
fromComposition :: Composition -> (String, Bool)
fromComposition c = (if compKinsokuStrict c then "strict" else "loose", compHanging c)

-- | The composition of the project evaluated by golem-driver.
evaluated :: FilePath -> IO (String, Bool)
evaluated root =
  evaluateProject Dev root >>= \case
    Left f -> assertFailure (show (map diagMessage (pfDiagnostics f)))
    Right e -> pure (fromComposition (stComposition (evStyle e)))

-- | The project and the composition of the JSON on stdout.
output :: String -> Either String (Maybe FilePath, (String, Bool))
output s =
  J.eitherDecodeStrict (TE.encodeUtf8 (T.pack s))
    >>= parseEither
      ( J.withObject "golem kinsoku" $ \o -> do
          schema <- o J..: "schema"
          when (schema /= (1 :: Int)) (fail ("schema " <> show schema))
          c <- o J..: "composition"
          (,) <$> o J..: "project" <*> ((,) <$> c J..: "kinsoku" <*> c J..: "hangingPunctuation")
      )

-- | A JSON string, for the tests of the exact output.
jsonString :: FilePath -> String
jsonString p = T.unpack (TE.decodeUtf8 (BS.toStrict (J.encode p)))
