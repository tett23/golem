{- | The underline and the strikethrough of character styles (docs/adr/0270):
the runs and the bands of the lines, the order they are drawn in, their
colour, the tagged PDF, golem preflight, HTML and plain text.
-}
module DecorationsSpec (decorationsTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Decoration (..), Look (..))
import Golem.Length (Sp (..))
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A horizontal book with a style u underlined, s struck, both, and inner styles.
styles :: BS.ByteString
styles =
  BS.concat
    [ "\n[color.swatches]\nred = { cmyk = [0, 100, 100, 0] }\nblue = { cmyk = [100, 0, 0, 0] }\n",
      "\n[character-styles.u]\nunderline = true\n",
      "\n[character-styles.s]\nstrikethrough = { color = \"red\" }\n",
      "\n[character-styles.both]\nunderline = true\nstrikethrough = true\n",
      "\n[character-styles.big]\nsize = \"2zw\"\n",
      "\n[character-styles.up]\nbaseline-shift = \"0.3zw\"\n",
      "\n[character-styles.off]\nunderline = false\n",
      "\n[character-styles.blue-u]\nunderline = true\ncolor = \"blue\"\n",
      "\n[character-styles.thick]\nunderline = { weight = \"0.2zw\" }\n"
    ]

horizontal :: BS.ByteString
horizontal = horizontalStyle <> styles

vertical :: BS.ByteString
vertical = pdfStyle <> styles

boxesOf :: PdfLayout -> [[BoxContent]]
boxesOf pl = [[c | Box _ c <- lineItems (slLine sl)] | sl <- Map.elems (plLines pl)]

layoutOf :: BS.ByteString -> Text -> IO PdfLayout
layoutOf style source = snd <$> layoutOk style source []

-- | The rectangles filled in a content stream, as written: x, y, width, height.
rects :: BS.ByteString -> [[BS.ByteString]]
rects = rulesIn

-- | The content streams of the pages of a PDF of the fake fonts.
contents :: BS.ByteString -> Text -> IO [BS.ByteString]
contents style source = miniPdf fakeProvider False style source [] >>= pageContents

