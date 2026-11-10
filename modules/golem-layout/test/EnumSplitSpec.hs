{- | What the pull requests and the nightly job check of the enumeration
tests (docs/adr ADR 0281, N1 to N3): the nightly job leaves out no
setting of the ADRs of an area, it checks everything the pull requests
check up to as many parts or more, and the pull requests check the default
composition. The depth of the nightly job is that of its variable in
.github/workflows/enum.yml.

The pagination, the ranges that do not break, the marks of citations and
the boundaries inside Latin words combine the same settings at every depth
(their enumerations take no depth but the parts): only their depths
differ, which N2 compares. The line breaking moves settings and checks to
the nightly job by its depth ('lineSettingsAt', 'lineChecksAt').
-}
module EnumSplitSpec (enumSplitTests) where

import AdjustOrderSpec (defaultOrder, ordersAt, staged)
import CiteBreakEnum (citePrDepth)
import ColumnWidthInvariantsSpec (tableBoundsAt, tablePrDepth)
import Data.Char (isDigit, isSpace)
import Data.List (isPrefixOf, isSuffixOf, nub, stripPrefix)
import Data.Maybe (isNothing)
import Data.Set (Set)
import Data.Set qualified as Set
import JoinedWordEnum (joinedPrDepth)
import LineBreakEnum (Setting (..))
import LineBreakInvariantsSpec (Adjust (..), LineSetting, lineChecksAt, lineLimitsAt, lineSettingsAt, linesPrDepth)
import NoBreakEnum (noBreakPrDepth)
import PaginateInvariantsSpec (prDepth)
import Test.Tasty
import Test.Tasty.HUnit

-- | The workflow of the nightly job, from the directory of the package, where the tests run.
enumYml :: FilePath
enumYml = "../../.github/workflows/enum.yml"

-- | Each area: the variable of its depth in the nightly job, and its depth on pull requests.
areas :: [(String, Int)]
areas =
  [ ("GOLEM_ENUM_DEPTH", prDepth),
    -- the keep options (docs/adr/0261), an area of their own (docs/adr ADR 0304)
    ("GOLEM_ENUM_KEEP_DEPTH", prDepth),
    ("GOLEM_ENUM_LINES_DEPTH", linesPrDepth),
    -- the order of line adjustment (docs/adr/0278), at the depth of the line breaking
    ("GOLEM_ENUM_LINES_DEPTH", linesPrDepth),
    ("GOLEM_ENUM_NOBREAK_DEPTH", noBreakPrDepth),
    ("GOLEM_ENUM_CITE_DEPTH", citePrDepth),
    ("GOLEM_ENUM_JOINED_DEPTH", joinedPrDepth),
    ("GOLEM_ENUM_TABLE_DEPTH", tablePrDepth)
  ]

-- | The depth of an area in the nightly job: the one value of its variable in the workflow.
nightlyDepth :: String -> String -> IO Int
nightlyDepth yml var =
  case nub [n | l <- lines yml, Just v <- [stripPrefix (var <> ": ") (dropWhile isSpace l)], let n = filter isDigit v, not (null n)] of
    [n] -> pure (read n)
    ns -> assertFailure (enumYml <> " gives " <> var <> " " <> show (length ns) <> " values, not one")

{- | Every setting the ADRs of the line breaking enumerate, as their
tables give them: strict and loose kinsoku, hanging punctuation,
protrusion, no span and the spans of en, fr (docs/adr ADR 0276) and ja,
the expansion, lines of 2 to 5 em (docs/adr/0209); pulling in first and
balanced, no stretch limit and the limits 0 and 2500 (docs/adr/0274); the
penalty 10000 and 50 of a number and its unit (docs/adr/0275).
-}
allLineSettings :: Set LineSetting
allLineSettings =
  Set.fromList
    [ (Setting s h p l, e, w, Adjust pull limit n)
    | s <- [True, False],
      h <- [False, True],
      p <- [False, True],
      l <- [Nothing, Just "en", Just "fr", Just "ja"],
      e <- [False, True],
      w <- [2 .. 5],
      pull <- [True, False],
      limit <- [Nothing, Just 0, Just 2500],
      n <- [10000, 50]
    ]

-- | The checks the ADRs of the line breaking and of its inline code ask for.
allLineChecks :: [String]
allLineChecks =
  [ "L1 to L13, T1, I4, B2 to B4, R2, R5, R6 on every input",
    "L1 to L13, T1, C1, C2, C4, C6 to C8, J1 to J7, D1 to D5 on every input of code",
    "R1",
    "R7",
    "the normal form",
    "the normal form of code",
    "vertical writing",
    "vertical writing of code"
  ]

