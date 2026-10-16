{- | The locale does not reach the output (docs/adr/0002-determinism.md):
with the encoding of the process set to EUC-JP, build writes the HTML and
the plain text in the same UTF-8 bytes, and golem new writes its template
in UTF-8.
-}
module LocaleSpec (localeTests) where

import Control.Exception (bracket)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text.Encoding qualified as TE
import GHC.IO.Encoding (getLocaleEncoding, mkTextEncoding, setLocaleEncoding, utf8)
import Golem.Driver
import Golem.Driver.New
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

localeTests :: TestTree
localeTests =
  testGroup
    "the locale does not change the output (docs/adr/0002-determinism.md)"
    [ testCase "HTML and plain text are the same UTF-8 bytes under EUC-JP" $ do
        ref <- withEncoding "UTF-8" builtOutputs
        euc <- withEncoding "EUC-JP" builtOutputs
        assertBool "files" (not (null ref))
        map fst euc @?= map fst ref
        forM_ (zip ref euc) $ \((p, a), (_, b)) -> assertEqual p a b
        -- the fixture's heading, in UTF-8
        case lookup "html/chapters/01.xhtml" ref of
          Nothing -> assertFailure (show (map fst ref))
          Just b -> assertBool "はじめに in UTF-8" (TE.encodeUtf8 "はじめに" `BS.isInfixOf` b),
      testCase "golem new writes the template in UTF-8 under EUC-JP" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        let files = templateFiles Japanese uuid0
        r <- withEncoding "EUC-JP" (createProject (tmp </> "book") files Nothing)
        r @?= Right ()
        forM_ files $ \(p, t) -> BS.readFile (tmp </> "book" </> p) >>= assertEqual p (TE.encodeUtf8 t)
    ]

-- | Runs the action with the locale encoding of the process set, and restores it.
withEncoding :: String -> IO a -> IO a
withEncoding name act = do
  enc <- if name == "UTF-8" then pure utf8 else mkTextEncoding name
  bracket (getLocaleEncoding <* setLocaleEncoding enc) setLocaleEncoding (const act)

-- | Builds a copy of the fixture as HTML and plain text; the files under build/ and their bytes.
builtOutputs :: IO [(FilePath, BS.ByteString)]
builtOutputs = withSystemTempDirectory "golem-locale" $ \tmp -> do
  copyTree fixture tmp
  r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetText]}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  Map.toList <$> buildFiles (tmp </> "build")
