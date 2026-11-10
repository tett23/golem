{- | The paragraph styles of the entries of the table of contents
(docs/adr/0264): toc-1 to toc-6 and toc-page-number through the layout,
the build and the HTML. The fake fonts set a character of 1zw and a digit
of 0.5zw, so the page number 999 of the body is 15pt wide and R is 35pt in
the columns of 120pt of 'horizontalStyle'.
-}
module TocStylesSpec (tocStylesTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Look (..))
import Golem.Length (Sp (..))
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..), TocPage (..))
import Support
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A table of contents of two levels and its headings.
tocSource :: Text
tocSource = "@toc depth=2\n\n# 一\n\n## 節\n\n本文。\n\n# 二\n\n本文。\n"

-- | The lines of the entries of the table of contents: their length, their start and the size of their first box.
entryLines :: PdfLayout -> [(Sp, Sp, Sp)]
entryLines pl =
  [ (lineTarget (slLine sl), slIndent sl, lkSize (bcLook c))
  | (lid, sl) <- Map.toList (plLines pl),
    Map.member lid (plTocPages pl),
    Box _ c : _ <- [lineItems (slLine sl)]
  ]

-- | The width of the boxes of a line.
boxesWidth :: Line -> Sp
boxesWidth l = sum [w | Box w _ <- lineItems l]

-- | Builds the one-chapter project to PDF with the fake fonts: the codes and offsets of its errors.
tocErrors :: BS.ByteString -> Text -> IO [(Text, Maybe FilePath, Int)]
tocErrors style source = withSystemTempDirectory "golem-toc" $ \tmp -> do
  writeProject tmp miniManifest style source []
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFiles = diskFiles tmp, optFonts = fakeProvider}
  pure [(c, siPath <$> Map.lookup (spanFile (diagSpan d)) (brSources r), spanStart (diagSpan d)) | d <- brDiagnostics r, isError d, let DiagnosticCode c = diagCode d]

-- | The byte offset of the first occurrence of a text in another.
offsetOf :: Text -> Text -> Int
offsetOf needle hay = BS.length (TE.encodeUtf8 (fst (T.breakOn needle hay)))

