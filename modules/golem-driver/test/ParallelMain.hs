module Main (main) where

import ParallelSpec (parallelTests, raceFactor)
import Test.Tasty

main :: IO ()
main = raceFactor >>= defaultMain . parallelTests
