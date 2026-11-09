{- | The runtime of the golem executable: the threaded RTS on every
processor, so that the PDF pipeline's parallel composition (golem-driver
ADR 0002) runs on several OS threads, with a 64 MB allocation area, so
that the collections of the youngest generation are few (docs/adr/0249).
-}
module RtsSpec (rtsTests) where

import Data.List (isInfixOf, isPrefixOf)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode, readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

rtsTests :: TestTree
rtsTests =
  testGroup
    "the runtime of golem"
    [ testCase "I2: golem is linked with the threaded RTS, -N and -A64m (docs/adr/0249)" $ do
        (code, out, _) <- readProcessWithExitCode "golem" ["+RTS", "--info", "-RTS"] ""
        let ws = maybe [] words (infoValue "Flag -with-rtsopts" out)
        (code, rtsWay `isInfixOf` out, filter (`elem` ws) ["-N", "-A64m"])
          @?= (ExitSuccess, True, ["-N", "-A64m"]),
      -- GHCRTS comes after -with-rtsopts, so the check of the environment
      -- can change the number of capabilities (docs/adr/0050)
      testCase "I3: GHCRTS=-N1 runs golem on one capability" $ usingN "-N1" >>= assertBool "using -N1",
      testCase "I3: GHCRTS=-N2 runs golem on two capabilities" $ usingN "-N2" >>= assertBool "using -N2",
      -- golem is not linked with -rtsopts: the options of the collector
      -- cannot be changed from outside (docs/adr/0050, docs/adr/0249)
      testCase "I4: +RTS -A4m is refused, golem is not linked with -rtsopts" $ do
        (code, _, err) <- readProcessWithExitCode "golem" ["+RTS", "-A4m", "-RTS", "--version"] ""
        (code, "Most RTS options are disabled" `isInfixOf` err) @?= (ExitFailure 1, True)
    ]
  where
    usingN n = do
      env <- filter ((/= "GHCRTS") . fst) <$> getEnvironment
      (_, _, err) <- readCreateProcessWithExitCode (proc "golem" ["+RTS", "-s", "-RTS", "--version"]) {env = Just (("GHCRTS", n) : env)} ""
      pure (("using " <> n <> ")") `isInfixOf` err)
    rtsWay = "(\"RTS way\", \"rts_thr\")"

{- | The value of a field of @+RTS --info@, whose lines are
@,("NAME", "VALUE")@.
-}
infoValue :: String -> String -> Maybe String
infoValue name out = case [rest | l <- lines out, Just rest <- [stripTo (dropWhile (`elem` (" ,[" :: String)) l)]] of
  (v : _) -> Just (takeWhile (/= '"') v)
  [] -> Nothing
  where
    key = "(\"" <> name <> "\", \""
    stripTo l
      | key `isPrefixOf` l = Just (drop (length key) l)
      | otherwise = Nothing
