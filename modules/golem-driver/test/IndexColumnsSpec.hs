{- | The index columns after @page-lines in the PDF (root ADR 0025, root
ADR 0030): the switch counts only the lines of the type area, so the
columns of the index stay inside it and an index heading stays with its
first entry.
-}
module IndexColumnsSpec (indexColumnsTests) where

import Data.Maybe (listToMaybe)
import Data.Text qualified as T
import Golem.Layout.Paginate (ColumnSetAt (..), PageOutAt (..))
import Golem.Length (Sp (..))
import Golem.Typeset (PdfLayout (..))
import Support
import Test.Tasty
import Test.Tasty.HUnit

indexColumnsTests :: TestTree
indexColumnsTests =
  testGroup
    "the index columns after page-lines in the PDF (root ADR 0025, root ADR 0030)"
    [ testCase "root ADR 0025: after page-lines +3 and 12 lines on a page of 10, every index line is inside the type area and the heading keeps its first entry" $ do
        let style = replaceIn "lines = 30" "lines = 10" horizontalStyle <> "\n[index]\ncolumns = 2\n"
            source = T.unlines ("@page-lines +3\n" : ["本文の行" <> n <> "[index reading=あ" <> n <> ": 語あ" <> n <> "]。\n" | k <- [1 .. 12 :: Int], let n = T.pack (show k)]) <> "@index\n"
            -- the line pitch of horizontalStyle, 15pt
            pitch = Sp (15 * 65536)
        result <- layoutMiniWith miniManifest (withBodyFont style) source fakeFontFiles
        case result of
          Right (_, pl) -> do
            let index = [p | p <- plPages pl, csColumns (poColumnSet p) == 2]
                outside = [(poNumber p, poColumn p, at) | p <- index, (at, _) <- poSlots p, at >= 10 * pitch]
            assertBool "the index has columns" (not (null index))
            outside @?= []
            -- the first column of the index holds the heading and its first entry
            assertBool (show (map poSlots index)) (maybe False ((>= 2) . length . poSlots) (listToMaybe index))
          Left errs -> assertFailure (show errs),
      testCase "root ADR 0441 I1, I2: after page-lines -3, a line and a note of two, no index line on the page of the switch reaches the separator or the note" $ do
        let style = replaceIn "lines = 30" "lines = 10" horizontalStyle <> "\n[index]\ncolumns = 2\n"
            marks = T.concat ["[index reading=あ" <> n <> ": 語あ" <> n <> "]" | k <- [1 .. 12 :: Int], let n = T.pack (show k)]
            source = "@page-lines -3\n\n本文[note: " <> T.replicate 20 "注" <> "]" <> marks <> "。\n\n@index\n"
            pitch = Sp (15 * 65536)
        result <- layoutMiniWith miniManifest (withBodyFont style) source fakeFontFiles
        case result of
          Right (_, pl) -> case [p | p <- plPages pl, poNumber p == 1, csColumns (poColumnSet p) == 1] of
            body : _ -> do
              let notes = sum [n | (_, _, n) <- poFootnotes body]
                  -- the separator takes a line at most
                  end = min (10 * pitch) (poLines body - fromIntegral (notes + 1) * pitch)
                  index = [at | p <- plPages pl, poNumber p == 1, csColumns (poColumnSet p) == 2, (at, _) <- poSlots p]
              assertBool ("a note of two lines: " <> show (poFootnotes body)) (notes == 2)
              assertBool ("the index starts on the page: " <> show index) (not (null index))
              assertBool (show (poLines body, notes, index)) (all (\at -> at + pitch <= end) index)
            [] -> assertFailure "no column of the body on page 1"
          Left errs -> assertFailure (show errs)
    ]
