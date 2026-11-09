{- | Footnotes are split over two columns only when they do not fit any
column (docs/adr/0263, I6): the pagination sees a note as its grid lines
alone, so the paragraphs of its body change nothing of it.
-}
module NoteSplitSpec (noteSplitTests) where

import Control.Monad (forM_, unless)
import Data.List (nub)
import Golem.Layout.Paginate
import Golem.Syntax (FileId (..), mkSpan)
import Test.Tasty
import Test.Tasty.HUnit

noteSplitTests :: TestTree
noteSplitTests =
  testGroup
    "footnotes of several paragraphs (docs/adr/0263)"
    [ testCase "I6: a note goes over two columns only when its lines, its marked line and the separator do not fit a column" $
        forM_ [(c, lead, k) | c <- [3 .. 8], lead <- [0 .. c], k <- [1 .. c + 1]] $ \(c, lead, k) -> do
          let nid = NoteId (mkSpan (FileId 0) 900 901) 0
              before = [FParagraph [LineBox i [] [] [] 0 | i <- [0 .. lead - 1]] | lead > 0]
              noted = FParagraph [LineBox 100 [NoteBody nid k] [] [] 0, LineBox 101 [] [] [] 0]
              ps = paginate 1 c (before <> [noted])
              columns = nub [(poNumber p, poColumn p) | p <- ps, (n, _, _) <- poFootnotes p, n == nid]
              shown = sum [m | p <- ps, (n, _, m) <- poFootnotes p, n == nid]
          assertEqual (show (c, lead, k)) k shown
          unless (length columns <= 1) $
            assertBool (show (c, lead, k, columns)) (1 + 1 + k > c)
    ]
