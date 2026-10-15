module Main (main) where

import DeferredSpec qualified
import ExprSpec qualified
import FileSpec qualified
import OperatorSpec qualified
import RegexStyleSpec qualified
import Test.Tasty

main :: IO ()
main = defaultMain (testGroup "golem-eval" [ExprSpec.tests, FileSpec.tests, RegexStyleSpec.tests, OperatorSpec.tests, DeferredSpec.tests])
