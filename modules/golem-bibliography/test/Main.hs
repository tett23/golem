module Main (main) where

import BibliographySpec qualified
import CslSpec qualified
import Test.Tasty

main :: IO ()
main = defaultMain (testGroup "golem-bibliography" [BibliographySpec.tests, CslSpec.tests])
