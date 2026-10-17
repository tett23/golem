-- | S1 assembled again on every edit, without stale S1 diagnostics (golem-lsp ADR 0004).
module StaleS1Spec (staleS1Tests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.Workspace
import Golem.Syntax
import System.Directory (copyFile, createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

fixture :: FilePath
fixture = "test/fixtures/proj"

-- | b.gm of the fixture.
original :: Text
original = "@label second\n# 次の章\n\n[ref-title intro]と[ref-page intro]を見る。\n"

-- | A copy of the fixture with b.gm on disk.
withProject :: Text -> (FilePath -> IO a) -> IO a
withProject b act = withSystemTempDirectory "golem-lsp-s1" $ \tmp -> do
  forM_ ["manifest.toml", "style.toml", "a.gm", "common/values.gm"] $ \f ->
    createDirectoryIfMissing True (takeDirectory (tmp </> f)) >> copyFile (fixture </> f) (tmp </> f)
  BS.writeFile (tmp </> "b.gm") (TE.encodeUtf8 b)
  act tmp

-- | The code and the start of each diagnostic of b.gm.
codesOfB :: Workspace -> [(Text, Int)]
codesOfB ws = [(c, spanStart (diagSpan d)) | d <- fromMaybe [] (Map.lookup "b.gm" (diagnosticsFor ws)), let DiagnosticCode c = diagCode d]

byteOffset :: Text -> Text -> Int
byteOffset src needle = BS.length (TE.encodeUtf8 (fst (T.breakOn needle src)))

{- | Edits b.gm from @start@ through @edits@; the project is not evaluated
again, and the diagnostics after each edit are those of a project with that
b.gm on disk.
-}
editing :: Text -> [Text] -> IO Workspace
editing start edits = withProject start $ \tmp -> do
  ws0 <- openWorkspace tmp
  let go ws [] = pure ws
      go ws (b : rest) = do
        ws' <- updateFile ws "b.gm" b
        fresh <- withProject b openWorkspace
        diagnosticsFor ws' @?= diagnosticsFor fresh
        go ws' rest
  ws <- go ws0 edits
  wsFullEvaluations ws @?= wsFullEvaluations ws0
  pure ws

withNolabel :: Text
withNolabel = "@label second\n# 次の章\n\n[ref-title intro]と[ref-page nolabel]を見る。\n"

staleS1Tests :: TestTree
staleS1Tests =
  testGroup
    "S1 on every edit (golem-lsp ADR 0004)"
    [ testCase "a reference to a missing label is G0403 at once" $ do
        ws <- editing original [withNolabel]
        [s | ("G0403", s) <- codesOfB ws] @?= [byteOffset withNolabel "[ref-page nolabel]"],
      testCase "two @toc are G0402" $ do
        ws <- editing original [original <> "\n@toc\n\n@toc\n"]
        assertBool (show (codesOfB ws)) ("G0402" `elem` map fst (codesOfB ws)),
      testCase "removing the reference removes G0403" $ do
        ws <- editing withNolabel [original]
        [c | (c, _) <- codesOfB ws, c == "G0403"] @?= [],
      testCase "G0403 moves with the text before it" $ do
        let moved = "@label second\n# 次の章\n\n前の段落。\n\n[ref-title intro]と[ref-page nolabel]を見る。\n"
        ws <- editing withNolabel [moved]
        [s | ("G0403", s) <- codesOfB ws] @?= [byteOffset withNolabel "[ref-page nolabel]" + BS.length (TE.encodeUtf8 "前の段落。\n\n")],
      testCase "an S0 error stops S1, and removing it brings G0403 back" $ do
        let broken = withNolabel <> "\n[nosuch: x]\n"
        ws <- editing original [broken]
        map fst (codesOfB ws) @?= ["G0222"]
        ws' <- editing original [broken, withNolabel]
        map fst (codesOfB ws') @?= ["G0403"]
    ]
