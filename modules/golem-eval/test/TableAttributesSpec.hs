-- | The attributes of a table: @caption, @nonumber, @style and @column-widths (docs/adr/0262).
module TableAttributesSpec (tests) where

import Data.Bifunctor (first)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Parser.SourceSettings (ParagraphSeparator (..), SourceSettings (..))
import Golem.Project.Style (LineBreaks (..), defaultStyle, paraLineBreaks)
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

ctx :: EvalContext
ctx =
  baseCtx
    { ctxParaStyles = Map.insert "small" JoinLines (paraLineBreaks defaultStyle),
      ctxAssets = Map.fromList [("t.csv", AssetText (FileId 5) "a,b\n1,2\n")]
    }

-- | The tables of a source, with the codes of the diagnostics.
run :: EvalContext -> Text -> ([Table], [Text])
run c src =
  let (ds, r) = evalSource c src
   in ([t | TableBlock t <- resultBodies r], map diagCodeText ds)

-- | A `|` table and the same as @table, after the attribute lines.
both :: Text -> [Text]
both attrs = [attrs <> "| a | b |\n|---|---|\n| 1 | 2 |\n", attrs <> "@table t.csv\n"]

-- | The fields the attributes set, without spans.
fields :: Table -> ([ColumnWidth], Maybe [Text], Bool, Maybe Text)
fields t = (tableWidths t, map plain <$> tableCaption t, tableNoNumber t, tableStyle t)
  where
    plain = \case
      Text _ x -> x
      _ -> "?"

tests :: TestTree
tests =
  testGroup
    "the attributes of tables (docs/adr/0262)"
    [ testCase "@caption, @nonumber, @style and @column-widths become fields of a | table and of @table" $
        mapM_
          (\src -> first (map fields) (run ctx src) @?= ([([ColumnZw 8, ColumnAuto], Just ["出力の形式"], True, Just "small")], []))
          (both "@caption 出力の形式\n@nonumber\n@style small\n@column-widths 8zw auto\n"),
      testCase "a table without attributes has no widths, caption or style" $
        mapM_ (\src -> first (map fields) (run ctx src) @?= ([([], Nothing, False, Nothing)], [])) (both ""),
      testCase "@style table is the built-in table, Nothing" $
        first (map fields) (run ctx "@style table\n| a |\n|---|\n| 1 |\n") @?= ([([], Nothing, False, Nothing)], []),
      testCase "one value of @column-widths is every column's; the values in mm, pt, Q, H, in, zw and %" $ do
        (map tableWidths . fst . run ctx) "@column-widths 30%\n| a | b |\n|---|---|\n| 1 | 2 |\n" @?= [[ColumnPercent 30, ColumnPercent 30]]
        (map tableWidths . fst . run ctx) "@column-widths 2.5zw auto\n| a | b |\n|---|---|\n| 1 | 2 |\n" @?= [[ColumnZw 2.5, ColumnAuto]]
        (map (map isAbs . tableWidths) . fst . run ctx) "@column-widths 10mm 72pt\n| a | b |\n|---|---|\n| 1 | 2 |\n" @?= [[True, True]],
      testCase "G02135 at each value of @column-widths that is not a width, and every column auto" $ do
        first (map tableWidths) (run ctx "@column-widths wide 0zw\n| a | b |\n|---|---|\n| 1 | 2 |\n") @?= ([[]], ["G02135", "G02135"])
        snd (run ctx "@column-widths [= 3] auto\n| a | b |\n|---|---|\n| 1 | 2 |\n") @?= ["G02135"],
      testCase "G02136 when the values are neither one nor as many as the columns" $
        mapM_
          (\ws -> first (map tableWidths) (run ctx ("@column-widths " <> ws <> "\n| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |\n")) @?= ([[]], ["G02136"]))
          ["auto auto", "auto auto auto auto"],
      testCase "@column-widths on a paragraph is G02013" $
        snd (run ctx "@column-widths auto\n本文\n") @?= ["G02013"],
      testCase "@nonumber on a table without a caption is G02134, and the table has no nonumber" $
        mapM_ (\src -> first (map tableNoNumber) (run ctx src) @?= ([False], ["G02134"])) (both "@nonumber\n"),
      testCase "@caption without text is G02069" $
        snd (run ctx "@caption\n| a |\n|---|\n| 1 |\n") @?= ["G02069"],
      testCase "an undefined paragraph style is G02047, and the table has the built-in table" $
        first (map tableStyle) (run ctx "@style nothing\n| a |\n|---|\n| 1 |\n") @?= ([Nothing], ["G02047"]),
      testCase "in the line style the attributes go to the whole table" $ do
        let lineCtx = ctx {ctxSource = SourceSettings LineSeparated}
        first (map fields) (run lineCtx "@caption 表\n@style small\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n") @?= ([([], Just ["表"], False, Just "small")], [])
        (map (length . tableRows) . fst . run lineCtx) "@caption 表\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n" @?= [2],
      testCase "I10: the diagnostics of the attributes keep the order of the lines" $ do
        let src = "@nonumber\n@style nothing\n@column-widths x auto auto\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        snd (run ctx src) @?= snd (run ctx src)
        snd (run ctx src) @?= ["G02047", "G02135", "G02134"]
    ]
  where
    isAbs = \case
      ColumnAbs _ -> True
      _ -> False