decorationsTests :: TestTree
decorationsTests =
  testGroup
    "underline and strikethrough (docs/adr/0270)"
    [ testCase "I1: the lines change neither the line breaking nor the pages" $ do
        let source t = "漢字漢字" <> t <> "漢字漢字漢字漢字漢字漢字漢字漢字漢字漢字漢字漢字漢字。\n"
        forM_ ["", " "] $ \sep -> do
          a <- layoutOf horizontal (source ("[style u: 漢字" <> sep <> "abc]"))
          c <- layoutOf horizontal (source ("漢字" <> sep <> "abc"))
          map (map bcText) (boxesOf a) @?= map (map bcText) (boxesOf c)
          [lineTarget (slLine sl) | sl <- Map.elems (plLines a)] @?= [lineTarget (slLine sl) | sl <- Map.elems (plLines c)]
          length (plPages a) @?= length (plPages c),
      testCase "I5, I6: the styles inside the basis do not change the line" $ do
        pl <- layoutOf horizontal "[style u: 漢[style big: 字][style up: 漢][style superscript: 2]字]\n"
        let ds = [lkUnderline (bcLook c) | cs <- boxesOf pl, c <- cs, isJust (lkUnderline (bcLook c))]
        length ds @?= 5
        assertBool (show ds) (and (zipWith (==) ds (drop 1 ds))),
      testCase "inner false cuts the line; an inner table is a line of its own basis" $ do
        pl <- layoutOf horizontal "[style u: 漢[style off: 字]漢[style thick: 字]]\n"
        let ds = [lkUnderline (bcLook c) | cs <- boxesOf pl, c <- cs]
        map isJust ds @?= [True, False, True, True]
        case ds of
          [outer, _, _, inner] -> do
            assertBool "another basis" (inner /= outer)
            fmap decWeight inner @?= Just (Sp (unSp 655360 `div` 5))
          other -> assertFailure (show other),
      testCase "the colour: of the line, else of the characters of the basis, else none" $ do
        pl <- layoutOf horizontal "[style s: 漢][style blue-u: 字][style u: 漢]\n"
        let cs = concat (boxesOf pl)
        map (fmap decColor . lkStrikethrough . bcLook) cs @?= [Just (Just "red"), Nothing, Nothing]
        map (fmap decColor . lkUnderline . bcLook) cs @?= [Nothing, Just (Just "blue"), Just Nothing],
      testCase "I1, I8: underline and strikethrough of @style-def are drawn as those of style.toml" $ do
        let source = "漢[style d: 字漢]字\n"
        toml <- contents (horizontalStyle <> "\n[character-styles.d]\nunderline = true\nstrikethrough = true\n") source
        local <- contents horizontalStyle ("@style-def character d underline=true strikethrough=true\n\n" <> source)
        plain <- contents horizontalStyle ("@style-def character d underline=false\n\n" <> source)
        assertBool "the lines are drawn" (toml /= plain)
        local @?= toml,
      testCase "I8: the underline is drawn before the characters, the strikethrough after, as artifacts" $ do
        streams <- contents horizontal "[style both: 漢字]\n"
        case filter (" re f" `BS.isInfixOf`) streams of
          st : _ -> do
            let ls = BC.lines st
                at p = length (takeWhile (not . p) ls)
                firstRect = at (" re f" `BS.isSuffixOf`)
                firstText = at ("BT" ==)
                lastRect = length ls - 1 - length (takeWhile (not . (" re f" `BS.isSuffixOf`)) (reverse ls))
                lastText = length ls - 1 - length (takeWhile ("ET" /=) (reverse ls))
            assertBool "underline first" (firstRect < firstText)
            assertBool "strikethrough last" (lastRect > lastText)
            assertBool "artifacts" ("/Artifact" `BS.isInfixOf` st)
          [] -> assertFailure "no rectangle",
      testCase "I7: horizontal: the top edge of the underline is the offset below the face; ruby does not move it" $ do
        a <- contents horizontal "[style u: 漢字]\n"
        b <- contents horizontal "[style u: [ruby: 漢|かん]字]\n"
        map (take 2 . drop 1) (concatMap rects a) @?= map (take 2 . drop 1) (concatMap rects b),
      testCase "I7: vertical: the underline is right of the readings of its run" $ do
        a <- contents vertical "[style u: 漢字]\n"
        b <- contents vertical "[style u: [ruby: 漢|かん]字]\n"
        let xs st = [ptToRational x | x : _ <- concatMap rects st]
        case (xs a, xs b) of
          (xa : _, xb : _) -> assertBool (show (xa, xb)) (xb > xa)
          other -> assertFailure (show other),
      testCase "I3: two ranges of one value side by side are one band; of other values, two" $ do
        one <- contents horizontal "[style u: 漢][style u: 字]\n"
        length (concatMap rects one) @?= 1
        two <- contents horizontal "[style u: 漢][style thick: 字]\n"
        length (concatMap rects two) @?= 2,
      testCase "I2, I4: a range over two lines is a band on each, and the box of no line is in none" $ do
        st <- contents horizontal ("[style u: " <> T.replicate 14 "漢" <> "]字\n")
        let bands = concatMap rects st
        length bands @?= 2
        -- the second band ends before the last character, which has no line
        case bands of
          [_, [_, _, w, _]] -> assertBool (show bands) (ptToRational w <= 2 * 10)
          other -> assertFailure (show other),
      testCase "a space at the end of a range under a character without the line has no line" $ do
        a <- contents horizontal "[style u: 漢字 ]abc\n"
        b <- contents horizontal "[style u: 漢字]abc\n"
        map (take 3) (concatMap rects a) @?= map (take 3) (concatMap rects b),
      testCase "tagged PDF: a Span with TextDecorationType, nested for both" $ do
        st <- withSystemTempDirectory "golem-decorations" $ \tmp -> do
          writeProject tmp miniManifest horizontal "[style u: 下線] [style both: 両方]\n" []
          r <- pdfStructure (defaultOptions tmp) {optFonts = fakeProvider}
          either (\ds -> assertFailure (show (map diagCode ds)) >> pure "") pure r
        assertBool (T.unpack st) ("TextDecorationType /Underline" `T.isInfixOf` st)
        assertBool (T.unpack st) ("TextDecorationType /LineThrough" `T.isInfixOf` st),
      testCase "golem preflight: an underline of 0.05zw under 2pt characters is a line of 0.1pt (G09018)" $ do
        ds <- withSystemTempDirectory "golem-decorations" $ \tmp -> do
          writeProject tmp miniManifest (horizontal <> "\n[character-styles.tiny]\nsize = \"2pt\"\nunderline = true\n") "[style tiny: 漢字]\n" []
          prDiagnostics <$> preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider}
        let g = [d | d <- ds, diagCode d == DiagnosticCode "G09018"]
        assertBool (show (map diagMessage ds)) (not (null g))
        assertBool (show (map diagMessage g)) (any (("0.1pt" `T.isInfixOf`) . diagMessage) g || any (("0.10" `T.isInfixOf`) . diagMessage) g),
      testCase "HTML: the CSS of an underline and a strikethrough" $ do
        (_, css) <- htmlMini (horizontalStyle <> "\n[character-styles.w]\nunderline = { style = \"wavy\", weight = \"0.08zw\" }\n\n[character-styles.st]\nstrikethrough = true\n") "[style w: a][style st: b]\n"
        assertBool (T.unpack css) ("text-decoration-line: underline; text-decoration-style: wavy; text-decoration-thickness: 0.08em" `T.isInfixOf` css)
        assertBool (T.unpack css) ("text-decoration-line: line-through" `T.isInfixOf` css)
        (_, vcss) <- htmlMini (pdfStyle <> "\n[character-styles.w]\nunderline = { style = \"wavy\", weight = \"0.08zw\" }\n") "[style w: a]\n"
        assertBool (T.unpack vcss) ("text-underline-position: right" `T.isInfixOf` vcss),
      testCase "plain text writes the characters of an underline as they are" $ withSystemTempDirectory "golem-decorations" $ \tmp -> do
        writeProject tmp (miniManifest <> "[targets.text]\n") horizontal "[style u: 下線]の字\n" []
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        assertBool "written" (any ("a.txt" `isSuffixOf`) (brWritten r))
        t <- TIO.readFile (tmp </> "build/text/horizontal/a.txt")
        assertBool (T.unpack t) ("下線の字" `T.isInfixOf` t)
    ]
