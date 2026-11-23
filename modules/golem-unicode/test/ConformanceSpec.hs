{- | The conformance tests of Unicode 17.0.0 for the grapheme cluster and
word boundaries (docs/adr ADR 0411 I1, I2): every data line of
GraphemeBreakTest-17.0.0.txt and WordBreakTest-17.0.0.txt.
-}
module ConformanceSpec (tests) where

import Data.Char (chr)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Unicode.Grapheme (graphemeClusters)
import Golem.Unicode.Word (wordSegments)
import Numeric (readHex)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "conformance (Unicode 17.0.0)"
    [ testCase "root ADR 0411 I1: graphemeClusters splits every line of GraphemeBreakTest-17.0.0.txt where the line breaks" $
        conformance "test/data/GraphemeBreakTest-17.0.0.txt" 766 graphemeClusters,
      testCase "root ADR 0411 I2: wordSegments splits every line of WordBreakTest-17.0.0.txt where the line breaks" $
        conformance "test/data/WordBreakTest-17.0.0.txt" 1944 wordSegments
    ]

-- | Checks every data line of a test file against a segmentation.
conformance :: FilePath -> Int -> (Text -> [Text]) -> Assertion
conformance path count segment = do
  cases <- concatMap parseLine . T.lines <$> TIO.readFile path
  length cases @?= count
  let failures = [(i, expected, segment (T.concat expected)) | (i, expected) <- zip [1 :: Int ..] cases, segment (T.concat expected) /= expected]
  case failures of
    [] -> pure ()
    _ ->
      assertFailure
        ( show (length failures)
            <> " of "
            <> show count
            <> " lines differ; the first ones (line, expected, actual):\n"
            <> unlines [show f | f <- take 10 failures]
        )

{- | The segments of a data line (@÷ 0061 × 0308 ÷ 0062 ÷@), or nothing for
a comment or an empty line.
-}
parseLine :: Text -> [[Text]]
parseLine line = case T.words (T.takeWhile (/= '#') line) of
  [] -> []
  ws -> [go [] [] ws]
  where
    go segs cur = \case
      [] -> reverse (flush segs cur)
      ("÷" : rest) -> go (flush segs cur) [] rest
      ("×" : rest) -> go segs cur rest
      (w : rest) -> go segs (cur <> [codePoint w]) rest
    flush segs [] = segs
    flush segs cur = T.pack cur : segs
    codePoint w = case readHex (T.unpack w) of
      [(n, "")] -> chr n
      _ -> error ("not a code point: " <> T.unpack w)
