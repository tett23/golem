module Main (main) where

import FmtSpec (fmtTests)
import LanguageSpec (languageTests)
import Test.Tasty

main :: IO ()
main = defaultMain (testGroup "golem-gmx" [languageTests, fmtTests])
