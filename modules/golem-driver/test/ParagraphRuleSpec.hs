-- | The rules of paragraph styles and headings (golem-driver ADR 0027, 0028).
module ParagraphRuleSpec (paragraphRuleTests) where

import Control.Monad (zipWithM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver.Pdf (PdfLayout (..))
import Golem.Layout.Paginate (HeadingBlock (..), PageOut (..), Slotted (..))
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | Two lengths in pt within 1/100pt.
near :: Rational -> Rational -> Assertion
near a b = assertBool (show (fromRational a :: Double, fromRational b :: Double)) (abs (a - b) < 1 / 100)

mmPt :: Rational -> Rational
mmPt mm = mm * 72 / 25.4

-- | The rectangles filled, as x, y, width and height in pt.
rects :: BS.ByteString -> [(Rational, Rational, Rational, Rational)]
rects content = [(ptToRational x, ptToRational y, ptToRational w, ptToRational h) | [x, y, w, h] <- rulesIn content]

-- | The origin of the first glyph of a character.
glyphAt :: BS.ByteString -> Char -> IO (Rational, Rational)
glyphAt content c = case [(ptToRational (dX d), ptToRational (dY d)) | d <- drawnGlyphs content, dGlyph d == fromEnum c] of
  (p : _) -> pure p
  [] -> assertFailure ("no " <> [c])

-- | A style with a paragraph style sec of the rule before written.
withRule :: BS.ByteString -> BS.ByteString -> BS.ByteString
withRule style r = style <> "\n[paragraph-styles.sec]\nrule-before = { " <> r <> " }\n"

section :: T.Text
section = "前。\n\n@style sec\n  節。\n"

paragraphRuleTests :: [TestTree]
paragraphRuleTests =
  [ testCase "horizontal: the rule before over the measure, the inner space to the em box of the first line" $ do
      content <- miniPdf fakeProvider True (withRule horizontalStyle "weight = \"0.5pt\", space-before = \"3pt\", space-after = \"2pt\"") section [] >>= fmap BS.concat . inflateAll
      (_, ySetsu) <- glyphAt content '節'
      (_, yMae) <- glyphAt content '前'
      case rects content of
        [(x, y, w, h)] -> do
          near x (mmPt 20)
          near w 120
          near h 0.5
          -- the em box of 節 starts 8.8pt above its baseline
          near (ySetsu + 8.8 - y) (-2)
          -- one grid line of area: 節 is two lines after 前
          near (yMae - ySetsu) 30
        other -> assertFailure (show other),
    testCase "vertical: a rule down from the top of the column, the inner space to the right of the first line" $ do
      content <- miniPdf fakeProvider True (withRule pdfStyle "weight = \"0.5pt\", space-before = \"3pt\", space-after = \"2pt\"") section [] >>= fmap BS.concat . inflateAll
      (xSetsu, _) <- glyphAt content '節'
      let size = 13 / 4 * 72 / 25.4
      case [r | r@(_, _, w, _) <- rects content, w < 1] of
        [(x, y, w, h)] -> do
          near w 0.5
          near (y + h) (mmPt (182 - 18))
          near h (42 * size)
          near (x - (xSetsu + size / 2)) 2
        other -> assertFailure (show other),
    testCase "length 10zw is ten characters of the size of the paragraph style" $ do
      let style = withRule horizontalStyle "length = \"10zw\"" <> "size = \"0.5zw\"\n"
      content <- miniPdf fakeProvider True style section [] >>= fmap BS.concat . inflateAll
      map (\(_, _, w, _) -> w) (rects content) `nearAll` [50],
    testCase "two columns: the rule from the start of the column of the paragraph" $ do
      content <- miniPdf fakeProvider True (withRule horizontal2 "weight = \"0.5pt\"") "前。\n\n@column-break\n\n@style sec\n  節。\n" [] >>= fmap BS.concat . inflateAll
      map (\(x, _, _, _) -> x) (rects content) `nearAll` [mmPt 20 + 140],
    testCase "start-indent and end-indent of -2zw: 2 characters out of the column on both sides" $ do
      content <- miniPdf fakeProvider True (withRule horizontalStyle "start-indent = \"-2zw\", end-indent = \"-2zw\"") section [] >>= fmap BS.concat . inflateAll
      case rects content of
        [(x, _, w, _)] -> near x (mmPt 20 - 20) >> near w 160
        other -> assertFailure (show other),
    testCase "keep-in-column = false: the rule of the first paragraph of a page in the head margin" $ do
      content <- miniPdf fakeProvider True (withRule horizontalStyle "weight = \"0.5pt\", space-after = \"2pt\", keep-in-column = false") "@style sec\n  節。\n" [] >>= fmap BS.concat . inflateAll
      (_, ySetsu) <- glyphAt content '節'
      let top = 595.2756 - mmPt 18
      -- 節 on the first grid line
      near (ySetsu + 8.8) top
      case rects content of
        [(_, y, _, _)] -> near y (top + 2)
        other -> assertFailure (show other),
    testCase "keep-in-column = false: the rule of the first paragraph of the second column in the head margin (golem-driver ADR 0040)" $ do
      content <- miniPdf fakeProvider True (withRule horizontal2 "weight = \"0.5pt\", space-after = \"2pt\", keep-in-column = false") "前。\n\n@column-break\n\n@style sec\n  節。\n" [] >>= fmap BS.concat . inflateAll
      (xSetsu, ySetsu) <- glyphAt content '節'
      let top = 595.2756 - mmPt 18
      -- 節 on the first grid line of the second column
      near (ySetsu + 8.8) top
      near xSetsu (mmPt 20 + 140)
      case rects content of
        [(x, y, _, _)] -> near x (mmPt 20 + 140) >> near y (top + 2)
        other -> assertFailure (show other),
    testCase "keep-in-column = false, vertical: the rule of the second column in the right margin, not in the gap (golem-driver ADR 0040)" $ do
      let style = replaceIn "characters = 42" "characters = 20" (replaceIn "columns = 1" "columns = 2\ncolumn-gap = \"2zw\"" pdfStyle)
      content <- miniPdf fakeProvider True (withRule style "weight = \"0.5pt\", space-after = \"2pt\", keep-in-column = false") "前。\n\n@column-break\n\n@style sec\n  節。\n" [] >>= fmap BS.concat . inflateAll
      (xSetsu, _) <- glyphAt content '節'
      (xMae, _) <- glyphAt content '前'
      let size = 13 / 4 * 72 / 25.4
          top = mmPt (182 - 18)
      -- 節 on the first grid line of the second column, as 前 of the first
      near xSetsu xMae
      case [r | r@(_, _, w, _) <- rects content, w < 1] of
        [(x, y, _, h)] -> do
          -- right of the right edge of the type area
          near (x - (xSetsu + size / 2)) 2
          -- over the second column only: below the first column and the gap
          near (y + h) (top - 22 * size)
          near h (20 * size)
        other -> assertFailure (show other),
    testCase "a heading rule after: the inner space below the last grid line of the heading" $ do
      let style = horizontalStyle <> "\n[headings.1]\nrule-after = { weight = \"0.5pt\", space-before = \"2pt\" }\n"
          source = "# 章\n\n本文。\n"
      (_, pl) <- layoutOk style source []
      content <- miniPdf fakeProvider True style source [] >>= fmap BS.concat . inflateAll
      (slot, span') <- case [(s, hbSpan hb) | p <- take 1 (plPages pl), (s, SHeading lid _) <- poSlots p, Just hb <- [Map.lookup lid (plHeadings pl)]] of
        (x : _) -> pure x
        [] -> assertFailure "no heading"
      let top = 595.2756 - mmPt 18
          faceEnd = top - (fromIntegral (slot + span' - 1) * 15 + 10)
      case rects content of
        [(_, y, _, h)] -> near (y + h) (faceEnd - 2)
        other -> assertFailure (show other),
    testCase "a dotted rule of a colour: a disc a dot, in the CMYK of the swatch (golem-driver ADR 0028)" $ do
      let style = horizontalStyle <> "\n[color.swatches]\naccent = { cmyk = [0, 100, 100, 0] }\n" <> "\n[paragraph-styles.sec]\nrule-before = { weight = \"1pt\", style = \"dotted\", color = \"accent\", length = \"5zw\" }\n"
      content <- miniPdf fakeProvider True style section [] >>= fmap BS.concat . inflateAll
      let ls = map BC.words (BC.lines content)
      length [l | l <- ls, l == ["f"]] @?= 17
      assertBool "CMYK" (["0", "1", "1", "0", "k", "0", "1", "1", "0", "K"] `elem` ls),
    testCase "G0746: a ruled paragraph longer than a page is broken, with a notice, and the PDF is written" $ do
      let style = withRule fiveLines "weight = \"0.5pt\"" <> "rule-after = { weight = \"0.5pt\" }\n"
          source = "@style sec\n  " <> T.replicate 96 "あ" <> "\n"
      n <- notified miniManifest style source
      [(diagMessage d, diagSeverity d) | d <- g0746 n] @?= [("罫線を持つ段落が版面に入らないため、罫線を省いて分けて組みました（段落スタイル sec）", Notice)]
      assertBool "the PDF" (any ((".pdf" `isSuffixOf`) . fst) (nOutputs n))
      -- neither rule is drawn on any part (golem-driver ADR 0035)
      content <- miniPdf fakeProvider True style source [] >>= fmap BS.concat . inflateAll
      rects content @?= []
      quiet <- notified (miniManifest <> "\n[diagnostics]\nsilence-notices = [\"G0746\"]\n") style source
      g0746 quiet @?= [],
    testCase "G0746: a heading whose rule after does not fit an empty page loses it" $ do
      let style = fiveLines <> "\n[headings.2]\nlines = 3\nrule-before = { space-after = \"5pt\", space-before = \"10pt\" }\nrule-after = { space-before = \"20pt\" }\n"
      n <- notified miniManifest style "## 節\n\n本文。\n"
      map diagMessage (g0746 n) @?= ["罫線を持つ見出しが版面に入らないため、罫線を省きました（見出し 2）"],
    testCase "a book without a broken block has no G0746" $ do
      n <- notified miniManifest (withRule horizontalStyle "weight = \"0.5pt\"") section
      g0746 n @?= [],
    testCase "the spaces of a rule in mm (golem-driver ADR 0035)" $ do
      content <- miniPdf fakeProvider True (withRule horizontalStyle "weight = \"0.5pt\", space-after = \"2mm\"") section [] >>= fmap BS.concat . inflateAll
      (_, ySetsu) <- glyphAt content '節'
      case rects content of
        [(_, y, _, _)] -> near (ySetsu + 8.8 - y) (negate (mmPt 2))
        other -> assertFailure (show other),
    testCase "a space of 1zw is a character of the size of the grid, not of the paragraph style (golem-driver ADR 0035)" $ do
      let ruleY extra = do
            content <- miniPdf fakeProvider True (withRule horizontalStyle "weight = \"0.5pt\", space-after = \"1zw\"" <> extra) section [] >>= fmap BS.concat . inflateAll
            case rects content of
              [(_, y, _, _)] -> pure y
              other -> assertFailure (show other)
      small <- ruleY "size = \"0.5zw\"\n"
      body <- ruleY ""
      content <- miniPdf fakeProvider True (withRule horizontalStyle "weight = \"0.5pt\", space-after = \"1zw\"") section [] >>= fmap BS.concat . inflateAll
      (_, ySetsu) <- glyphAt content '節'
      near small body
      near (ySetsu + 8.8 - body) (-10),
    testCase "HTML: the spaces of a rule in mm are pt; zw is the size of the grid in pt (golem-driver ADR 0035)" $ do
      (_, mmCss) <- htmlMini (withRule horizontalStyle "space-before = \"3mm\"") section
      assertBool (T.unpack mmCss) ("margin-block: 8.504pt 0;" `T.isInfixOf` mmCss)
      (_, css) <- htmlMini (withRule horizontalStyle "space-before = \"1zw\", space-after = \"0.5zw\", length = \"10zw\"" <> "size = \"0.5zw\"\n") section
      assertBool (T.unpack css) ("margin-block: 10pt 5pt;" `T.isInfixOf` css)
      assertBool (T.unpack css) ("width: 10em" `T.isInfixOf` css)
      (_, hCss) <- htmlMini (horizontalStyle <> "\n[headings.2]\nrule-after = { space-before = \"1zw\" }\n") "## 節\n"
      assertBool (T.unpack hCss) ("margin-block: 10pt 0;" `T.isInfixOf` hCss)
      (_, noGrid) <- htmlMini "[paragraph-styles.sec]\nrule-before = { space-before = \"1zw\" }\n" section
      assertBool (T.unpack noGrid) ("margin-block: 1rem 0;" `T.isInfixOf` noGrid),
    testCase "HTML: the rule before is ::before with a block border; 10zw is 10em" $ do
      (_, css) <- htmlMini (withRule horizontalStyle "weight = \"0.5pt\", space-before = \"1zw\", space-after = \"0.5zw\"") section
      assertBool (T.unpack css) ("p.ps-sec::before { content: \"\"; display: block; width: 100%; border-block-start: 0.5pt solid; margin-block: 10pt 5pt; }" `T.isInfixOf` css)
      (_, css10) <- htmlMini (withRule horizontalStyle "length = \"10zw\"") section
      assertBool (T.unpack css10) ("width: 10em" `T.isInfixOf` css10),
    testCase "HTML: a heading rule after is h2::after; a negative start-indent is margin-inline-start" $ do
      (_, css) <- htmlMini (horizontalStyle <> "\n[headings.2]\nrule-after = { start-indent = \"-2zw\" }\n") "## 節\n"
      assertBool (T.unpack css) ("h2::after {" `T.isInfixOf` css)
      assertBool (T.unpack css) ("margin-inline-start: -2em" `T.isInfixOf` css),
    testCase "HTML: the line style and the colour (golem-driver ADR 0028)" $ do
      let swatch = "\n[color.swatches]\naccent = { cmyk = [0, 100, 100, 0] }\n"
          cssOf r = snd <$> htmlMini (horizontalStyle <> swatch <> "\n[paragraph-styles.sec]\nrule-before = { " <> r <> " }\n") section
      dashed <- cssOf "style = \"dashed\", color = \"accent\""
      assertBool (T.unpack dashed) ("border-block-start: 0.3pt dashed rgb(" `T.isInfixOf` dashed)
      thick <- cssOf "style = \"thick-thin\""
      assertBool (T.unpack thick) ("0.3pt double;" `T.isInfixOf` thick)
      dots <- cssOf "style = \"japanese-dots\""
      assertBool (T.unpack dots) ("0.3pt dotted;" `T.isInfixOf` dots)
      wavy <- cssOf "style = \"wavy\""
      assertBool (T.unpack wavy) ("0.3pt solid;" `T.isInfixOf` wavy)
  ]
  where
    notified manifest style source = buildNotified ([("manifest.toml", manifest), ("style.toml", withBodyFont style), ("a.gm", TE.encodeUtf8 source)] <> fakeFontFiles) id
    g0746 n = [d | d <- nDiagnostics n, diagCode d == DiagnosticCode "G0746"]
    nearAll xs ys = do
      length xs @?= length ys
      zipWithM_ near xs ys
