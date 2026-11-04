-- | The functions of .gmx in the language server (docs/adr/0150).
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
import Golem.TestSupport.Manifest (manifestToml, testManifest)
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

gmx :: Text
gmx = "pub inline taxIncluded :: Nat -> Inlines;\ntaxIncluded n = Inline.text (String.fromNat n);\n\npub block wordTable :: String -> Blocks;\nwordTable s = Block.paragraph (Inline.text s);\n"

chapter :: Text
chapter = "[tax-included 1000]\n\n@word-table words\n"

withFunctionsProject :: Text -> (FilePath -> IO a) -> IO a
withFunctionsProject fn act = withSystemTempDirectory "golem-lsp-functions" $ \tmp0 -> do
  tmp <- canonicalizePath tmp0
  let files =
        [ ("manifest.toml", TE.encodeUtf8 (manifestToml testManifest) <> "\n[functions]\nfiles = [\"fn.gmx\"]\n"),
          ("style.toml", ""),
          ("a.gm", TE.encodeUtf8 chapter),
          ("fn.gmx", TE.encodeUtf8 fn)
        ]
  forM_ files $ \(p, b) -> createDirectoryIfMissing True (takeDirectory (tmp </> p)) >> BS.writeFile (tmp </> p) b
  act tmp

offsetOf :: Text -> Text -> Int
offsetOf src a = BS.length (TE.encodeUtf8 (fst (T.breakOn a src)))

codesOf :: Workspace -> FilePath -> [Text]
codesOf ws p = [c | d <- fromMaybe [] (Map.lookup p (diagnosticsFor ws)), let DiagnosticCode c = diagCode d]

functionsLspTests :: TestTree
functionsLspTests =
  testGroup
    "functions of .gmx (docs/adr/0150)"
    [ testCase "the names of the commands of functions are completed" $ withFunctionsProject gmx $ \dir -> do
        ws <- updateFile' dir "a.gm" "[tax"
        assertBool "inline" (Completion "tax-included" CkCommand `elem` completions ws "a.gm" 4)
        ws2 <- updateFile' dir "a.gm" "@word"
        assertBool "block" (Completion "word-table" CkCommand `elem` completions ws2 "a.gm" 5),
      testCase "the name of a command goes to the declaration of the function" $ withFunctionsProject gmx $ \dir -> do
        ws <- openWorkspace dir
        definition ws "a.gm" 3 @?= [Location "fn.gmx" (offsetOf gmx "taxIncluded ::") (offsetOf gmx "taxIncluded ::" + 11)]
        definition ws "a.gm" (offsetOf chapter "word-table" + 2) @?= [Location "fn.gmx" (offsetOf gmx "wordTable ::") (offsetOf gmx "wordTable ::" + 9)],
      testCase "the references of a function list the calls in .gm" $ withFunctionsProject gmx $ \dir -> do
        ws <- openWorkspace dir
        references ws "fn.gmx" (offsetOf gmx "taxIncluded ::" + 2) @?= [Location "a.gm" 1 13]
        references ws "a.gm" 3 @?= [Location "a.gm" 1 13],
      testCase "hover on a command shows the signature" $ withFunctionsProject "pub inline taxIncluded :: Nat -> Inlines => file;\ntaxIncluded n = Inline.text (String.fromNat n);\n" $ \dir -> do
        BS.appendFile (dir </> "manifest.toml") "requires = [\"file\"]\n"
        ws <- openWorkspace dir
        hover ws "a.gm" 3 @?= Just "taxIncluded :: Nat -> Inlines => file",
      testCase "the diagnostics of a .gmx are published on it" $ withFunctionsProject "pub inline taxIncluded :: Nat -> Inlines;\ntaxIncluded n = n;\n" $ \dir -> do
        ws <- openWorkspace dir
        codesOf ws "fn.gmx" @?= ["G10201"]
        codesOf ws "a.gm" @?= [],
      testCase "editing a .gmx evaluates the .gm again" $ withFunctionsProject gmx $ \dir -> do
        ws0 <- openWorkspace dir
        codesOf ws0 "a.gm" @?= []
        ws <- updateFile ws0 "fn.gmx" (T.replace "pub inline taxIncluded" "pub inline taxExcluded" (T.replace "taxIncluded n =" "taxExcluded n =" gmx))
        codesOf ws "a.gm" @?= ["G02022"],
      testCase "a .gmx is formatted" $ withFunctionsProject gmx $ \dir -> do
        ws <- updateFile' dir "fn.gmx" "f :: Nat;\n\n\n\nf = 1;\n"
        formatting ws "fn.gmx" @?= Just "f :: Nat;\n\nf = 1;\n"
    ]
  where
    updateFile' dir p t = openWorkspace dir >>= \ws -> updateFile ws p t
