-- | The language server and the functions of .emet (docs/adr/0162).
module FunctionsLspSpec (functionsLspTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.Features
import Golem.Lsp.Workspace
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

bookEmet :: Text
bookEmet =
  T.unlines
    [ "import \"fn/lib.emet\"",
      "",
      "pub inline \"tax-included\" taxIncluded :: Nat -> Inlines",
      "taxIncluded n = Inline.text (String.fromNat (twice n))",
      "",
      "pub block rule :: Blocks",
      "rule = Block.paragraph (Inline.text \"――\")",
      "",
      "pub fn total :: List Nat -> <file \"w.tsv\"> Nat",
      "total xs = List.length xs + String.length (File.read \"w.tsv\")"
    ]

libEmet :: Text
libEmet = "pub twice :: Nat -> Nat\ntwice n = n * 2\n"

chapter :: Text
chapter = "@import fn/book.emet as book\n\n[book.tax-included 1000]\n\n@book.rule\n\n[= book.total([1])]\n"

-- | A project of a.gm and the two .emet, the workspace opened on it.
withFunctions :: (FilePath -> Workspace -> IO a) -> IO a
withFunctions act = withSystemTempDirectory "golem-lsp-functions" $ \tmp0 -> do
  tmp <- canonicalizePath tmp0
  let files =
        [ ("manifest.toml", TE.encodeUtf8 (manifestToml testManifest {tmChapters = ["a.gm"]} <> "\n[functions.requires]\nfile = [\"w.tsv\"]\n")),
          ("a.gm", TE.encodeUtf8 chapter),
          ("fn/book.emet", TE.encodeUtf8 bookEmet),
          ("fn/lib.emet", TE.encodeUtf8 libEmet),
          ("w.tsv", "w\n")
        ]
  forM_ files $ \(p, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> p)) >> BS.writeFile (tmp </> p) bytes
  ws <- openWorkspace tmp
  act tmp ws

-- | The offset of a needle in a text, and a number of bytes further.
offsetIn :: Text -> Text -> Int -> Int
offsetIn text needle k = BS.length (TE.encodeUtf8 (fst (T.breakOn needle text))) + k

codesOf :: Workspace -> FilePath -> [Text]
codesOf ws p = [c | d <- fromMaybe [] (Map.lookup p (diagnosticsFor ws)), let DiagnosticCode c = diagCode d]

functionsLspTests :: TestTree
functionsLspTests =
  testGroup
    "the functions of .emet (docs/adr/0162)"
    [ testCase "the project with functions has no diagnostics" $
        withFunctions $ \_ ws -> do
          codesOf ws "a.gm" @?= []
          codesOf ws "fn/book.emet" @?= [],
      testCase "completion in a .emet: the variables of the patterns, the names of a built-in module, the requirements" $
        withFunctions $ \_ ws -> do
          let names o = map cmpLabel (completions ws "fn/book.emet" o)
          assertBool "n and twice" (all (`elem` names (offsetIn bookEmet "(twice n)" 7)) ["n", "twice", "taxIncluded", "List"])
          assertBool "List.length" ("length" `elem` names (offsetIn bookEmet "List.length" 5))
          names (offsetIn bookEmet "<file" 1) @?= ["file"],
      testCase "completion in a .gm after a namespace of a .emet" $
        withFunctions $ \_ ws -> do
          let text = chapter <> "\n[book."
          ws' <- updateFile ws "a.gm" text
          map cmpLabel (completions ws' "a.gm" (BS.length (TE.encodeUtf8 text))) @?= ["tax-included"]
          let block = chapter <> "\n@book."
          ws'' <- updateFile ws "a.gm" block
          map cmpLabel (completions ws'' "a.gm" (BS.length (TE.encodeUtf8 block))) @?= ["rule"]
          let expr = chapter <> "\n[= book."
          ws3 <- updateFile ws "a.gm" expr
          map cmpLabel (completions ws3 "a.gm" (BS.length (TE.encodeUtf8 expr))) @?= ["total"],
      testCase "definition: from a command of .gm to the .emet, and in a .emet to an import" $
        withFunctions $ \_ ws -> do
          map locPath (definition ws "a.gm" (offsetIn chapter "book.tax-included" 6)) @?= ["fn/book.emet"]
          map locStart (definition ws "a.gm" (offsetIn chapter "book.tax-included" 6)) @?= [offsetIn bookEmet "taxIncluded ::" 0]
          map locPath (definition ws "a.gm" (offsetIn chapter "book.total" 6)) @?= ["fn/book.emet"]
          map locPath (definition ws "fn/book.emet" (offsetIn bookEmet "twice n" 1)) @?= ["fn/lib.emet"],
      testCase "references: the calls in .gm of a function of a .emet" $
        withFunctions $ \_ ws -> do
          map locPath (references ws "fn/book.emet" (offsetIn bookEmet "taxIncluded ::" 1)) @?= ["a.gm"]
          map locPath (references ws "a.gm" (offsetIn chapter "book.rule" 2)) @?= ["a.gm"],
      testCase "hover: the signature with its requirements in .gm, and the type in a .emet" $
        withFunctions $ \_ ws -> do
          hover ws "a.gm" (offsetIn chapter "book.total" 3) @?= Just "pub fn total :: List Nat -> <file \"w.tsv\"> Nat"
          hover ws "fn/book.emet" (offsetIn bookEmet "List.length" 6) @?= Just "length :: List a -> Nat"
          hover ws "fn/book.emet" (offsetIn bookEmet "twice n)" 1) @?= Just "twice :: Nat -> Nat",
      testCase "an edit of a .emet evaluates the .gm again, and its diagnostics are published" $
        withFunctions $ \_ ws -> do
          ws' <- updateFile ws "fn/book.emet" (T.replace "pub block rule" "pub block line" (T.replace "\nrule =" "\nline =" bookEmet))
          codesOf ws' "a.gm" @?= ["G02009"]
          ws'' <- updateFile ws "fn/book.emet" (bookEmet <> "\nbroken :: Nat\nbroken = \"x\"\n")
          codesOf ws'' "a.gm" @?= []
          assertBool "an error in the .emet" (not (null (codesOf ws'' "fn/book.emet"))),
      testCase "formatting of a .emet" $
        withFunctions $ \_ ws -> do
          ws' <- updateFile ws "fn/lib.emet" (libEmet <> "\n\n\n")
          formatting ws' "fn/lib.emet" @?= Just libEmet
    ]
