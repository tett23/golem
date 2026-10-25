{- | The locale does not reach the output (docs/adr/0002-determinism.md):
golem writes the same UTF-8 bytes to its files, stdout and stderr under a
UTF-8 locale, an EUC-JP locale and the C locale. Where the system has no
such locale, the C library falls back to C, which golem must survive too.
-}
module LocaleSpec (localeTests) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Monad (forM, forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (sort)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), StdStream (..), createProcess, proc, waitForProcess)
import Test.Tasty
import Test.Tasty.HUnit

localeTests :: TestTree
localeTests =
  testGroup
    "the locale does not change the output (docs/adr/0002-determinism.md)"
    [ sameEverywhere "golem build --target html --target text writes the same files" projectFiles ["build", "--target", "html", "--target", "text"] $ \r ->
        assertJapanese "build/html/a.xhtml" (lookup "build/html/a.xhtml" (rFiles r)),
      sameEverywhere "golem check --format json writes the same JSON" syntaxErrorFiles ["check", "--format", "json"] $ \r ->
        assertJapanese "stderr" (Just (rErr r)),
      sameEverywhere "golem check writes the same diagnostics and hint" syntaxErrorFiles ["check"] $ \r ->
        assertJapanese "stderr" (Just (rErr r)),
      sameEverywhere "golem explain writes the same section" [] ["explain", "G01017"] $ \r ->
        assertJapanese "stdout" (Just (rOut r)),
      sameEverywhere "golem inspect writes the same tree" projectFiles ["inspect", "a.gm"] $ \r ->
        assertJapanese "stdout" (Just (rOut r)),
      sameEverywhere "a usage error is the same message" [] ["nope"] $ \r ->
        assertJapanese "stderr" (Just (rErr r)),
      sameEverywhere "golem new writes the same template" [] ["new", "book", "--no-fonts"] $ \r -> do
        assertJapanese "stderr" (Just (rErr r))
        assertJapanese "book/chapters/01.gm" (lookup "book/chapters/01.gm" (rFiles r)),
      sameEverywhere "golem plugin lock writes the same plugins.lock" pluginFiles ["plugin", "lock"] $ \r ->
        assertBool "plugins.lock" ("plugins.lock" `elem` map fst (rFiles r))
    ]

-- | The locales: the first is the reference.
locales :: [String]
locales = ["en_US.UTF-8", "ja_JP.eucJP", "ja_JP.EUC-JP", "C"]

data Run = Run {rCode :: ExitCode, rOut :: BS.ByteString, rErr :: BS.ByteString, rFiles :: [(FilePath, BS.ByteString)]}
  deriving stock (Eq, Show)

{- | Runs golem under every locale in a fresh copy of the files, checks the
first run, and expects the others to be byte-identical to it.
-}
sameEverywhere :: String -> [(FilePath, T.Text)] -> [String] -> (Run -> Assertion) -> TestTree
sameEverywhere name files args check = testCase name $ do
  runs <- forM locales $ \l -> (l,) <$> golemUnder l files args
  case runs of
    [] -> assertFailure "no locale"
    (l0, ref) : others -> do
      check ref
      forM_ others $ \(l, r) -> assertEqual (l <> " against " <> l0) (normalize ref) (normalize r)

{- | golem new writes a fresh id into manifest.toml; everything else must
agree to the byte.
-}
normalize :: Run -> Run
normalize r = r {rFiles = [(p, if p == "book/manifest.toml" then dropId b else b) | (p, b) <- rFiles r]}
  where
    dropId = BC.unlines . filter (not . BC.isPrefixOf "id = ") . BC.lines

-- | Runs golem in a new directory with the files, under the locale.
golemUnder :: String -> [(FilePath, T.Text)] -> [String] -> IO Run
golemUnder locale files args = withSystemTempDirectory "golem-locale" $ \tmp -> do
  forM_ files $ \(p, c) -> do
    createDirectoryIfMissing True (takeDirectory (tmp </> p))
    BS.writeFile (tmp </> p) (TE.encodeUtf8 c)
  env <- getEnvironment
  let env' = [("LC_ALL", locale), ("LANG", locale), ("LC_CTYPE", locale)] <> filter ((`notElem` ["LC_ALL", "LANG", "LC_CTYPE"]) . fst) env
  (code, out, err) <- runBytes (proc "golem" args) {cwd = Just tmp, env = Just env'}
  written <- filesUnder tmp
  let new = filter (`notElem` map fst files) written
  contents <- mapM (\p -> (p,) <$> BS.readFile (tmp </> p)) new
  pure (Run code out err contents)

-- | Runs a process; exit code, stdout and stderr as bytes.
runBytes :: CreateProcess -> IO (ExitCode, BS.ByteString, BS.ByteString)
runBytes cp = do
  (_, mout, merr, ph) <- createProcess cp {std_in = NoStream, std_out = CreatePipe, std_err = CreatePipe}
  case (mout, merr) of
    (Just hout, Just herr) -> do
      v <- newEmptyMVar
      _ <- forkIO (BS.hGetContents herr >>= putMVar v)
      out <- BS.hGetContents hout
      err <- takeMVar v
      hClose hout
      hClose herr
      code <- waitForProcess ph
      pure (code, out, err)
    _ -> do
      _ <- waitForProcess ph
      assertFailure "no pipes"

-- | Every file under a directory, relative to it, sorted.
filesUnder :: FilePath -> IO [FilePath]
filesUnder root = sort <$> go ""
  where
    go rel = do
      names <- listDirectory (root </> rel)
      concat
        <$> mapM
          ( \n -> do
              let p = if null rel then n else rel </> n
              isDir <- doesDirectoryExist (root </> p)
              if isDir then go p else pure [p]
          )
          names

-- | The bytes are UTF-8 and hold Japanese.
assertJapanese :: String -> Maybe BS.ByteString -> Assertion
assertJapanese what = \case
  Nothing -> assertFailure (what <> " is missing")
  Just b -> case TE.decodeUtf8' b of
    Left e -> assertFailure (what <> " is not UTF-8: " <> show e)
    Right t -> assertBool (what <> " holds no Japanese: " <> T.unpack t) (T.any (\c -> c >= '\x3040' && c <= '\x9FFF') t)

manifest :: T.Text
manifest = manifestToml testManifest {tmTitle = "日本語の本", tmTargets = ["html", "text"]}

projectFiles :: [(FilePath, T.Text)]
projectFiles = [("manifest.toml", manifest), ("a.gm", "# はじめに\n\n吾輩は猫である。名前はまだ無い。\n")]

syntaxErrorFiles :: [(FilePath, T.Text)]
syntaxErrorFiles = [("manifest.toml", manifest), ("a.gm", "[strong: 閉じない\n")]

pluginFiles :: [(FilePath, T.Text)]
pluginFiles = [("manifest.toml", manifest)]
