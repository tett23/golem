module Main (main) where

import BuiltinSpec qualified
import DeferredSpec qualified
import DiagnosticSitesSpec qualified
import ExprSpec qualified
import FileSpec qualified
import NaturalSpec qualified
import OperatorSpec qualified
import RangeSpec qualified
import RationalSpec qualified
import RegexStyleSpec qualified
import TableSpec qualified
import Test.Tasty

main :: IO ()
main = defaultMain (testGroup "golem-eval" [ExprSpec.tests, FileSpec.tests, RegexStyleSpec.tests, OperatorSpec.tests, DeferredSpec.tests, DiagnosticSitesSpec.tests, BuiltinSpec.tests, TableSpec.tests, RationalSpec.tests, NaturalSpec.tests, RangeSpec.tests])
