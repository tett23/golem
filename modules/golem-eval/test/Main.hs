module Main (main) where

import BuiltinSpec qualified
import DeferredSpec qualified
import DiagnosticSitesSpec qualified
import ExceptionsSpec qualified
import ExprSpec qualified
import FileSpec qualified
import FunctionSpec qualified
import LangSpec qualified
import LinkSpec qualified
import NaturalSpec qualified
import CiteSpec qualified
import NoteSpec qualified
import OperatorSpec qualified
import RangeSpec qualified
import RationalSpec qualified
import RegexStyleSpec qualified
import ShySpec qualified
import TableAttributesSpec qualified
import TableSpec qualified
import Test.Tasty
import VarsSpec qualified

main :: IO ()
main = defaultMain (testGroup "golem-eval" [ExprSpec.tests, FileSpec.tests, RegexStyleSpec.tests, OperatorSpec.tests, DeferredSpec.tests, DiagnosticSitesSpec.tests, BuiltinSpec.tests, TableSpec.tests, TableAttributesSpec.tests, NoteSpec.tests, CiteSpec.tests, RationalSpec.tests, NaturalSpec.tests, RangeSpec.tests, FunctionSpec.tests, VarsSpec.tests, LinkSpec.tests, LangSpec.tests, ShySpec.tests, ExceptionsSpec.tests])
