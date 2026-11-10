module Main (main) where

import AstShapeSpec qualified
import CSTSpec qualified
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import LabelSafetySpec qualified
import LowerSpec qualified
import ParserSpec qualified
import SourceSettingsSpec qualified
import SplatEscapeSpec qualified
import Test.Tasty

main :: IO ()
main = enterPackageDirectory >> defaultMain (testGroup "golem-parser" [CSTSpec.tests, ParserSpec.tests, AstShapeSpec.tests, LowerSpec.tests, LabelSafetySpec.tests, SourceSettingsSpec.tests, SplatEscapeSpec.tests])
