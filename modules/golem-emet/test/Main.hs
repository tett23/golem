module Main (main) where

import ExportSpec (exportTests)
import FmtSpec (fmtTests)
import LanguageSpec (languageTests)
import LintSpec (lintTests)
import RequirementSpec (requirementTests)
import Test.Tasty

main :: IO ()
main = defaultMain (testGroup "golem-emet" [languageTests, requirementTests, exportTests, lintTests, fmtTests])
