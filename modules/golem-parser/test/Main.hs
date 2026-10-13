module Main (main) where

import CSTSpec qualified
import LabelSafetySpec qualified
import LowerSpec qualified
import ParserSpec qualified
import SourceSettingsSpec qualified
import Test.Tasty

main :: IO ()
main = defaultMain (testGroup "golem-parser" [CSTSpec.tests, ParserSpec.tests, LowerSpec.tests, LabelSafetySpec.tests, SourceSettingsSpec.tests])
