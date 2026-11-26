{- | The pagination of the blocks that cannot be shortened off the areas
of the frames of wrap around (root ADR 0456).
-}
module AvoidSpec (avoidTests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Golem.Layout.Code (CodeGeometry (..))
import Golem.Layout.Paginate
import Golem.Layout.Paginate.Physical
import Golem.Length (Sp (..))
import Test.Tasty
import Test.Tasty.HUnit

line :: Int -> LineBox
line i = LineBox i [] [] [] 0

-- | One column of n grid lines, the blocks kept off the areas on page 1.
grid :: Int -> [(Int, Int)] -> [Flow] -> [PageOut]
grid n areas = paginateAvoiding (\page _ _ _ -> if page == 1 then areas else []) Set.empty maxBound 1 (ColumnSet 1 0 0 0) n

-- | The slots of page 1.
firstPage :: [PageOutAt position] -> [(position, Slotted)]
firstPage pages = concat [poSlots p | p <- pages, poNumber p == 1]

-- | A paragraph of k lines from id i.
para :: Int -> Int -> Flow
para i k = FParagraph defaultKeep (map line [i .. i + k - 1])

-- | A code block of rows of one grid line each, from id i.
codeOf :: Int -> Int -> Flow
codeOf i k = FCode (CodeGeometry 10 10 10 10 0) 0 1 False (map line [i .. i + k - 1])

-- | One column of 160 sp, a line of 16 sp, the blocks kept off the areas on page 1.
free :: [(Sp, Sp)] -> PhysicalSettings
free areas = PhysicalSettings 16 10 160 160 0 (ColumnSet 1 0 0 0) Map.empty Map.empty Map.empty Map.empty Map.empty Nothing Set.empty (\page _ _ _ -> if page == 1 then areas else [])

avoidTests :: TestTree
avoidTests =
  testGroup
    "blocks off the frames of wrap around (root ADR 0456)"
    [ testCase "root ADR 0456 I3: a figure over an area starts at its end" $
        firstPage (grid 20 [(3, 6)] [para 0 2, FFigure 100 3 [] []]) @?= [(0, SLine 0), (1, SLine 1), (6, SFigure 100)],
      testCase "root ADR 0456 I5: a figure that ends before an area does not move" $
        firstPage (grid 20 [(5, 8)] [para 0 2, FFigure 100 3 [] []]) @?= [(0, SLine 0), (1, SLine 1), (2, SFigure 100)],
      testCase "root ADR 0456 I3: a table whose header row and first row reach an area starts past it, without the space before it" $
        firstPage (grid 20 [(3, 6)] [para 0 2, FTable 50 1 [line 10] [[line 20], [line 21]] [] False]) @?= [(0, SLine 0), (1, SLine 1), (6, SLine 10), (7, SLine 20), (8, SLine 21)],
      testCase "root ADR 0456 I1: a table broken by an area goes on past it without its header row" $ do
        let pages = grid 20 [(5, 8)] [para 0 1, FTable 50 1 [line 10] [[line 20], [line 21], [line 22], [line 23]] [] False]
        firstPage pages @?= [(0, SLine 0), (2, SLine 10), (3, SLine 20), (4, SLine 21), (8, SLine 22), (9, SLine 23)]
        concat [poTables p | p <- pages, poNumber p == 1] @?= [TableSegment 50 2 (Just 2) 4, TableSegment 50 8 Nothing 9],
      testCase "root ADR 0456 I1: a code block broken by an area goes on past it" $
        firstPage (grid 20 [(4, 7)] [para 0 2, codeOf 10 5]) @?= [(0, SLine 0), (1, SLine 1), (2, SCode 10 2 2), (7, SCode 12 3 3)],
      testCase "root ADR 0456 I7: a figure that fits the column but no place off the areas is left out, and the rest is placed" $ do
        let pages = grid 10 [(2, 5)] [FFigure 100 6 [] [], para 0 2]
        [u | p <- pages, u <- poUnmet p] @?= [UnplacedBlock 100]
        [s | p <- pages, (_, s) <- poSlots p] @?= [SLine 0, SLine 1],
      testCase "root ADR 0456 I7: a figure that does not fit the column without the areas either is placed as before" $
        [u | p <- grid 5 [(2, 3)] [FFigure 100 6 [] []], u <- poUnmet p] @?= [],
      testCase "root ADR 0456 I3: a table of free placement starts at the end of the area" $
        fmap firstPage (paginatePhysical (free [(Sp 20, Sp 50)]) [FParagraph defaultKeep [line 0], FTable 50 16 [line 10] [[line 20]] [] False])
          @?= Right [(0, SLine 0), (50, SLine 10), (66, SLine 20)],
      testCase "root ADR 0456 I3: a figure of free placement starts at the end of the area" $
        fmap firstPage (paginatePhysical (free [(Sp 20, Sp 50)]) [FParagraph defaultKeep [line 0], FFigure 100 32 [] []])
          @?= Right [(0, SLine 0), (50, SFigure 100)]
    ]
