{- | A composed table forced without turning it into a string (docs/adr ADR
0299): I2 and I3, on the boundary inputs of the ADR. The tables are composed
as flowLines composes them, from a one-chapter project with the fake fonts;
the tests are here, not in golem-typeset-test, because a table needs the
evaluation of a project (golem-driver) and golem-typeset-test depends on
neither golem-doc nor golem-layout.
-}
module ForceTableSpec (forceTableTests) where

import Control.Exception (SomeException, evaluate, try)
import Control.Monad (forM, forM_)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Layout.KnuthPlass (Line)
import Golem.Layout.Table (SetCell (..), SetTable (..), TableError (..))
import Golem.Typeset (TableRefusal (..), composedTables, forceTable)
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | What a table composes to, the lines of its notes left out.
type Composed = Either TableRefusal SetTable

{- | The tables of a one-chapter project in their order: each composed
twice, once forced by 'forceTable' and once evaluated in full by show, as
before docs/adr ADR 0299.
-}
forcedTables :: T.Text -> [(FilePath, BS.ByteString)] -> IO [(Either SomeException Composed, Composed)]
forcedTables source files = do
  r <- withMiniInput fakeProvider miniManifest horizontalStyle source files $ \inp geom fonts ->
    -- composed twice, so that the two are evaluated apart
    forM (zip (composedTables inp geom fonts) (composedTables inp geom fonts)) $ \(once, again) -> do
      forced <- try (fmap fst <$> forceTable once)
      let shown = fmap fst again
      _ <- evaluate (length (show shown))
      pure (forced, shown)
  either (assertFailure . show) pure r

-- | I2 and I3 of one input: every table forced without an exception, equal to the one evaluated by show.
holds :: T.Text -> [(FilePath, BS.ByteString)] -> IO [Composed]
holds source files = do
  ts <- forcedTables source files
  assertBool "the input has a table" (not (null ts))
  forM ts $ \(forced, shown) -> case forced of
    Left e -> assertFailure ("forceTable threw " <> show e)
    Right v -> do
      assertBool "the forced table equals the one evaluated by show" (v == shown)
      pure v

-- | The lines of every cell of a set table.
cellLines :: SetTable -> [[Line]]
cellLines st = map scLines (stHeader st <> concat (stRows st))

set :: [Composed] -> IO SetTable
set = \case
  [Right st] -> pure st
  other -> assertFailure ("not one set table: " <> show other)

refusedBy :: [Composed] -> IO TableRefusal
refusedBy = \case
  [Left why] -> pure why
  other -> assertFailure ("not one refused table: " <> show other)

csvOf :: [[T.Text]] -> BS.ByteString
csvOf = TE.encodeUtf8 . T.concat . map (\r -> T.intercalate "," r <> "\n")

-- | n rows of k cells of x, the header row one of them.
grid :: Int -> Int -> BS.ByteString
grid n k = csvOf (replicate n (replicate k "x"))

forceTableTests :: TestTree
forceTableTests =
  testGroup
    "forcing a composed table without show (docs/adr ADR 0299)"
    [ testGroup
        "I3: the forced table equals the table evaluated by show"
        [ testCase "I3: a header row alone, no row of the body" $ do
            st <- holds "| 項目 | 値 |\n|---|---|\n" [] >>= set
            (length (stHeader st), stRows st) @?= (2, []),
          testCase "I3: one cell" $ do
            st <- holds "| あ |\n|---|\n" [] >>= set
            length (cellLines st) @?= 1,
          testCase "I3: a header row of empty cells" $ do
            st <- holds "@table data/t.csv\n" [("data/t.csv", csvOf [["", ""], ["あ", "い"]])] >>= set
            -- the header row of empty cells is not set, only counted (docs/adr/0224)
            map length (cellLines st) @?= [1, 1],
          testCase "I3: an empty cell, a cell of one character" $ do
            st <- holds "| 項目 | 値 |\n|---|---|\n| | あ |\n" [] >>= set
            -- an empty cell is one empty line
            map length (cellLines st) @?= [1, 1, 1, 1],
          testCase "I3: a sentence broken into lines in a cell" $ do
            st <- holds ("| 項目 | 値 |\n|---|---|\n| 幅 | " <> T.replicate 60 "あ" <> " |\n") [] >>= set
            assertBool "the long cell has two lines or more" (maximum (map length (cellLines st)) >= 2),
          testCase "I3: cells with a note and ruby" $ do
            st <- holds "| 項目 | 値 |\n|---|---|\n| 注[note: 注の文。] | [ruby: 漢字 | かんじ] |\n" [] >>= set
            length (cellLines st) @?= 4,
          testCase "I3: columns that fit their widths" $ do
            st <- holds "@column-widths 30% 30%\n| 項目 | 値 |\n|---|---|\n| 幅 | 10 |\n" [] >>= set
            length (stWidths st) @?= 2
        ],
      testGroup
        "I2: a refused table stays refused, and forcing it throws nothing"
        [ localOption hangTimeout $
            testCase "I2: N cells, composed and refused by their widths (G07041)" $
              -- 400 rows of 250 cells: 100,000, the limit itself
              holds "@table data/t.csv\n" [("data/t.csv", grid 400 250)] >>= refusedBy >>= \case
                LayoutRefused es -> assertBool "G07041" (not (null es) && all isColumnsTooWide es)
                other -> assertFailure (show other),
          localOption hangTimeout $
            testCase "I2: N + 1 cells (G07108)" $
              -- 9,091 rows of 11 cells
              holds "@table data/t.csv\n" [("data/t.csv", grid 9091 11)] >>= refusedBy >>= \case
                TooManyCells n -> n @?= 100001
                other -> assertFailure (show other),
          testCase "I2: widths specified wider than the measure (G07114)" $
            holds "@column-widths 50% 51%\n| 項目 | 値 |\n|---|---|\n| 幅 | 10 |\n" [] >>= refusedBy >>= \case
              LayoutRefused [WidthsTooWide {}] -> pure ()
              other -> assertFailure (show other),
          testCase "I2: a width specified narrower than its cells (G07115)" $
            holds "@column-widths 1zw 1zw\n| 項目 | 値段 |\n|---|---|\n| 幅 | 10 |\n" [] >>= refusedBy >>= \case
              LayoutRefused es -> forM_ es $ \case
                ColumnTooNarrow {} -> pure ()
                e -> assertFailure (show e)
              other -> assertFailure (show other)
        ]
    ]
  where
    isColumnsTooWide = \case
      ColumnsTooWide {} -> True
      _ -> False
