module Main (main) where

import ExprSpec qualified
import FileSpec qualified
import Test.Tasty

main :: IO ()
main = defaultMain (testGroup "golem-eval" [ExprSpec.tests, FileSpec.tests])
