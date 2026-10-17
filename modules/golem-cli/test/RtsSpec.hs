{- | The runtime of the golem executable: the threaded RTS on every
processor, so that the PDF pipeline's parallel composition (golem-driver
ADR 0002) runs on several OS threads.
-}
module RtsSpec (rtsTests) where

import Data.List (isInfixOf)
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

rtsTests :: TestTree
rtsTests =
  testGroup
    "the runtime of golem"
    [ testCase "golem is linked with the threaded RTS and starts on every processor (-N)" $ do
        (code, out, _) <- readProcessWithExitCode "golem" ["+RTS", "--info", "-RTS"] ""
        (code, filter (`isInfixOf` out) [rtsWay, withN]) @?= (ExitSuccess, [rtsWay, withN])
    ]
  where
    rtsWay = "(\"RTS way\", \"rts_thr\")"
    withN = "(\"Flag -with-rtsopts\", \"-N\")"
