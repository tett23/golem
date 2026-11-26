module Main (main) where

import BlockBodySpec qualified
import BuiltinSpec qualified
import CiteSpec qualified
import DeferredSpec qualified
import DiagnosticSitesSpec qualified
import ExceptionsSpec qualified
import ExprSpec qualified
import FileSpec qualified
import FollowOnSpec qualified
import FunctionSpec qualified
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import ImportAliasSpec qualified
import ImportListSpec qualified
import IndexKindSpec qualified
import LangSpec qualified
import LinkSpec qualified
import NaturalSpec qualified
import NoteSpec qualified
import OperatorSpec qualified
import OverrideImportSpec qualified
import ParagraphStyleControlsSpec qualified
import RangeSpec qualified
import RationalSpec qualified
import RegexStyleSpec qualified
import ShySpec qualified
import TableAttributesSpec qualified
import TableSpec qualified
import Test.Tasty
import VarsSpec qualified

main :: IO ()
main = enterPackageDirectory >> defaultMain (testGroup "golem-eval" [ExprSpec.tests, FileSpec.tests, RegexStyleSpec.tests, OperatorSpec.tests, DeferredSpec.tests, DiagnosticSitesSpec.tests, BuiltinSpec.tests, TableSpec.tests, TableAttributesSpec.tests, NoteSpec.tests, CiteSpec.tests, IndexKindSpec.tests, RationalSpec.tests, NaturalSpec.tests, RangeSpec.tests, FunctionSpec.tests, ImportListSpec.tests, ImportAliasSpec.tests, OverrideImportSpec.tests, VarsSpec.tests, LinkSpec.tests, LangSpec.tests, ShySpec.tests, ExceptionsSpec.tests, ParagraphStyleControlsSpec.tests, BlockBodySpec.tests, FollowOnSpec.tests])
