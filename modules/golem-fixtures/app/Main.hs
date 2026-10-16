{- | golem-fixtures gutenberg-play INPUT.txt OUTPUT.gm
  golem-fixtures gutenberg-text [OPTION...] INPUT.txt OUTPUT.gm
  golem-fixtures aozora INPUT.txt OUTPUT.gm
  golem-fixtures aozora-prose INPUT.txt OUTPUT.gm
  golem-fixtures aozora-verse INPUT.txt OUTPUT.gm

Converts a public-domain text of the test fixtures into Golem source
(docs/adr/0023, docs/adr/0026). scripts/fixtures/fetch-public-domain.sh runs
it.
-}
module Main (main) where

import Data.ByteString qualified as BS
import Golem.Fixtures (convertBytes, parseArgs)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, hSetEncoding, stderr, utf8)

main :: IO ()
main =
  -- stderr is UTF-8 whatever the locale (docs/adr/0002-determinism.md)
  hSetEncoding stderr utf8 >> getArgs >>= \args -> case parseArgs args of
    Right (conv, input, output) -> do
      src <- BS.readFile input
      either (die' . ((input <> ": ") <>)) (BS.writeFile output) (convertBytes conv src)
    Left err ->
      die'
        ( err
            <> "\nusage: golem-fixtures (gutenberg-play | aozora | aozora-prose | aozora-verse) INPUT.txt OUTPUT.gm"
            <> "\n       golem-fixtures gutenberg-text [--start TEXT] [--end TEXT] [--heading PREFIX]... [--caps-heading N]"
            <> " [--numbered-headings] [--speakers] [--verse] [--two-columns] [--notes MARKER] [--bold-equals] INPUT.txt OUTPUT.gm"
        )

die' :: String -> IO ()
die' msg = hPutStrLn stderr ("golem-fixtures: " <> msg) >> exitFailure
