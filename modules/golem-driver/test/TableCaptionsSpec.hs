{- | Tables with numbers, captions, column widths and a paragraph style of
their cells, through the outputs (docs/adr/0262): I4, I8, I9, I10 and I11,
and G07114, G07115 and G07116.
-}
module TableCaptionsSpec (tableCaptionsTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (isInfixOf, isSuffixOf, sort)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Support
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A table of two body rows with a caption, after a paragraph.
captioned :: T.Text
captioned = "前。\n\n@caption 題目\n| 項目 | 値 |\n|:---|---:|\n| 幅 | 10 |\n| 高さ | 20 |\n\n後。\n"

-- | A style whose table numbers do not use the chapter, the captions above.
above :: BS.ByteString -> BS.ByteString
above style = style <> "\n[tables]\nnumber = \"表{n}\"\n"

-- | 'above' with the captions below the tables.
below :: BS.ByteString -> BS.ByteString
below style = above style <> "caption-position = \"below\"\n"

-- | The baseline in pt of the first glyph of a character drawn.
baselineOf :: BS.ByteString -> Char -> IO Rational
baselineOf c0 c = case [ptToRational (dY d) | d <- drawnGlyphs c0, dGlyph d == fromEnum c] of
  (y : _) -> pure y
  [] -> assertFailure ("no " <> [c])

-- | The x in pt of the first glyph of a character drawn.
xOf :: BS.ByteString -> Char -> IO Rational
xOf c0 c = case [ptToRational (dX d) | d <- drawnGlyphs c0, dGlyph d == fromEnum c] of
  (x : _) -> pure x
  [] -> assertFailure ("no " <> [c])

approx :: Rational -> Rational -> Assertion
approx a b = assertBool (show (fromRational a :: Double, fromRational b :: Double)) (abs (a - b) < 1 / 100)

content :: BS.ByteString -> T.Text -> IO BS.ByteString
content style source = miniPdf fakeProvider True style source [] >>= fmap BS.concat . inflateAll

-- | The plain text of a one-chapter project.
textOf :: BS.ByteString -> T.Text -> IO T.Text
textOf style source = withSystemTempDirectory "golem-text" $ \tmp -> do
  writeProject tmp (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["text"]})) style source []
  r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  case filter (\p -> ".txt" `isSuffixOf` p && "horizontal" `isInfixOf` p) (brWritten r) of
    [p] -> TIO.readFile p
    other -> assertFailure (show other)

-- | The structure tree of the PDF of a one-chapter project.
structureOf :: BS.ByteString -> T.Text -> IO [T.Text]
structureOf style source = withSystemTempDirectory "golem-structure" $ \tmp -> do
  writeProject tmp miniManifest style source []
  r <- pdfStructure (defaultOptions tmp) {optFonts = fakeProvider}
  either (assertFailure . show . map diagCode) (pure . map T.strip . T.lines) r

-- | The codes of the layout errors of a source.
layoutCodes :: BS.ByteString -> T.Text -> IO [T.Text]
layoutCodes style source = (\es -> [c | (c, _, _, _, _) <- es]) . layoutErrors <$> layoutMini style source []

