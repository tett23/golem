{- | The plates Golem draws on (docs/adr ADR 0232): the colour spaces of
the fills and strokes of code blocks, rules and crop marks, as golem
preflight reads them from the objects of the PDF, and G09019 to G09021 on
the PDFs of Golem. The numbers of the tests are those of the invariants of
the ADR.
-}
module PlatesSpec (platesTests) where

import Control.Monad (forM, forM_)
import Data.ByteString qualified as BS
import Data.List ((\\))
import Data.Text qualified as T
import Golem.Driver
import Golem.Pdf (Paint (..), PaintSource (..), PaintSpace (..))
import Golem.Preflight.View (View (..))
import Golem.Syntax
import Support
import System.Directory (copyFile, createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | golem preflight on a one-chapter project with the fake fonts: its view and diagnostics.
preflightOf :: CropMarks -> BS.ByteString -> Maybe BS.ByteString -> T.Text -> IO (View, [Diagnostic])
preflightOf marks style rules source = withSystemTempDirectory "golem-plates" $ \tmp -> do
  writeProject tmp miniManifest style source []
  forM_ rules (BS.writeFile (tmp </> "preflight.toml"))
  p <- preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider, poMarks = marks}
  v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
  pure (v, prDiagnostics p)

pagePaints :: View -> [Paint]
pagePaints v = [p | p <- vwPaints v, paSource p == PageContent]

-- | I1 without the crop marks: DeviceCMYK or DeviceGray.
processOnly :: Paint -> Bool
processOnly p = paSpace p `elem` [PsDeviceCmyk, PsDeviceGray]

codesIn :: [T.Text] -> [Diagnostic] -> [T.Text]
codesIn cs ds = [c | d <- ds, let DiagnosticCode c = diagCode d, c `elem` cs]

-- | I9: neither G09019 nor G09020.
noFontsNorSpots :: [Diagnostic] -> Assertion
noFontsNorSpots ds = codesIn ["G09019", "G09020"] ds @?= []

codeStyle :: BS.ByteString
codeStyle = horizontalStyle <> "\n[color.swatches]\ncode-bg = { cmyk = [0, 0, 0, 8] }\n\n[paragraph-styles.code]\nbackground = \"code-bg\"\n"

-- | The A5 page of horizontalStyle with 3mm of bleed, for the crop marks.
bleedStyle :: BS.ByteString
bleedStyle = replaceIn "size = \"A5\"\n" "size = \"A5\"\nbleed = \"3mm\"\n" horizontalStyle

lineStyles :: [BS.ByteString]
lineStyles = ["solid", "thin-thin", "thick-thick", "thick-thin", "thin-thick", "thick-thin-thick", "thin-thick-thin", "triple", "dashed", "dotted", "japanese-dots", "wavy"]

-- | The paints as a multiset of what they paint with.
painted :: [Paint] -> [(T.Text, PaintSpace, [T.Text])]
painted ps = [(paOperator p, paSpace p, paComponents p) | p <- ps]

platesTests :: [TestTree]
platesTests =
  [ testCase "I1 I2 I9: a code block with a background, a highlighted row, a callout and line numbers" $ do
      (v, ds) <- preflightOf NoMarks codeStyle Nothing "``` numbers=1 highlight=2 callouts=true\na <1>\nb\nc\n```\n\n<1> 説明。\n"
      let ps = pagePaints v
      assertBool (show ps) (not (null ps))
      assertBool (show ps) (all processOnly ps)
      case [p | p <- ps, paOperator p == "f"] of
        background : band : _ -> do
          (paSpace background, paComponents background) @?= (PsDeviceCmyk, ["0", "0", "0", "0.08"])
          -- I2: the band of the highlighted row
          assertBool (show band) (paSpace band == PsDeviceGray || (paSpace band == PsDeviceCmyk && map (`elem` ["0", "0.0"]) (take 3 (paComponents band)) == [True, True, True]))
        other -> assertFailure (show other)
      noFontsNorSpots ds,
    testCase "I1 I9: the twelve line styles of a coloured footnote rule" $
      forM_ lineStyles $ \st -> do
        let style = horizontalStyle <> "\n[color.swatches]\naccent = { cmyk = [0, 100, 100, 0] }\n\n[notes.rule]\nlength = \"5zw\"\nweight = \"1pt\"\ncolor = \"accent\"\nstyle = \"" <> st <> "\"\n"
        (v, ds) <- preflightOf NoMarks style Nothing "漢[note: 注。]字\n"
        let ps = pagePaints v
        assertBool (show (st, ps)) (all processOnly ps)
        assertBool (show st) ((PsDeviceCmyk, ["0", "1", "1", "0"]) `elem` [(paSpace p, paComponents p) | p <- ps])
        noFontsNorSpots ds,
    testCase "I1 I9: the crop marks are all Separation All, and nothing else is a Separation or DeviceN" $ do
      let style = bleedStyle <> "\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n"
          source = "前[color accent: 赤い語]後\n"
      (marked, ds) <- preflightOf JapaneseMarks style Nothing source
      (plain, _) <- preflightOf NoMarks style Nothing source
      -- the hidden folio comes with the marks too (golem-driver ADR 0021); it is text
      let markPaints = [x | x@(op, _, _) <- painted (pagePaints marked) \\ painted (pagePaints plain), op `notElem` ["Tj", "TJ", "'", "\""]]
      assertBool "marks" (not (null markPaints))
      assertBool (show markPaints) (all (\(_, sp, _) -> sp == PsSeparation "All") markPaints)
      assertBool (show (pagePaints plain)) (all processOnly (pagePaints plain))
      assertBool (show (pagePaints marked)) (length [() | p <- pagePaints marked, paSpace p == PsSeparation "All"] == length markPaints)
      noFontsNorSpots ds,
    testCase "I9: the fixture with real fonts" $ withSystemTempDirectory "golem-plates" $ \tmp -> do
      copyTree fixture tmp
      createDirectoryIfMissing True (tmp </> "fonts")
      copyFile "../golem-font/test/fonts/SourceHanSans-Regular_subset.otf" (tmp </> "fonts/ja.otf")
      BS.writeFile (tmp </> "style.toml") (pdfStyle <> "\n[fonts.body]\nja = \"fonts/ja.otf\"\n")
      p <- preflight (defaultPreflightOptions tmp)
      v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
      assertBool "paints" (not (null (vwPaints v)))
      assertBool (show (pagePaints v)) (all processOnly (pagePaints v))
      noFontsNorSpots (prDiagnostics p),
    testCase "G09021: none with swatches of black only, one with a character of a swatch with C" $ do
      let rules = Just "based-on = \"none\"\n[cmy-plates]\nseverity = \"error\"\n"
          style = horizontalStyle <> "\n[color.swatches]\nink = { cmyk = [0, 0, 0, 80] }\ncyan = { cmyk = [30, 0, 0, 100] }\n\n[paragraph-styles.code]\nbackground = \"ink\"\n"
      results <- forM ["一[color ink: 二]三\n\n```\na\n```\n", "一[color ink: 二]三[color cyan: 四]\n\n```\na\n```\n"] $ \source -> do
        (_, ds) <- preflightOf NoMarks style rules source
        pure [diagMessage d | d <- ds, diagCode d == DiagnosticCode "G09021"]
      results @?= [[], ["C、M、Y の版に出る色があります: cyan、DeviceCMYK 0.3 0 0 1（PDF の 1 ページ目）"]]
  ]
