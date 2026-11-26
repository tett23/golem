{- | Figures wrapped along their outlines in the PDF (root ADR 0464): the
lines beside an outline follow it, a figure without one keeps its
widths, and the check of 8 characters takes the shortest line beside it.
-}
module WrapOutlineSpec (tests) where

import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Containers.ListUtils (nubOrd)
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Layout.KnuthPlass (Line (..), Sp)
import Golem.Syntax (DiagnosticCode (..), diagCode)
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- the figure of the tests: images/tiny.jpg is 2 by 3 pixels; at 8zw it is 80pt by 120pt, with no number and so no caption
figureAt :: T.Text -> T.Text -> T.Text
figureAt side outline = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=" <> side <> " width=8zw" <> outline <> "\n\n"

outlines :: BS.ByteString
outlines =
  "\n[outlines.triangle]\npath = \"M 0 3 L 2 3 L 1 0 Z\"\n"
    <> "\n[outlines.oval]\npath = \"M 2 1.5 C 2 2.3284 1.5523 3 1 3 C 0.4477 3 0 2.3284 0 1.5 C 0 0.6716 0.4477 0 1 0 C 1.5523 0 2 0.6716 2 1.5 Z\"\n"
    <> "\n[outlines.sliver]\npath = \"M 0 0 L 0.2 0 L 0.2 3 L 0 3 Z\"\n"

-- the targets of the lines of the layout in order, those beside the figure first
targets :: PdfLayout -> [Sp]
targets pl = [lineTarget (slLine sl) | (_, sl) <- sortOn fst (Map.toList (plLines pl))]

tests :: TestTree
tests =
  testGroup
    "figures wrapped along their outlines (root ADR 0464)"
    [ testCase "root ADR 0464 I1: a figure without an outline sets the lines beside it as before" $ do
        img <- tinyImage
        (_, pl) <- layoutOk (horizontal24 <> outlines) (figureAt "end" "" <> longPara 30) img
        -- 240pt less 80pt and the gap of 10pt, for the 9 grid lines of 120pt and the gap
        take 9 (targets pl) @?= replicate 9 (150 * pt),
      testCase "root ADR 0464 I2, I3, I4: a triangle at the end gives longer lines higher up" $ do
        img <- tinyImage
        (_, pl) <- layoutOk (horizontal24 <> outlines) (figureAt "end" " outline=triangle" <> longPara 30) img
        let beside = take 9 (targets pl)
        assertBool (show beside) (and (zipWith (>=) beside (drop 1 beside)))
        assertBool (show beside) (take 1 beside > drop 8 beside)
        assertBool (show beside) (all (\t -> t >= 150 * pt && t <= 240 * pt) beside),
      testCase "root ADR 0464 I2, I4: an oval in free placement gives its shortest line in the middle, by the pitch of the paragraph" $ do
        img <- tinyImage
        let free = replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" horizontal24
        (_, pl) <- layoutOk (free <> outlines) (figureAt "start" " outline=oval" <> longPara 30) img
        let beside = takeWhile (< 240 * pt) (targets pl)
            shortest = minimum beside
        assertBool (show beside) (length beside >= 5)
        assertBool (show beside) (all (> shortest) (take 1 beside <> drop (length beside - 1) beside))
        assertBool (show beside) (shortest >= 150 * pt),
      testCase "root ADR 0464 I3: a figure whose rectangle leaves fewer than 8 characters is no G07022 when the outline leaves more" $ do
        img <- tinyImage
        let wide = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=18zw"
        r <- layoutMini (horizontal24 <> outlines) (wide <> "\n\n" <> longPara 30) img
        either (map diagCode) (const []) r @?= [DiagnosticCode "G07022"]
        r' <- layoutMini (horizontal24 <> outlines) (wide <> " outline=sliver\n\n" <> longPara 30) img
        either (map diagCode) (const []) r' @?= [],
      testCase "root ADR 0464 A1: the sample of a circle and a star (specimens/outlines) builds, its lines beside each outline of more than one length" $ do
        let dir = "test/fixtures/specimens/outlines/"
        style <- BS.readFile (dir <> "style.toml")
        source <- TE.decodeUtf8 <$> BS.readFile (dir <> "chapters/01-outlines.gm")
        images <- mapM (\f -> ("images/" <> f,) <$> BS.readFile (dir <> "images/" <> f)) ["circle.svg", "star.svg"]
        -- the fonts of the sample are copied in by hand (../README.md); the tests set it in their own
        let withoutFonts = BC.unlines [l | l <- BC.lines style, not ("ja = " `BS.isPrefixOf` l || "latin = " `BS.isPrefixOf` l || l == "[fonts.body]")]
        (_, pl) <- layoutOk withoutFonts source images
        let shorter = filter (< maximum (targets pl)) (targets pl)
        assertBool (show shorter) (length (nubOrd shorter) > 4),
      testCase "root ADR 0464 I1, I6: outline=missing is G02285 once" $ do
        img <- tinyImage
        r <- layoutMini (horizontal24 <> outlines) (figureAt "end" " outline=missing" <> longPara 30) img
        either (map diagCode) (const []) r @?= [DiagnosticCode "G02285"]
    ]
