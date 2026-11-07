{- | buildPdfInMemory writes nothing (docs/adr/0199). The test changes the
current directory, so it is in golem-driver-global-test (docs/adr/0146).
-}
module InMemoryWritesSpec (inMemoryWritesTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Golem.Driver
import System.Directory (listDirectory, withCurrentDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The files of the kanikosen fixture, by their paths from it.
kanikosen :: IO (Map.Map FilePath BS.ByteString)
kanikosen = do
  let root = "test/fixtures/kanikosen"
      one p = (p,) <$> BS.readFile (root </> p)
  fonts <- map ("fonts/" <>) <$> listDirectory (root </> "fonts")
  Map.fromList <$> mapM one (["manifest.toml", "style.toml", "kanikosen.gm"] <> fonts)

inMemoryWritesTests :: TestTree
inMemoryWritesTests =
  testCase "buildPdfInMemory writes nothing in the current directory (docs/adr/0199)" $ do
    table <- kanikosen
    withSystemTempDirectory "golem-memory-writes" $ \tmp -> do
      m <- withCurrentDirectory tmp (buildPdfInMemory table)
      assertBool "a PDF" (isJust (bimPdf m))
      left <- listDirectory tmp
      left @?= []
