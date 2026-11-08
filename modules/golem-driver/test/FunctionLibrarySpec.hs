{- | The functions of the repository (functions/ at its root): .emet files
that a press copies into its projects. Each function that a .gm can call
documents its examples in the comment before its signature:

> -- >>> [dates.wareki 2026]
> -- 令和8年

A line @-- >>> @ is the call, set in a chapter of its own that imports the
file as its base name; the lines @-- ... @ after it continue the call (the
body of a block command); the comment lines after them, up to the
signature, are the lines of the plain text of the chapter (@--@ alone is
an empty line). Every example builds without diagnostics and gives its
lines; every file is as @golem fmt@ writes it and has nothing for
@golem lint@ to report.
-}
module FunctionLibrarySpec (functionLibraryTests) where

import Control.Monad (forM, forM_)
import Data.ByteString qualified as BS
import Data.List (isPrefixOf, sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Driver.Functions (formatFunctionFile)
import Golem.Driver.Lint (lintProject)
import Golem.Syntax
import Support (codesOf, copyTree)
import System.Directory (listDirectory)
import System.FilePath (dropExtension, takeExtension, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

-- | The functions/ of the repository, from the directory of golem-driver, where the tests run.
library :: FilePath
library = "../../functions"

-- | An example: the file, the lines of the call and the lines of the plain text.
data Example = Example
  { exFile :: FilePath,
    exCall :: [Text],
    exExpected :: [Text]
  }
  deriving (Show)

functionLibraryTests :: TestTree
functionLibraryTests =
  testGroup
    "the functions of the repository (functions/)"
    [ testCase "every .emet is as golem fmt writes it" $ do
        files <- emetFiles
        forM_ files $ \f -> do
          t <- readText (library </> f)
          case formatFunctionFile t of
            Left ds -> assertFailure (f <> ": " <> show (codesOf ds))
            Right formatted -> assertBool (f <> " is not formatted") (formatted == t),
      testCase "every function a .gm calls has an example" $ do
        files <- emetFiles
        missing <- fmap concat . forM files $ \f -> do
          ls <- T.lines <$> readText (library </> f)
          pure [(f, sig) | (sig, comment) <- commandSignatures ls, not (any (T.isPrefixOf ">>> ") comment)]
        missing @?= [],
      testCase "every example builds without diagnostics and gives its plain text" $
        withLibrary $ \tmp examples -> do
          r <- build (defaultOptions tmp)
          noDiagnostics (brDiagnostics r)
          forM_ (zip [1 :: Int ..] examples) $ \(i, ex) -> do
            got <- readText (tmp </> "build" </> "text" </> "horizontal" </> chapterName i <> ".txt")
            (exFile ex, exCall ex, trimEnd (T.lines got)) @?= (exFile ex, exCall ex, trimEnd (exExpected ex)),
      testCase "golem lint reports nothing on the .emet" $
        withLibrary $ \tmp _ -> do
          (_, ds) <- lintProject Dev False True tmp
          noDiagnostics [d | d <- ds, let DiagnosticCode c = diagCode d, "E0" `T.isPrefixOf` c]
    ]

-- | Fails with the codes, the messages and the sites of the diagnostics, if any.
noDiagnostics :: [Diagnostic] -> Assertion
noDiagnostics [] = pure ()
noDiagnostics ds = assertFailure (T.unpack (T.unlines [c <> " " <> diagMessage d <> " " <> T.pack (show (diagSpan d)) | d <- ds, let DiagnosticCode c = diagCode d]))

-- | The .emet of functions/, sorted.
emetFiles :: IO [FilePath]
emetFiles = do
  fs <- sort . filter ((== ".emet") . takeExtension) <$> listDirectory library
  assertBool "functions/ has no .emet" (not (null fs))
  pure fs

readText :: FilePath -> IO Text
readText p = TE.decodeUtf8 <$> BS.readFile p

{- | A project with functions/ copied into it and a chapter for each example,
in the order of the files and of the examples in them.
-}
withLibrary :: (FilePath -> [Example] -> IO a) -> IO a
withLibrary k = withSystemTempDirectory "golem-functions" $ \tmp -> do
  files <- emetFiles
  examples <- fmap concat . forM files $ \f -> examplesOf f . T.lines <$> readText (library </> f)
  assertBool "functions/ has no example" (not (null examples))
  copyTree library (tmp </> "functions")
  let names = [chapterName i | i <- [1 .. length examples]]
  forM_ (zip names examples) $ \(n, ex) ->
    BS.writeFile (tmp </> n <> ".gm") . TE.encodeUtf8 . T.unlines $
      ("@import functions/" <> T.pack (exFile ex) <> " as " <> T.pack (dropExtension (exFile ex))) : "" : exCall ex
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifest names))
  BS.writeFile (tmp </> "style.toml") styles
  k tmp examples

-- | The paragraph styles that functions/README.md tells a project to define.
styles :: BS.ByteString
styles = "[paragraph-styles.epigraph]\nindent = \"2zw\"\n\n[paragraph-styles.epigraph-source]\nalign = \"right\"\n"

chapterName :: Int -> String
chapterName = printf "example-%03d"

manifest :: [String] -> Text
manifest names =
  T.unlines
    [ "chapters = [" <> T.intercalate ", " [T.pack (show (n <> ".gm")) | n <- names] <> "]",
      "",
      "[metadata]",
      "id = \"urn:uuid:00000000-0000-4000-8000-000000000237\"",
      "title = \"functions/ の例\"",
      "language = \"ja\"",
      "date = 2026-11-08",
      "",
      "[targets.text]",
      "",
      "[source]",
      "paragraph-separator = \"blank-line\""
    ]

{- | The examples of a file: a line @-- >>> @, the lines @-- ... @ after it,
and the comment lines after them up to the first line that is not a
comment or is another example.
-}
examplesOf :: FilePath -> [Text] -> [Example]
examplesOf f = go
  where
    go [] = []
    go (l : ls) = case T.stripPrefix "-- >>> " l of
      Just call ->
        let (more, rest) = span (T.isPrefixOf "-- ... ") ls
            (expected, rest') = span (\x -> isComment x && not (T.isPrefixOf "-- >>> " x)) rest
         in Example f (call : map (T.drop 7) more) (map commentText expected) : go rest'
      Nothing -> go ls
    isComment x = x == "--" || "-- " `T.isPrefixOf` x

-- | The text of a comment line: @--@ alone is an empty line.
commentText :: Text -> Text
commentText x = if x == "--" then "" else T.drop 3 x

{- | The signatures of the functions a .gm calls (@pub inline@, @pub block@,
@pub fn@), each with the texts of the comment lines just before it.
-}
commandSignatures :: [Text] -> [(Text, [Text])]
commandSignatures = go []
  where
    go _ [] = []
    go comment (l : ls)
      | l == "--" || "-- " `T.isPrefixOf` l = go (comment <> [commentText l]) ls
      | any (`isPrefixOf` T.unpack l) ["pub inline ", "pub block ", "pub fn "] = (l, comment) : go [] ls
      | otherwise = go [] ls

-- | The lines without the empty lines at the end.
trimEnd :: [Text] -> [Text]
trimEnd = reverse . dropWhile T.null . reverse
