module Main (main) where

import AssembleSpec qualified
import Bibliography0475Spec qualified
import BibliographyFormatsSpec qualified
import BibliographyNamesSpec qualified
import BibliographyRangesSpec qualified
import BibliographySortSpec qualified
import BibliographyStyleSpec qualified
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import IndexSpec qualified
import ListMarkersSpec qualified
import NumberingSpec qualified
import TableNumberSpec qualified
import Test.Tasty

main :: IO ()
main = enterPackageDirectory >> defaultMain (testGroup "golem-assemble" [Bibliography0475Spec.tests, BibliographyRangesSpec.tests, BibliographyFormatsSpec.tests, BibliographyNamesSpec.tests, BibliographySortSpec.tests, BibliographyStyleSpec.tests, AssembleSpec.tests, IndexSpec.tests, ListMarkersSpec.tests, NumberingSpec.tests, TableNumberSpec.tests])
