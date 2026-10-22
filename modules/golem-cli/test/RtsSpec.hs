{- | The runtime of the golem executable: the threaded RTS on every
processor, so that the PDF pipeline's parallel composition (golem-driver
ADR 0002) runs on several OS threads.
-}
module RtsSpec (rtsTests) where

import Data.List (isInfixOf)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode, readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

rtsTests :: TestTree
rtsTests =
  testGroup
    "the runtime of golem"
    [ testCase "golem is linked with the threaded RTS and starts on every processor (-N)" $ do
        (code, out, _) <- readProcessWithExitCode "golem" ["+RTS", "--info", "-RTS"] ""
        (code, filter (`isInfixOf` out) [rtsWay, withN]) @?= (ExitSuccess, [rtsWay, withN]),
      -- GHCRTS comes after -with-rtsopts, so the check of the environment
      -- can change the number of capabilities (docs/adr/0050)
      testCase "GHCRTS=-N1 runs golem on one capability" $ usingN "-N1" >>= assertBool "using -N1",
      testCase "GHCRTS=-N2 runs golem on two capabilities" $ usingN "-N2" >>= assertBool "using -N2"
    ]
  where
    usingN n = do
      env <- filter ((/= "GHCRTS") . fst) <$> getEnvironment
      (_, _, err) <- readCreateProcessWithExitCode (proc "golem" ["+RTS", "-s", "-RTS", "--version"]) {env = Just (("GHCRTS", n) : env)} ""
      pure (("using " <> n <> ")") `isInfixOf` err)
    rtsWay = "(\"RTS way\", \"rts_thr\")"
    withN = "(\"Flag -with-rtsopts\", \"-N\")"
