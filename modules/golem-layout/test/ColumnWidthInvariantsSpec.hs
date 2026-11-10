-- the enumerations are built in the tests that check them, and must not
-- be floated out into values that live as long as the program: those
-- would hold every input checked (docs/adr/0208)
{-# OPTIONS_GHC -fno-full-laziness -fno-cse #-}

{- | The widths of the columns of a table (docs/adr ADR 0295) on every
small input: C1 to C6 on 'columnWidths', every column a (minimum,
natural) width with 0 <= lo <= hi <= K and the width W from 0 to n K + 1;
C7 and C8 on 'tableColumnWidths', each column also auto or a width of 0
to K written ('ColumnAbs'), the columns sharing W. Tier n holds the
inputs of n columns.

The bounds are those of GOLEM_ENUM_TABLE_DEPTH, or 'tablePrDepth' on pull
requests ('tableBoundsAt').
-}
module ColumnWidthInvariantsSpec
  ( columnWidthInvariantTests,
    tablePrDepth,
    tableBoundsAt,
    CwInput (..),
    cwViolations,
  )
where

import Data.Maybe (catMaybes, isJust)
import Golem.Doc.IR (ColumnWidth (..))
import Golem.Layout.KnuthPlass (Sp (..))
import Golem.Layout.Table
import Golem.TestSupport.Enum
import System.Environment (lookupEnv)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Read (readMaybe)

-- | An input of 'columnWidths': the width available and the (minimum, natural) width of each column.
data CwInput = CwInput {cwWidth :: !Sp, cwCols :: ![(Sp, Sp)]}
  deriving stock (Eq, Show)

-- | An input of 'tableColumnWidths': the width the columns share, the width written for each column and its (minimum, natural) width.
data TcwInput = TcwInput {tcwWidth :: !Sp, tcwSpecs :: ![ColumnWidth], tcwCols :: ![(Sp, Sp)]}
  deriving stock (Eq, Show)

clampTo :: Sp -> (Sp, Sp) -> Sp
clampTo c (lo, hi) = max lo (min c hi)

{- | The widths of the rule of docs/adr ADR 0295 found by the naive
search (C5): the largest level C* from 0 to the largest natural width
whose widths fit, each column clamped to it, and the remainder 1sp to
each of the first columns at the level (lo <= C* < hi).
-}
naiveWidths :: Sp -> [(Sp, Sp)] -> [Sp]
naiveWidths w cols =
  let level = last (0 : [c | c <- map Sp [0 .. unSp (maximum (0 : map snd cols))], sum (map (clampTo c) cols) <= w])
      rest = w - sum (map (clampTo level) cols)
      atLevel = [lo <= level && level < hi | (lo, hi) <- cols]
      ranks = scanl (+) 0 [if a then 1 else 0 | a <- atLevel]
   in [clampTo level c + (if a && k < rest then 1 else 0) | (c, a, k) <- zip3 cols atLevel ranks]

{- | C1 to C6 of an input, on the widths a function gives ('columnWidths'
in the enumeration; another one in the predicate tests).
-}
cwViolations :: (Sp -> [(Sp, Sp)] -> Either TableError [Sp]) -> CwInput -> [Violation]
cwViolations f (CwInput w cols) =
  concat
    [ [Violation "C1" ("the minimum widths add up to " <> show lo <> " for the width " <> show w <> ", and the result is " <> show r) | c1],
      [Violation "C2" ("the natural widths fit, and the result is " <> show r) | hi <= w, r /= Right (map snd cols)],
      [Violation "C3" ("the widths do not add up to the width: " <> show r) | lo <= w, w < hi, either (const True) ((/= w) . sum) r],
      [Violation "C4" ("a width is not between its minimum and natural widths: " <> show ws) | Right ws <- [r], length ws /= length cols || or [x < mn || x > nat | ((mn, nat), x) <- zip cols ws]],
      [Violation "C5" ("the widths are " <> show r <> ", the naive search gives " <> show naive) | lo <= w, w < hi, r /= Right naive],
      [ Violation "C6" ("the width " <> show (w + 1) <> " gives " <> show next <> ", narrower than " <> show ws <> " at " <> show w)
      | Right ws <- [r],
        Right next <- [f (w + 1) cols],
        or (zipWith (>) ws next) || length ws /= length next
      ]
    ]
  where
    r = f w cols
    lo = sum (map fst cols)
    hi = sum (map snd cols)
    naive = naiveWidths w cols
    c1 = case r of
      Left e -> lo <= w || e /= ColumnsTooWide lo w
      Right _ -> lo > w

{- | C7 and C8 of an input, on the widths a function gives
('tableColumnWidths' in the enumeration; another one in the predicate
tests).
-}
tcwViolations :: (Sp -> Sp -> [ColumnWidth] -> [(Sp, Sp)] -> Either [TableError] [Sp]) -> TcwInput -> [Violation]
tcwViolations f (TcwInput w specs cols) =
  case r of
    Left errs
      | not (null written) -> [Violation "C8" ("the errors are " <> show errs <> ", not " <> show written) | errs /= written]
      | otherwise -> [Violation "C8" ("the errors are " <> show errs <> ", not " <> show autoErr) | errs /= autoErr || null errs]
    Right ws
      | not (null written) -> [Violation "C8" ("the widths are " <> show ws <> ", not the errors " <> show written)]
      | otherwise ->
          [Violation "C8" ("the widths are " <> show ws <> ", not " <> show autoErr) | not (null autoErr)]
            <> [Violation "C7" ("a written width is not its column's: " <> show ws) | length ws /= length cols || or [x /= y | (Just y, x) <- zip fixed ws]]
            <> [Violation "C7" ("the auto columns are " <> show autoWs <> ", columnWidths gives " <> show (columnWidths rest autos)) | Right autoWs /= columnWidths rest autos]
      where
        autoWs = [x | (Nothing, x) <- zip fixed ws]
  where
    r = f w 1 specs cols
    fixed = map (\case ColumnAbs x -> Just x; _ -> Nothing) specs
    fixedSum = sum (catMaybes fixed)
    rest = w - fixedSum
    autos = [c | (Nothing, c) <- zip fixed cols]
    lo = sum (map fst autos)
    written =
      [WidthsTooWide fixedSum w | any isJust fixed, fixedSum > w]
        <> [ColumnTooNarrow i x mn | (i, Just x, (mn, _)) <- zip3 [0 ..] fixed cols, x < mn]
    autoErr = [ColumnsTooWide lo rest | lo > rest]

-- | The columns of widths up to k: 0 <= lo <= hi <= k.
columnsUpTo :: Int -> [(Sp, Sp)]
columnsUpTo k = [(Sp lo, Sp hi) | hi <- [0 .. toInteger k], lo <- [0 .. hi]]

-- | Every input of 'columnWidths' of up to n columns of widths up to k, tier n holding those of n columns.
cwInputs :: (Int, Int) -> Tiers CwInput
cwInputs (k, n) =
  Tiers
    ( []
        : [ [CwInput (Sp w) cols | cols <- mapM (const (columnsUpTo k)) [1 .. m], w <- [0 .. toInteger (m * k + 1)]]
          | m <- [1 .. n]
          ]
    )

-- | Every input of 'tableColumnWidths' of up to n columns of widths up to k, each auto or written 0 to k.
tcwInputs :: (Int, Int) -> Tiers TcwInput
tcwInputs (k, n) =
  Tiers
    ( []
        : [ [ TcwInput (Sp w) (map fst cs) (map snd cs)
            | cs <- mapM (const [(s, c) | s <- ColumnAuto : [ColumnAbs (Sp x) | x <- [0 .. toInteger k]], c <- columnsUpTo k]) [1 .. m],
              w <- [0 .. toInteger (m * k + 1)]
            ]
          | m <- [1 .. n]
          ]
    )

{- | The bounds (the largest width K, the most columns n) at a depth: of
'columnWidths' K = depth and n = depth − 1, of 'tableColumnWidths' K =
depth − 1 and n = 3, n at least 1. The pull requests check 'tablePrDepth'
4, (4, 3) and (3, 3); the nightly job 5, (5, 4) and (4, 3) (docs/adr ADR
0295, its section 2).
-}
tableBoundsAt :: Int -> ((Int, Int), (Int, Int))
tableBoundsAt d = ((d, max 1 (d - 1)), (max 0 (d - 1), 3))

-- | The depth of pull requests.
tablePrDepth :: Int
tablePrDepth = 4

-- | GOLEM_ENUM_TABLE_DEPTH, or 'tablePrDepth' on pull requests.
depthOf :: IO Int
depthOf =
  lookupEnv "GOLEM_ENUM_TABLE_DEPTH" >>= \case
    Nothing -> pure tablePrDepth
    Just "" -> pure tablePrDepth
    Just s -> case readMaybe s of
      Just n | n >= 1 -> pure n
      _ -> assertFailure ("GOLEM_ENUM_TABLE_DEPTH is not a whole number of 1 or more: " <> show s)

report :: (Show a) => Result a -> Assertion
report = \case
  Failed k i vs -> assertFailure ("the smallest input that breaks an invariant has " <> show k <> " columns: " <> show i <> "\n" <> unlines [violationRule v <> ": " <> violationDetail v | v <- vs])
  Passed _ -> pure ()

columnWidthInvariantTests :: TestTree
columnWidthInvariantTests =
  testGroup
    "the widths of the columns of a table on every small input (docs/adr ADR 0295)"
    [ testCase "C1 to C6 hold for every input of columnWidths up to GOLEM_ENUM_TABLE_DEPTH" $ do
        ((k, n), _) <- tableBoundsAt <$> depthOf
        report (checkAllPar n (cwInputs (k, n)) (cwViolations columnWidths)),
      testCase "C7 and C8 hold for every input of tableColumnWidths up to GOLEM_ENUM_TABLE_DEPTH" $ do
        (_, (k, n)) <- tableBoundsAt <$> depthOf
        report (checkAllPar n (tcwInputs (k, n)) (tcwViolations tableColumnWidths)),
      testCase "C5, C6: a predicate test, the remainder to the first column short of its natural width breaks both on (1, 2), (0, 1), (0, 1)" $ do
        let cols = [(1, 2), (0, 1), (0, 1)]
            before w _ = Right (if w == 2 then [2, 0, 0] else [1, 1, 1])
        map violationRule (cwViolations before (CwInput 2 cols)) @?= ["C5", "C6"],
      testCase "C5: the naive search gives the remainder to the columns at the level only" $ do
        naiveWidths 2 [(1, 2), (0, 1), (0, 1)] @?= [1, 1, 0]
        naiveWidths 10 [(0, 9), (0, 9), (0, 9)] @?= [4, 3, 3],
      testCase "C8: a predicate test, an error of the auto columns besides a written width too narrow is a violation" $
        map violationRule (tcwViolations (\_ _ _ _ -> Left [ColumnTooNarrow 0 0 1, ColumnsTooWide 1 0]) (TcwInput 0 [ColumnAbs 0, ColumnAuto] [(1, 1), (1, 1)])) @?= ["C8"],
      testCase "C7: a predicate test, a written width not given to its column is a violation" $
        map violationRule (tcwViolations (\_ _ _ _ -> Right [1, 1]) (TcwInput 3 [ColumnAbs 2, ColumnAuto] [(0, 2), (0, 1)])) @?= ["C7"],
      testCase "the bounds of pull requests and of the nightly job are those of the ADR" $ do
        tableBoundsAt tablePrDepth @?= ((4, 3), (3, 3))
        tableBoundsAt 5 @?= ((5, 4), (4, 3))
    ]
