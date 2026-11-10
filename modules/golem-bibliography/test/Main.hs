module Main (main) where

import BibliographySpec qualified
import CslSpec qualified
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import Test.Tasty

main :: IO ()
main = enterPackageDirectory >> defaultMain (testGroup "golem-bibliography" [BibliographySpec.tests, CslSpec.tests])
