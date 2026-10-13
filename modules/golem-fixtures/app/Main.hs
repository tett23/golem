{- | golem-fixtures gutenberg-play INPUT.txt OUTPUT.gm
  golem-fixtures aozora INPUT.txt OUTPUT.gm

Converts a public-domain text of the test fixtures into Golem source
(docs/adr/0023). scripts/fixtures/fetch-public-domain.sh runs it.
-}
module Main (main) where

import Data.ByteString qualified as BS
import Golem.Fixtures (convertBytes, converterNamed)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main =
  getArgs >>= \case
    [name, input, output] | Just conv <- converterNamed name -> do
      src <- BS.readFile input
      either (die' . ((input <> ": ") <>)) (BS.writeFile output) (convertBytes conv src)
    _ -> die' "usage: golem-fixtures (gutenberg-play | aozora) INPUT.txt OUTPUT.gm"

die' :: String -> IO ()
die' msg = hPutStrLn stderr ("golem-fixtures: " <> msg) >> exitFailure
