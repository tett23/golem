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
          Left errs -> assertFailure (show errs)
    ]
