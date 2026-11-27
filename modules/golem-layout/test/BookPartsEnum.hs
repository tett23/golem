{- | Root ADR 0377 and root ADR 0401 checked on every small input (root
ADR 0204): a filler paragraph, then one retained list item, on pages of
one or two columns of three to five lines, in the grid and in free
placement.
-}
module BookPartsEnum (bookPartsEnumTests) where

import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Paginate
import Golem.Layout.Paginate.Physical
import Golem.Project.Style (KeepParts (..))
import Golem.Syntax (FileId (..), SrcSpan, mkSpan)
import Golem.TestSupport.Enum
import Test.Tasty
import Test.Tasty.HUnit

data Input = Input
  { inColumns :: !Int,
    inLines :: !Int,
    inUnit :: !KeepParts,
    inSecondPage :: !Bool,
    inFiller :: !Int,
    inPart :: !Int
  }
  deriving stock (Show)

data Mode = Grid | Free
  deriving stock (Eq, Show)

-- | Tier k holds the inputs whose item has k lines.
inputs :: Tiers Input
inputs =
  Tiers
    [ [ Input columns capacity unit second filler k
      | columns <- [1, 2],
        capacity <- [3 .. 5],
        k <= 4 * columns * capacity + 1,
        unit <- [KeepColumn, KeepPage, KeepSpread],
        second <- [False, True],
        filler <- [0 .. 2 * columns * capacity]
      ]
    | k <- [0 .. 41]
    ]

source :: SrcSpan
source = mkSpan (FileId 0) 0 1

lineAt :: Int -> LineBox
lineAt i = LineBox i [] [] [] 0

partIds :: Input -> [Int]
partIds i = [100 .. 100 + inPart i - 1]

flowsOf :: Bool -> Input -> [FlowAt position]
flowsOf retained i =
  [FBreak BreakPage | inSecondPage i]
    <> [FParagraph (Keep 1 1 False) (map lineAt [0 .. inFiller i - 1]) | inFiller i > 0]
    <> concat [if retained then [FBookPart (inUnit i) source "list item" (partIds i) body] else body | inPart i > 0]
  where
    body = [FParagraph (Keep 1 1 False) (map lineAt (partIds i))]

-- | Each column: its page, its column, its lines and what it could not meet.
type Columns = [(Int, Int, [Int], [Unmet])]

pagesOf :: Mode -> Input -> (forall position. [FlowAt position]) -> Either String Columns
pagesOf Grid i flows = Right (map summary (paginate (inColumns i) (inLines i) flows))
pagesOf Free i flows = either (Left . show) (Right . map summary) (paginatePhysical cfg flows)
  where
    height = fromIntegral (16 * inLines i)
    cfg = PhysicalSettings 16 10 height height 0 (ColumnSet (inColumns i) 0 0 0) Map.empty Map.empty Map.empty Map.empty Map.empty Nothing Set.empty noAvoid Map.empty

summary :: PageOutAt position -> (Int, Int, [Int], [Unmet])
summary p = (poNumber p, poColumn p, [ident | (_, SLine ident) <- poSlots p], poUnmet p)

positions :: Columns -> Map.Map Int (Int, Int)
positions pages = Map.fromList [(ident, (page, column)) | (page, column, ids, _) <- pages, ident <- ids]

-- | The unit of a physical page: the page, or its spread (2 and 3, 4 and 5).
unitOf :: KeepParts -> Int -> Int
unitOf unit page = case unit of
  KeepSpread -> if page == 1 then 0 else page `div` 2
  _ -> page

-- | Where the item's first line is expected, as the index of a grid line from the first page.
expectedStart :: Input -> (Int, Bool)
expectedStart i
  | inUnit i == KeepColumn = (at, inPart i > inLines i)
  | fitsHere = (at, False)
  | inPart i <= unitLines nextStart = (nextStart, False)
  | atUnitStart = (at, True)
  | otherwise = (nextStart, True)
  where
    perPage = inColumns i * inLines i
    at = (if inSecondPage i then perPage else 0) + inFiller i
    pageOf index = index `div` perPage + 1
    unitAt index = unitOf (inUnit i) (pageOf index)
    fitsHere = unitAt at == unitAt (at + inPart i - 1)
    firstPageOfUnit = case inUnit i of
      KeepSpread -> \u -> if u == 0 then 1 else 2 * u
      _ -> id
    startOfUnit u = (firstPageOfUnit u - 1) * perPage
    atUnitStart = startOfUnit (unitAt at) == at
    nextStart = startOfUnit (unitAt at + 1)
    unitLines index = length (takeWhile ((== unitAt index) . unitAt) [index ..])

violations :: Mode -> Input -> [Violation]
violations mode i = case (pagesOf mode i (flowsOf True i), pagesOf mode i (flowsOf False i)) of
  (Left failure, _) -> [Violation "I3" ("pagination failed: " <> failure)]
  (_, Left failure) -> [Violation "I1" ("plain pagination failed: " <> failure)]
  (Right pages, Right plain) ->
    let placed = positions pages
        ids = [ident | (_, _, slotted, _) <- pages, ident <- slotted]
        notices = [u | (_, _, _, unmet) <- pages, u@SplitBookPart {} <- unmet]
        perPage = inColumns i * inLines i
        at index = (index `div` perPage + 1, (index `mod` perPage) `div` inLines i)
        (start, noticed) = expectedStart i
        expected = Map.fromList (zip (partIds i) (map at [start ..]))
        actual = Map.restrictKeys placed (Map.keysSet expected)
     in [Violation "I3" ("lines lost or repeated: " <> show ids) | sort ids /= [0 .. inFiller i - 1] <> partIds i]
          <> [Violation "I3" ("notices: " <> show notices) | length notices /= (if noticed then 1 else 0)]
          <> [ Violation "I1" "column differs from the plain placement"
             | inUnit i == KeepColumn,
               [(page, column, slotted) | (page, column, slotted, _) <- pages] /= [(page, column, slotted) | (page, column, slotted, _) <- plain]
             ]
          <> [Violation "I2" ("item placed at " <> show actual <> ", expected " <> show expected) | inUnit i /= KeepColumn, actual /= expected]

check :: Mode -> Assertion
check mode = case checkAll 41 inputs (violations mode) of
  Passed n -> assertBool "inputs were enumerated" (n > 0)
  Failed _ input found -> assertFailure (show input <> "\n" <> show found)

bookPartsEnumTests :: TestTree
bookPartsEnumTests =
  testGroup
    "root ADR 0377 and root ADR 0401 on every small input (root ADR 0204)"
    [ testCase "root ADR 0401 I1 I2 I3, root ADR 0377 I1: grid placement of every small item" (check Grid),
      testCase "root ADR 0401 I1 I2 I3, root ADR 0377 I1: free placement of every small item" (check Free)
    ]
