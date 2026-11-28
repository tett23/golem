{-# LANGUAGE GHC2021 #-}

module Main where

import Control.Monad (forM_, replicateM, unless, when)
import Data.List (intercalate)
import Data.Map.Strict qualified as Map
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
  putStrLn "import RoundPayloadStore\nopen BesideStore"
  let patterns = concat [replicateM n [0 :: Int .. 3] | n <- [0 .. 4]]
      render pairs = "([" <> intercalate ", " ["(" <> show key <> ", " <> show value <> ")" | (key, value) <- pairs] <> "] : List (Nat × Nat))"
  forM_ patterns $ \keys -> do
    let pairs = zip keys [1 :: Int ..]
        table = Map.fromList pairs
        source = render pairs
    forM_ [0 :: Int .. 4] $ \key -> do
      let expected = maybe "none" (("some " <>) . show) (Map.lookup key table)
      putStrLn ("example : fromPairs " <> source <> " " <> show key <> " = " <> expected <> " := by decide")
    when (and (zipWith (<) keys (drop 1 keys))) $ do
      unless (Map.toAscList table == pairs) (error "ordered unique pairs lost their payloads")
      putStrLn ("example : readPairs (pairKeys " <> source <> ") (fromPairs " <> source <> ") = " <> source <> " := by decide")
  hPutStrLn stderr "root ADR 0352 I5: 341 tables / 1705 native lookups / 16 ordered payload readbacks"
