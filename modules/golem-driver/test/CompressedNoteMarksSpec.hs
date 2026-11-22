-- | The kanji numbers of note marks set flat in vertical text, in the PDF (docs/adr/0381).
module CompressedNoteMarksSpec (compressedNoteMarksTests) where

import Data.ByteString qualified as BS
import Data.Text.Encoding qualified as TE
import Golem.Length (Sp (..))
import Golem.Project.Style (dimToSp, parseDim)
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | The glyphs drawn for a style and a source, the streams of the PDF inflated.
drawnOf :: BS.ByteString -> IO [Drawn]
drawnOf style = drawnGlyphs . BS.concat <$> (miniPdf fakeProvider True style "漢[note: 注。]字\n" [] >>= inflateAll)

-- | The [notes] of a format, flat or not.
notesWith :: Bool -> BS.ByteString
notesWith flat = TE.encodeUtf8 ("\n[notes]\nmark-format = '（{n:kanji}）'\n" <> (if flat then "mark-shape = \"flat\"\n" else ""))

-- | The matrix of the text of a glyph scaled to half along the line, upright in vertical text.
half :: [BS.ByteString]
half = ["1", "0", "0", "0.5"]

compressedNoteMarksTests :: [TestTree]
compressedNoteMarksTests =
  [ testCase "ADR 0381 I1: the kanji of the marks in the text and at the start of the body are drawn half along the line, the parentheses as they are" $ do
      ds <- drawnOf (pdfStyle <> notesWith True)
      let glyphs c = [d | d <- ds, dGlyph d == fromEnum c]
          s = toRational (unSp (maybe 0 (dimToSp 0) (parseDim "13Q"))) / 65536
          m = toRational (unSp (maybe 0 (dimToSp 0) (parseDim "13Q")) `div` 2) / 65536
          near a b = abs (a - b) < 1 / 100
          inMark c = [d | d <- glyphs c, near (ptToRational (dSize d)) m]
      -- the mark in the text and that of the body: the kanji of both flat
      map dMatrix (glyphs '一') @?= [half, half]
      assertBool "the parentheses unscaled" (all ((/= half) . dMatrix) (glyphs '（' <> glyphs '）'))
      case (inMark '（', inMark '一', inMark '）') of
        ([open], [one], [close]) -> do
          -- （ an em of the mark, 一 half of it, ） after them
          let y = ptToRational . dY
          assertBool (show (y open, y one)) (near (y open - y one) m)
          assertBool (show (y one, y close)) (near (y one - y close) (m / 2))
          -- across the line: the column of the mark, as the parentheses
          assertBool "the column" (near (ptToRational (dX one)) (ptToRational (dX open)))
        other -> assertFailure (show other)
      assertBool "the size of the text" (s > m),
    testCase "ADR 0381 I1: horizontal text and marks without mark-shape are not scaled" $ do
      plain <- drawnOf (pdfStyle <> notesWith False)
      [d | d <- plain, dMatrix d == half] @?= []
      horizontal <- drawnOf (horizontalStyle <> notesWith True)
      [d | d <- horizontal, dMatrix d == half] @?= []
  ]
