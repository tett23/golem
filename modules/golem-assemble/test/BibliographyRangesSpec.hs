module BibliographyRangesSpec (tests) where

import Control.Monad (forM_)
import Data.Text qualified as T
import Golem.Assemble.BibliographyRanges
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "bibliography page ranges"
    [ testCase "root ADR 0470 I6: minimal endpoints reconstruct the original endpoint" $
        forM_ [(a, b) | a <- [0 .. 299], b <- [a .. a + 30]] $ \(a, b) ->
          let written = formatBibliographyRange MinimalPageRange "-" a b
              (start, rest) = T.breakOn "-" written
              end = T.drop 1 rest
              reconstructed = T.take (T.length start - T.length end) start <> end
           in assertEqual (show (a, b)) (T.pack (show b)) reconstructed,
      testCase "root ADR 0470 I6: the NLM example uses the minimal endpoint" $
        formatBibliographyRange MinimalPageRange "-" 284 287 @?= "284-7",
      testCase "root ADR 0470 I6: full ranges retain all endpoint digits" $
        formatBibliographyRange FullPageRange "–" 284 287 @?= "284–287",
      testCase "root ADR 0470 I6: minimal ranges remove all common leading digits" $ do
        formatBibliographyRange MinimalPageRange "-" 100 104 @?= "100-4"
        formatBibliographyRange MinimalPageRange "-" 109 110 @?= "109-10"
        formatBibliographyRange MinimalPageRange "-" 1000 1004 @?= "1000-4",
      testCase "root ADR 0470 I6: different leading digits retain the full endpoint" $
        formatBibliographyRange MinimalPageRange "–" 199 203 @?= "199–203",
      testCase "root ADR 0470 I6: a change in the number of digits retains the full endpoint" $
        formatBibliographyRange MinimalPageRange "–" 999 1002 @?= "999–1002",
      testCase "root ADR 0470 I6: equal or descending endpoints retain their full values" $ do
        formatBibliographyRange MinimalPageRange "-" 503 503 @?= "503-503"
        formatBibliographyRange MinimalPageRange "-" 287 284 @?= "287-284",
      testCase "root ADR 0470 I6: the supplied range delimiter is used literally" $ do
        formatBibliographyRange MinimalPageRange " to " 284 287 @?= "284 to 7"
        formatBibliographyRange FullPageRange "" 284 287 @?= "284287",
      testCase "root ADR 0470 I6: endpoints above the machine integer width retain their digits" $
        formatBibliographyRange MinimalPageRange "–" 100000000000000000000000 100000000000000000000005 @?= "100000000000000000000000–5"
    ]