{- | Whether a setting is of the default composition, which a user gets
writing no field: pulling in first (docs/adr/0274), no stretch limit, the
penalty 10000 of a number and its unit, and no span (docs/adr ADR 0281,
its section 3).
-}
isDefault :: LineSetting -> Bool
isDefault (s, _, _, a) = isNothing (sLang s) && aPullIn a && isNothing (aLimit a) && aNumberUnit a == 10000

enumSplitTests :: TestTree
enumSplitTests =
  testGroup
    "the split of the enumeration tests between pull requests and the nightly job (docs/adr ADR 0281)"
    [ testCase "N2: the nightly job checks every area up to as many parts as pull requests or more" $ do
        yml <- readFile enumYml
        depths <- mapM (\(var, pr) -> (,) var . (,) pr <$> nightlyDepth yml var) areas
        [d | d@(_, (pr, nightly)) <- depths, nightly < pr] @?= [],
      testCase "N2: every area of the workflow is one of the areas compared" $ do
        yml <- readFile enumYml
        let vars = [key | l <- lines yml, let key = takeWhile (/= ':') (dropWhile isSpace l), "GOLEM_ENUM_" `isPrefixOf` key, "DEPTH" `isSuffixOf` key]
        vars @?= map fst areas,
      testCase "N1: at the depth of the nightly job, the line breaking combines every setting of its ADRs, and runs every check" $ do
        nightly <- nightlyDepth' "GOLEM_ENUM_LINES_DEPTH"
        let got = lineSettingsAt nightly
        (Set.toList (Set.difference allLineSettings got), Set.toList (Set.difference got allLineSettings)) @?= ([], [])
        [c | (c, parts) <- lineChecksAt nightly, parts > 0] @?= allLineChecks,
      testCase "N2: the settings and checks of the line breaking on pull requests are among those of the nightly job, up to as many parts and as wide limits or more" $ do
        nightly <- nightlyDepth' "GOLEM_ENUM_LINES_DEPTH"
        Set.toList (Set.difference (lineSettingsAt linesPrDepth) (lineSettingsAt nightly)) @?= []
        [(c, pr, n) | ((c, pr), (_, n)) <- zip (lineChecksAt linesPrDepth) (lineChecksAt nightly), pr > n] @?= []
        [(c, pr, n) | ((c, pr), (_, n)) <- zip (lineLimitsAt linesPrDepth) (lineLimitsAt nightly), pr > n] @?= [],
      testCase "N3: the pull requests break lines in the default composition: pulling in first, no stretch limit, number-unit-penalty 10000, no span" $
        assertBool "no setting of pull requests is of the default composition" (any isDefault (Set.toList (lineSettingsAt linesPrDepth))),
      testCase "N1, N2, N3: the order of line adjustment checks the three orders of docs/adr/0278 in lines up to 5 em in the nightly job, and the same orders, the default order of style.toml among them, on pull requests, in lines no wider" $ do
        nightly <- nightlyDepth' "GOLEM_ENUM_LINES_DEPTH"
        let (prOrders, prWidth) = ordersAt linesPrDepth
            (nightlyOrders, nightlyWidth) = ordersAt nightly
        (nightlyOrders, nightlyWidth) @?= (staged, 5)
        filter (`notElem` nightlyOrders) prOrders @?= []
        assertBool "the lines of pull requests are wider than those of the nightly job" (prWidth <= nightlyWidth)
        assertBool "pull requests do not check the default order" (defaultOrder `elem` prOrders),
      testCase "N2: the column widths of the nightly job have widths as large and as many columns as those of pull requests or more (docs/adr ADR 0295)" $ do
        nightly <- nightlyDepth' "GOLEM_ENUM_TABLE_DEPTH"
        let ((prK, prN), (prK', prN')) = tableBoundsAt tablePrDepth
            ((k, n), (k', n')) = tableBoundsAt nightly
        assertBool "the nightly job checks fewer inputs of columnWidths than pull requests" (prK <= k && prN <= n)
        assertBool "the nightly job checks fewer inputs of tableColumnWidths than pull requests" (prK' <= k' && prN' <= n'),
      testCase "ADR 0286, its section 4: pull requests check what fits the budgets by the median of four jobs: the span of fr, R1 up to 2 parts and the three orders; balanced stays on the nightly job" $ do
        let pr = Set.toList (lineSettingsAt linesPrDepth)
        assertBool "pull requests do not check the span of fr" (any (\(s, _, _, _) -> sLang s == Just "fr") pr)
        lookup "R1" (lineChecksAt linesPrDepth) @?= Just 2
        fst (ordersAt linesPrDepth) @?= staged
        [a | (_, _, _, a) <- pr, not (aPullIn a)] @?= []
    ]
  where
    nightlyDepth' var = readFile enumYml >>= (`nightlyDepth` var)