tableCaptionsTests :: [TestTree]
tableCaptionsTests =
  [ testCase "I8: above, the caption is on the grid line before the header row, and the top rule between them" $ do
      c <- content (above horizontalStyle) captioned
      [mae, dai, kou] <- mapM (baselineOf c) "前題項"
      -- the space before the table goes before the caption
      approx (mae - dai) 30
      approx (dai - kou) 15
      -- the top rule is a + c above the header row (golem-driver ADR 0031), the caption above it
      let centres = sort [ptToRational y + ptToRational h / 2 | [_, y, _, h] <- rulesIn c]
      length centres @?= 3
      approx (last centres) (kou + 11)
      assertBool (show (dai, centres)) (dai > last centres),
    testCase "I8: below, the caption is on the grid line after the last row, and the bottom rule between them" $ do
      c <- content (below horizontalStyle) captioned
      [taka, dai, ato] <- mapM (baselineOf c) "高題後"
      approx (taka - dai) 15
      approx (dai - ato) 30
      let centres = sort [ptToRational y + ptToRational h / 2 | [_, y, _, h] <- rulesIn c]
      length centres @?= 3
      approx (head' centres) (taka - 4)
      assertBool (show (dai, centres)) (dai < head' centres),
    testCase "I8: vertical, the caption above is on the right of the table, below on its left" $ do
      a <- content (above pdfStyle) captioned
      [daiA, kouA] <- mapM (xOf a) "題項"
      assertBool (show (daiA, kouA)) (daiA > kouA)
      b <- content (below pdfStyle) captioned
      [daiB, takaB] <- mapM (xOf b) "題高"
      assertBool (show (daiB, takaB)) (daiB < takaB),
    testCase "I8: above, a table that cannot start with its caption, header and first row on the page goes on whole" $ do
      -- five lines: three paragraphs, then the caption, the header and the first row do not fit
      pdf <- miniPdf fakeProvider True (above fiveLines) "一。\n\n二。\n\n三。\n\n@caption 題目\n| 項目 | 値 |\n|---|---|\n| 幅 | 10 |\n" []
      pages <- pageContents pdf
      [p | (p, c) <- zip [1 :: Int ..] pages, fromEnum '題' `elem` map dGlyph (drawnGlyphs c)] @?= [2]
      [p | (p, c) <- zip [1 :: Int ..] pages, fromEnum '幅' `elem` map dGlyph (drawnGlyphs c)] @?= [2],
    testCase "I8: below, the last row goes on with the caption after the header repeated" $ do
      let rows = T.concat ["| 行" <> T.pack (show i) <> " | " <> T.pack (show i) <> " |\n" | i <- [1 .. 4 :: Int]]
      pdf <- miniPdf fakeProvider True (below fiveLines) ("@caption 題目\n| 項目 | 値 |\n|---|---|\n" <> rows <> "| 末 | 5 |\n") []
      pages <- pageContents pdf
      let on ch = [p | (p, c) <- zip [1 :: Int ..] pages, fromEnum ch `elem` map dGlyph (drawnGlyphs c)]
      on '題' @?= [2]
      on '末' @?= [2]
      on '項' @?= [1, 2],
    testCase "G07116: a caption that does not fit an empty column with the lines it touches; G07042 only without the caption" $ do
      let tall = "| 項目 | 値 |\n|---|---|\n| " <> T.replicate 40 "あ" <> " | 1 |\n"
      layoutCodes fiveLines tall >>= (@?= [])
      layoutCodes (above fiveLines) ("@caption 題目\n" <> tall) >>= (@?= ["G07116"])
      layoutCodes (below fiveLines) ("@caption 題目\n" <> tall) >>= (@?= ["G07116"])
      let taller = "| 項目 | 値 |\n|---|---|\n| " <> T.replicate 60 "あ" <> " | 1 |\n"
      layoutCodes (above fiveLines) ("@caption 題目\n" <> taller) >>= (@?= ["G07042"]),
    testCase "G07114 and G07115 from the widths of @column-widths; none for widths that fit" $ do
      -- 12 characters of 10pt: two columns share 110pt
      layoutCodes horizontalStyle "@column-widths 50% 50%\n| 項目 | 値 |\n|---|---|\n| 幅 | 10 |\n" >>= (@?= [])
      layoutCodes horizontalStyle "@column-widths 50% 51%\n| 項目 | 値 |\n|---|---|\n| 幅 | 10 |\n" >>= (@?= ["G07114"])
      layoutCodes horizontalStyle "@column-widths 1zw 1zw\n| 項目 | 値段 |\n|---|---|\n| 幅 | 10 |\n" >>= (@?= ["G07115", "G07115"])
      layoutCodes horizontalStyle "@column-widths 1zw auto\n| 項目 | 値 |\n|---|---|\n| 幅 | 10 |\n" >>= (@?= ["G07115"]),
    testCase "a column of a width written starts where the widths put it" $ do
      c <- content horizontalStyle "@column-widths 6zw auto\n| 項 | 値 |\n|---|---|\n| 幅 | 10 |\n"
      [kou, chi] <- mapM (xOf c) "項値"
      -- the gap is one character of the cells
      approx (chi - kou) 70,
    testCase "I9: cells at half the size: two lines in one grid line, a pitch of their size apart, the text after on the grid" $ do
      let style = horizontalStyle <> "\n[paragraph-styles.table]\nsize = \"0.5zw\"\n"
          source = "前。\n\n| 項 |\n|---|\n| " <> T.replicate 30 "あ" <> "末 |\n\n後。\n"
      c <- content style source
      [mae, kou, a, sue, ato] <- mapM (baselineOf c) "前項あ末後"
      -- the header and the first row, each on one grid line
      approx (kou - a) 15
      -- the second line of the row 7.5pt below its first
      approx (a - sue) 7.5
      -- the text after the table on the grid: the header, the row of two grid lines, the spaces before and after
      approx (mae - ato) (15 * 6),
    testCase "I9: the cells of a table with @style take the size of that style; the gap is one of its characters" $ do
      let style = horizontalStyle <> "\n[paragraph-styles.small]\nsize = \"0.5zw\"\n"
      c <- content style "@style small\n@column-widths 2zw auto\n| 項 | 値 |\n|---|---|\n| 幅 | 10 |\n"
      [kou, chi] <- mapM (xOf c) "項値"
      approx (chi - kou) 15,
    testCase "I9: table of @style-def paragraph table sets the cells as one of style.toml" $ do
      let source = "前。\n\n| 項 |\n|---|\n| " <> T.replicate 30 "あ" <> "末 |\n\n後。\n"
      toml <- content (horizontalStyle <> "\n[paragraph-styles.table]\nsize = \"0.5zw\"\n") source
      local <- content horizontalStyle ("@style-def paragraph table size=0.5zw\n\n" <> source)
      plain <- content horizontalStyle source
      assertBool "the size changes the cells" (toml /= plain)
      local @?= toml,
    testCase "I11: the side of the caption changes no number, [ref-number] nor [ref-title]" $ do
      let source = "# 章\n\n@label t\n@caption 題目\n| 項目 | 値 |\n|---|---|\n| 幅 | 10 |\n\n表[ref-number t]は[ref-title t]。\n"
      a <- textOf horizontalStyle source
      b <- textOf (horizontalStyle <> "\n[tables]\ncaption-position = \"below\"\n") source
      let refs t = [l | l <- T.lines t, "は" `T.isInfixOf` l]
      refs a @?= ["表1-1は題目。"]
      refs b @?= refs a
      assertBool (T.unpack a) ("表1-1　題目\n項目\t値\n幅\t10" `T.isInfixOf` a)
      assertBool (T.unpack b) ("項目\t値\n幅\t10\n表1-1　題目" `T.isInfixOf` b),
    testCase "tagged PDF: the caption is the first child of Table above, the last below" $ do
      a <- structureOf (above horizontalStyle) captioned
      take 2 (dropWhile (/= "Table") a) @?= ["Table", "Caption"]
      b <- structureOf (below horizontalStyle) captioned
      let table = takeWhile (/= "P") (drop 1 (dropWhile (/= "Table") b))
      assertBool (show table) ("Caption" `elem` table)
      assertBool (show table) (last' [l | l <- table, l `elem` ["Caption", "TR"]] == Just "Caption"),
    testCase "I10: the same source gives the same PDF and diagnostics twice, in parallel and not" $ do
      let source = captioned <> "\n@column-widths 1zw 1zw\n| 項目 | 値 |\n|---|---|\n| 幅 | 10 |\n"
      forM_ [True, False] $ \par -> do
        a <- buildMiniErrors fakeProvider par (above horizontalStyle) source []
        b <- buildMiniErrors fakeProvider par (above horizontalStyle) source []
        map (\d -> (diagCode d, diagMessage d, diagSpan d)) (fst a) @?= map (\d -> (diagCode d, diagMessage d, diagSpan d)) (fst b)
      x <- miniPdf fakeProvider True (above horizontalStyle) captioned []
      y <- miniPdf fakeProvider False (above horizontalStyle) captioned []
      x @?= y
  ]
  where
    head' = \case
      (x : _) -> x
      [] -> 0
    last' = \case
      [] -> Nothing
      xs -> Just (last xs)
