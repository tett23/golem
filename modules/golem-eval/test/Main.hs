module Main (main) where

import DiagnosticSitesSpec qualified
import ExprSpec qualified
import FileSpec qualified
import RegexStyleSpec qualified
import Test.Tasty

main :: IO ()
main = defaultMain (testGroup "golem-eval" [ExprSpec.tests, FileSpec.tests, RegexStyleSpec.tests, DiagnosticSitesSpec.tests])
