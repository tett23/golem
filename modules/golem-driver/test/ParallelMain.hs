module Main (main) where

import ParallelSpec (parallelTests)
import Test.Tasty

main :: IO ()
main = defaultMain parallelTests