tocStylesTests :: TestTree
tocStylesTests =
  testGroup
    "the paragraph styles of the entries of the table of contents (docs/adr/0264)"
    [ testCase "I1: the built-in styles set the entries as before: of the grid size, indented by l - 1, the lines R short" $ do
        (_, pl) <- layoutOk horizontalStyle tocSource []
        entryLines pl @?= [(85 * pt, 0, 10 * pt), (75 * pt, 10 * pt, 10 * pt), (85 * pt, 0, 10 * pt)],
      testCase "I2: each entry in the size and the indents of toc-<l>" $ do
        let style = horizontalStyle <> "\n[paragraph-styles.toc-2]\nsize = \"0.8zw\"\nindent = \"3zw\"\n"
        (_, pl) <- layoutOk style tocSource []
        [(i, s) | (_, i, s) <- entryLines pl] @?= [(0, 10 * pt), (24 * pt, 8 * pt), (0, 10 * pt)],
      testCase "I2, I3: toc-<l> of @style-def sets the entries as one of style.toml" $ do
        (_, toml) <- layoutOk (horizontalStyle <> "\n[paragraph-styles.toc-2]\nsize = \"0.8zw\"\nindent = \"3zw\"\n\n[paragraph-styles.toc-1]\nend-indent = \"2zw\"\n") tocSource []
        (_, local) <- layoutOk horizontalStyle ("@style-def paragraph toc-2 size=0.8zw indent=3zw\n@style-def paragraph toc-1 end-indent=2zw\n\n" <> tocSource) []
        (_, plain) <- layoutOk horizontalStyle tocSource []
        [(i, s) | (_, i, s) <- entryLines toml] @?= [(0, 10 * pt), (24 * pt, 8 * pt), (0, 10 * pt)]
        assertBool "end-indent shortens the titles" (entryLines toml /= entryLines plain)
        entryLines local @?= entryLines toml,
      testCase "I3, I5: end-indent shortens the title, the page number still ends at the measure" $ do
        let style = horizontalStyle <> "\n[paragraph-styles.toc-1]\nend-indent = \"2zw\"\n"
        (_, pl) <- layoutOk style tocSource []
        [t | (t, _, _) <- entryLines pl] @?= [65 * pt, 75 * pt, 65 * pt]
        [tpNumberStart tp + boxesWidth (tpNumber tp) | tp <- Map.elems (plTocPages pl)] @?= replicate 3 (120 * pt),
      testCase "I4: the leaders of entries of different sizes end at one place" $ do
        let style = horizontalStyle <> "\n[paragraph-styles.toc-2]\nsize = \"0.5zw\"\n"
        (_, pl) <- layoutOk style tocSource []
        let ends = [tpLeaderStart tp + boxesWidth (tpLeader tp) | tp <- Map.elems (plTocPages pl), boxesWidth (tpLeader tp) > 0]
        length ends @?= 3
        assertBool (show ends) (all (\e -> e <= 120 * pt - 15 * pt - 5 * pt && e > 120 * pt - 15 * pt - 5 * pt - 10 * pt) ends)
        -- the reserve is the widest of the levels: of 1zw, the same as the body's
        -- the indent of toc-2 is 1zw of its own size
        [t | (t, _, _) <- entryLines pl] @?= [85 * pt, 80 * pt, 85 * pt],
      testCase "I6: the lines of the entries do not depend on the page numbers" $ do
        let style = fiveLines <> "\n[paragraph-styles.toc-1]\nindent = \"1zw\"\nfirst-line-indent = \"-1zw\"\n"
            source = "@toc\n\n" <> T.concat ["# 章" <> T.singleton k <> T.replicate 9 "題" <> "\n\n本文。\n\n" | k <- "あいうえおかきくけこ"]
        (_, first) <- verseLines style source
        (_, pl) <- layoutOk style source []
        [(lineTarget (slLine sl), slIndent sl) | sl <- Map.elems (plLines pl)] @?= first,
      testCase "I7: a line of exactly one character is no error; one sp shorter is one G07117 for the level, at the table of style.toml" $ do
        let at indent = horizontalStyle <> "\n[paragraph-styles.toc-1]\nindent = \"" <> indent <> "\"\n"
            two = "@toc\n\n# 一\n\n本文。\n\n# 二\n\n本文。\n"
        ok <- tocErrors (at "75pt") two
        ok @?= []
        bad <- tocErrors (at "75.00002pt") two
        let styleText = TE.decodeUtf8 (withBodyFont (at "75.00002pt"))
        [(c, f) | (c, f, _) <- bad] @?= [("G07117", Just "style.toml")]
        -- on the header of the table
        let header = offsetOf "[paragraph-styles.toc-1]" styleText
        assertBool (show (bad, header)) (and [o >= header && o < header + BS.length "[paragraph-styles.toc-1]" | (_, _, o) <- bad]),
      testCase "I7: a level not in the table of contents is not checked; without a table in style.toml, at the @toc" $ do
        let style = horizontalStyle <> "\n[paragraph-styles.body]\nindent = \"0zw\"\n"
            source = "@toc depth=1\n\n# 一\n\n本文。\n"
        tocErrors (style <> "\n[paragraph-styles.toc-2]\nindent = \"200pt\"\n") source >>= (@?= [])
        errs <- tocErrors style ("@style-def paragraph toc-1 indent=80pt\n\n" <> source)
        [(c, f, o) | (c, f, o) <- errs] @?= [("G07117", Just "a.gm", offsetOf "@toc" ("@style-def paragraph toc-1 indent=80pt\n\n" <> source))],
      testCase "HTML: the font of toc-<l> is on the entries of the table of contents, and nothing without one" $ do
        let style = horizontalStyle <> fakeBody <> "\n[fonts.gothic]\nja = \"fonts/b.otf\"\n\n[paragraph-styles.toc-1]\nfont = \"gothic\"\n"
        (_, css) <- htmlMini style tocSource
        assertBool (T.unpack css) ("nav.toc li.toc-1 { font-family:" `T.isInfixOf` css)
        assertBool "not of toc-2" (not ("nav.toc li.toc-2" `T.isInfixOf` css))
        (_, plain) <- htmlMini horizontalStyle tocSource
        assertBool "none" (not ("toc-" `T.isInfixOf` plain))
    ]
