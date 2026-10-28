module Main (main) where

import LengthSpec qualified
import Test.Tasty

main :: IO ()
main = defaultMain LengthSpec.tests
